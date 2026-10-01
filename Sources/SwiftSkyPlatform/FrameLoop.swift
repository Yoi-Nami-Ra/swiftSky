import QuartzCore
import Synchronization
import SwiftSkyRendering
import SwiftSkySimulation

/// Drives simulation and rendering off the main thread (FR-028).
///
/// This file is where the feature's only real concurrency lives, and it is deliberately the only place
/// that has any. The logic layer stays free of actors, locks, and isolation entirely (FR-012c), which
/// is what keeps its tests synchronous — the complexity is confined here rather than smeared across the
/// codebase. That trade is recorded in plan.md's Complexity Tracking.
///
/// ## Isolation discipline
///
/// Every `private var` below is touched **only** on `thread`'s run loop, from
/// `metalDisplayLink(_:needsUpdate:)` and the helpers it calls. Nothing else may read or write them.
/// The one channel in from the main thread is `pendingEvents`, which is mutex-guarded and drained at a
/// frame boundary (FR-029, FR-031). It carries surface changes and, since 008, the player's move order
/// requests, in the order they happened.
///
/// `@unchecked Sendable` is a genuine opt-out of compiler checking, and worth being explicit about:
/// FR-030 asks for compiler-enforced transfer safety, and it holds for the types that actually cross
/// the boundary — `SurfaceEvent` and `RenderSurface` are value types the compiler verifies. It does not
/// hold for this object, whose safety rests on the discipline described above. Confining that to one
/// file was the point.
public final class FrameLoop: NSObject, @unchecked Sendable {
    // MARK: - Owned by the loop thread

    private var state = SimulationState()
    private var accumulator = TimeAccumulator()
    private var surface = RenderSurface(widthPixels: 0, heightPixels: 0, backingScale: 1)
    private var instrumentation: Instrumentation
    private var lastTimestamp: CFTimeInterval?
    private var framesSinceReport: UInt64 = 0

    /// The display's nominal frame interval, learned from the display link.
    ///
    /// SC-003's budget is "16.6 ms, **or the display's native rate**", so a fixed 1/60 is only correct
    /// on a 60 Hz display. Left hardcoded it silently over-reports success: on a 120 Hz display a 12 ms
    /// frame misses its deadline and is not counted as dropped, making the gate pass by being wrong.
    private var displayInterval: Double?

    /// A shorter gap awaiting a second sighting before it is believed. See `learnDisplayInterval`.
    private var candidateInterval: Double?

    private let renderer: Renderer
    private let layer: CAMetalLayer

    #if SWIFTSKY_INSTRUMENTATION
    /// `--debug-ship-spin` (007 FR-013): feed every tick a full counter-clockwise turn and no thrust, so
    /// the ship turns in place at its top rate. Set once on the main thread before `start()`, which
    /// publishes it to the loop thread; read only on the loop thread afterwards.
    public var debugShipSpin = false

    /// The spin's input: built once, not per frame.
    private static let spinInput = ControlInput(thrust: 0, turn: 1)

    /// Whether the current arrival has been logged (008 FR-015). `true` at launch: there is no order,
    /// so nothing to log. Cleared by every applied order and whenever the ship is not arrived; set when
    /// the arrival line is written. A flag rather than a before/after comparison around the advance,
    /// because `setOrder` evaluates the phase at once (006): an order to the ship's own position is
    /// already arrived before the advance, and would otherwise never be logged (research R6).
    private var arrivalLogged = true
    #endif

    // MARK: - Cross-thread

    /// The only channel from the main thread into the loop. Drained at a frame boundary, never applied
    /// mid-draw (FR-031).
    private let pendingEvents = Mutex<[SurfaceEvent]>([])

    /// Signals that the loop has stopped and no frame is in flight (FR-032).
    private let drained = Mutex<Bool>(false)

    private var thread: Thread?
    private var displayLink: CAMetalDisplayLink?

    /// How often the instrumentation summary is emitted, in frames. Once per ~2 seconds at 60 Hz.
    private static let reportInterval: UInt64 = 120

    public init(renderer: Renderer, layer: CAMetalLayer) {
        self.renderer = renderer
        self.layer = layer
        // Assume 60 Hz until the display tells us otherwise.
        self.instrumentation = Instrumentation(budgetSeconds: 1.0 / 60.0)
        super.init()
    }

    // MARK: - Main-thread API

    /// Hands an event to the loop. Enqueues and returns immediately — the main thread never waits for a
    /// frame, so UI responsiveness cannot be coupled to the frame budget (FR-029).
    public func post(_ event: SurfaceEvent) {
        if case .willTerminate = event {
            stopAndDrain()
            return
        }
        pendingEvents.withLock { $0.append(event) }
    }

    /// Starts the loop. Safe to call once; subsequent calls are ignored.
    public func start() {
        guard thread == nil else { return }
        drained.withLock { $0 = false }

        // A dedicated Thread rather than a DispatchQueue: `CAMetalDisplayLink` attaches to a RunLoop
        // (`add(to:forMode:)`) and a DispatchQueue has none. research.md R4 originally specified a
        // serial queue, which cannot host the display link — corrected during implementation.
        let loopThread = Thread { [weak self] in self?.runLoopMain() }
        loopThread.name = "com.swiftsky.frameLoop"
        loopThread.qualityOfService = .userInteractive
        thread = loopThread
        loopThread.start()
    }

    /// Stops the loop and waits until no frame is in flight, so graphics resources can then be released
    /// safely (FR-032). Teardown ordering is explicit, never left to deallocation order.
    ///
    /// This is the only call that blocks the caller, and it waits for the drain — not for a frame to be
    /// presented.
    public func stopAndDrain() {
        guard let loopThread = thread else { return }
        loopThread.cancel()

        // Bounded wait. A loop that will not drain must not hang the app on exit.
        let deadline = Date().addingTimeInterval(1.0)
        while !drained.withLock({ $0 }), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.005))
        }

        thread = nil
    }

    // MARK: - Loop thread

    private func runLoopMain() {
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        // Pace to the display's actual refresh rate (FR-020). Leaving the range at its default lets
        // the system pick, which is what makes variable-refresh displays and Low Power Mode work with
        // no special handling.
        link.add(to: .current, forMode: .default)
        displayLink = link

        // The run loop needs at least one source to avoid returning immediately; the display link is
        // that source. `Thread.isCancelled` is checked each turn so cancellation is honoured promptly.
        while !Thread.current.isCancelled {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        }

        link.isPaused = true
        link.remove(from: .current, forMode: .default)
        link.invalidate()
        displayLink = nil

        instrumentation.summary()
        drained.withLock { $0 = true }
    }

    /// Narrows the frame budget towards the display's true interval. Allocation-free.
    ///
    /// The **minimum** observed gap is taken, not the mean, and that is the whole trick: consecutive
    /// `targetTimestamp`s are *scheduled* presentation times, so a gap is always a whole number of
    /// display intervals. A missed frame can only ever double a gap, never halve it — so the minimum
    /// converges on one interval and a dropped frame cannot inflate the budget that is supposed to
    /// detect it. Averaging would let exactly the frames SC-003 forbids raise the bar they must clear.
    ///
    /// On a variable-refresh display this settles on the fastest rate the display actually ran at,
    /// which is the reading of "native rate" that makes the gate strictest.
    private func learnDisplayInterval(from gap: Double) {
        // A paused-and-resumed loop, a first frame, or a stalled display produces gaps that are not
        // display intervals at all. Only plausible ones teach us anything.
        guard gap >= Self.fastestPlausibleInterval, gap <= Self.slowestPlausibleInterval else { return }
        if let known = displayInterval, known <= gap { return }

        // Shorter than we believed — but adopted only once a second gap agrees, because a single
        // anomalous short gap does occur around startup and would otherwise lock in a budget the
        // display never actually meets, failing SC-003 for a reason that is purely an artefact.
        // Measurement on a 120 Hz panel: real gaps are exactly 8.333333 ms at p10, median and p90, so
        // a genuine interval always has a partner and a spurious one never does.
        if let candidate = candidateInterval, abs(candidate - gap) <= candidate * Self.intervalTolerance {
            let interval = min(candidate, gap)
            displayInterval = interval
            candidateInterval = nil
            instrumentation.updateBudget(seconds: interval)
        } else {
            candidateInterval = gap
        }
    }

    /// Drops what was learned, so the next frames relearn on the display we are now on.
    private func forgetDisplayInterval() {
        displayInterval = nil
        candidateInterval = nil
        instrumentation.updateBudget(seconds: 1.0 / 60.0)
    }

    /// How close two gaps must be to count as the same display interval.
    private static let intervalTolerance = 0.05

    /// 250 Hz and 20 Hz. Nothing outside this is a real display interval.
    private static let fastestPlausibleInterval = 1.0 / 250.0
    private static let slowestPlausibleInterval = 1.0 / 20.0

    /// Applies queued events. Runs at a frame boundary only, which is what makes FR-031 hold rather
    /// than merely being intended.
    ///
    /// Events apply in queue order, so a move order request is converted against the surface as it
    /// stands after every earlier event in the same drain, and of several requests the last one is the
    /// order flown (008 FR-005, FR-006, contracts C12).
    ///
    /// Allocates nothing when the queue is empty, which is the common case.
    private func applyPendingEvents() {
        let events = pendingEvents.withLock { queue -> [SurfaceEvent] in
            guard !queue.isEmpty else { return [] }
            defer { queue.removeAll(keepingCapacity: true) }
            return queue
        }
        guard !events.isEmpty else { return }

        for event in events {
            switch event {
            case .resized(let new):
                surface = new
            case .backingScaleChanged(let new):
                surface = new
                // A backing-property change is the signal that the surface may have moved to another
                // display (FR-031), which may refresh at a different rate. Relearn it rather than
                // keeping a budget belonging to the display we left.
                forgetDisplayInterval()
            case .visibilityChanged(let isVisible):
                displayLink?.isPaused = !isVisible
                #if SWIFTSKY_INSTRUMENTATION
                // Frames from before the pause are not the last second's (003 FR-008).
                if isVisible { instrumentation.restartOverlayWindow() }
                #endif
            case .moveOrderRequested(let request):
                let outcome = request.apply(to: &state, on: surface)
                // The order's planned path rides along for the Debug log line (010 FR-014).
                instrumentation.recordOrder(outcome, viewPoint: request.viewPoint, path: state.plannedPath)
                #if SWIFTSKY_INSTRUMENTATION
                if case .ordered = outcome { arrivalLogged = false }
                #endif
            case .willTerminate:
                // Handled on the main thread by `post`, which routes it to `stopAndDrain`.
                break
            }
        }
    }
}

// MARK: - CAMetalDisplayLinkDelegate

extension FrameLoop: CAMetalDisplayLinkDelegate {
    /// One frame. The normative ordering is in contracts/frame-loop.md and is deliberately literal
    /// here: events, renderability, one clock read, the debug overlay's snapshot (003), simulation,
    /// draw, instrumentation.
    public func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        // 1. Events, at the frame boundary and nowhere else. A move order applied here is flown by this
        //    frame's step-4 advance (008 FR-005, SC-005).
        applyPendingEvents()

        // 2. Nothing to draw into.
        guard surface.isRenderable else {
            instrumentation.recordSkipped()
            return
        }

        // 3. Read the clock exactly once per frame (FR-033). Every downstream decision uses this one
        //    value, which is what keeps the simulation deterministic regardless of scheduling.
        let now = update.targetTimestamp
        let elapsed: Double
        if let previous = lastTimestamp {
            elapsed = now - previous
        } else {
            elapsed = 0
        }
        lastTimestamp = now
        learnDisplayInterval(from: elapsed)

        // 3a. The debug overlay's statistics, four times a second, from this frame's one timestamp
        //     (003 FR-006, FR-008). A plain value handed across — the renderer never reads the
        //     instrumentation (FR-015). Debug/profiling only.
        #if SWIFTSKY_INSTRUMENTATION
        if let statistics = instrumentation.overlayStatistics(at: now) {
            renderer.updateDebugOverlay(statistics)
        }
        #endif

        // 4. Advance on the fixed timestep. `ticks` may be 0 — the frame still draws (FR-021).
        let ticks = accumulator.consume(elapsed: elapsed)
        #if SWIFTSKY_INSTRUMENTATION
        // `--debug-ship-spin` uses the explicit-input entry point, which leaves any order alone (006).
        if debugShipSpin {
            state = Simulation.advance(state, ticks: ticks, input: Self.spinInput)
        } else {
            state = Simulation.advance(state, ticks: ticks)
        }
        #else
        state = Simulation.advance(state, ticks: ticks)
        #endif

        // 4a. Each arrival is logged once (008 FR-015, SC-007b): one comparison and one flag test, in
        //     debug and profiling builds only.
        #if SWIFTSKY_INSTRUMENTATION
        if state.autopilot.phase == .arrived {
            if !arrivalLogged {
                instrumentation.recordArrival(position: state.ship.position, tickCount: state.tickCount)
                arrivalLogged = true
            }
        } else {
            arrivalLogged = false
        }
        #endif

        // 5. Draw. A `false` return is a skipped frame: retain accumulated time, count it, carry on
        //    (FR-027a, FR-027b).
        let frameStart = CACurrentMediaTime()
        let presented = renderer.render(state: state, surface: surface, drawable: update.drawable, timestamp: now)
        let frameSeconds = CACurrentMediaTime() - frameStart

        // 6. Instrumentation. Debug/profiling only, log only, allocation-free (FR-021d–f).
        if presented {
            instrumentation.recordPresented(frameSeconds: frameSeconds, tickCount: state.tickCount)
        } else {
            instrumentation.recordSkipped()
        }

        framesSinceReport += 1
        if framesSinceReport >= Self.reportInterval {
            framesSinceReport = 0
            instrumentation.summary()
        }
    }
}
