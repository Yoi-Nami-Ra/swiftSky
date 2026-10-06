import QuartzCore
import Synchronization
import SwiftSkyRendering
import SwiftSkySimulation

#if SWIFTSKY_INSTRUMENTATION
import SwiftSkyAllocationCounter
#endif

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
/// Since 012, instrumented builds have a second, lock-free channel the other way: `stallProbe`, whose
/// observers run on the main thread and whose figures this loop takes, through atomics, at each summary.
/// It is installed in `start()` and removed in `stopAndDrain()`, both on the main thread.
///
/// `@unchecked Sendable` is a genuine opt-out of compiler checking, and worth being explicit about:
/// FR-030 asks for compiler-enforced transfer safety, and it holds for the types that actually cross
/// the boundary — `SurfaceEvent` and `RenderSurface` are value types the compiler verifies. It does not
/// hold for this object, whose safety rests on the discipline described above. Confining that to one
/// file was the point.
public final class FrameLoop: NSObject, @unchecked Sendable {
    // MARK: - Owned by the loop thread

    private var state = SimulationState()

    /// The ship's pose one tick before `state`, for drawing between the two (013 FR-005). The initial
    /// pose until the first tick.
    private var previousPose = ShipPose(SimulationState().ship)
    private var accumulator = TimeAccumulator()
    private var surface = RenderSurface(widthPixels: 0, heightPixels: 0, backingScale: 1)
    private var instrumentation: Instrumentation
    private var lastTimestamp: CFTimeInterval?
    private var framesSinceReport: UInt64 = 0

    /// The display's frame interval, learned from the display link's gaps (016). See
    /// `DisplayIntervalLearner` for why it is learned and the rules that keep stray gaps out.
    private var displayInterval = DisplayIntervalLearner()

    private let renderer: Renderer
    private let layer: CAMetalLayer

    #if SWIFTSKY_INSTRUMENTATION
    /// The main thread's busy stretches (012). Sendable; the instrumentation holds the same instance.
    private let stallProbe = MainThreadStallProbe()
    #endif

    #if SWIFTSKY_INSTRUMENTATION
    /// `--debug-ship-spin` (007 FR-013): feed every tick a full counter-clockwise turn and no thrust, so
    /// the ship turns in place at its top rate. Set once on the main thread before `start()`, which
    /// publishes it to the loop thread; read only on the loop thread afterwards.
    public var debugShipSpin = false

    /// `--no-interpolation` (013 FR-008): draw the ship at its latest tick's pose. Set and published like
    /// `debugShipSpin`.
    public var debugNoInterpolation = false

    /// The spin's input: built once, not per frame.
    private static let spinInput = ControlInput(thrust: 0, turn: 1)

    /// Whether the current arrival has been logged (008 FR-015). `true` at launch: there is no order,
    /// so nothing to log. Cleared by every applied order and whenever the ship is not arrived; set when
    /// the arrival line is written. A flag rather than a before/after comparison around the advance,
    /// because `setOrder` evaluates the phase at once (006): an order to the ship's own position is
    /// already arrived before the advance, and would otherwise never be logged (research R6).
    private var arrivalLogged = true

    /// An arrival found in step 4a, written in step 6. Writing a log line allocates (the `Logger` argument
    /// buffer, and the system's encoding of the message), so the line waits until the counted stretch has
    /// closed, like the summary (011 FR-006). A plain optional value: holding it allocates nothing.
    private var pendingArrival: (position: Vector2, tickCount: UInt64)?

    /// The order lines of the requests applied in step 1, written in step 6 for the same reason. Capacity
    /// for several is reserved up front, so noting one allocates nothing; more requests than that in one
    /// drain grow the array, counted as the event's (011 FR-004).
    private var pendingOrderLines: [OrderLogLine] = {
        var lines: [OrderLogLine] = []
        lines.reserveCapacity(8)
        return lines
    }()
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
        #if SWIFTSKY_INSTRUMENTATION
        self.instrumentation = Instrumentation(budgetSeconds: 1.0 / 60.0, stallProbe: stallProbe)
        #else
        self.instrumentation = Instrumentation(budgetSeconds: 1.0 / 60.0)
        #endif
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
        #if SWIFTSKY_INSTRUMENTATION
        stallProbe.install()
        #endif

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
        #if SWIFTSKY_INSTRUMENTATION
        stallProbe.uninstall()
        #endif
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
        #if SWIFTSKY_INSTRUMENTATION
        installAllocationCounter()
        #endif

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
            // A paused link delivers no frames, and events are otherwise applied only inside one — so the
            // `visibilityChanged(true)` that should resume it would wait forever, and the loop would stay
            // paused after the window was hidden once (found by 012's Thread Sanitizer run, T014). While
            // paused no frame is in flight, so this turn is itself a frame boundary (FR-031).
            if link.isPaused {
                _ = applyPendingEvents()
                #if SWIFTSKY_INSTRUMENTATION
                writePendingLogLines()
                #endif
            }
        }

        link.isPaused = true
        link.remove(from: .current, forMode: .default)
        link.invalidate()
        displayLink = nil

        instrumentation.summary()
        #if SWIFTSKY_INSTRUMENTATION
        sky_alloc_counter_uninstall()
        #endif
        drained.withLock { $0 = true }
    }

    #if SWIFTSKY_INSTRUMENTATION
    /// Installs the draw-path allocation counter for the life of the loop and proves it is counting
    /// (011 research R7, R8). Runs on the loop thread, before the display link delivers a frame.
    ///
    /// The self-test is one counted stretch around exactly one allocation. A counter that is not
    /// counting would report zero allocations on every frame — exactly the result check 25 is looking
    /// for — so its summaries say `allocs=unavailable` unless this passes.
    private func installAllocationCounter() {
        var ready = false
        if sky_alloc_counter_install(nil, 0) {
            sky_alloc_frame_begin()
            sky_alloc_probe()
            let counts = sky_alloc_frame_end()
            ready = counts.app == 1 && counts.graphics == 0
        }
        instrumentation.markAllocationCounter(ready: ready)
    }
    #endif

    /// Applies queued events. Runs at a frame boundary only, which is what makes FR-031 hold rather
    /// than merely being intended.
    ///
    /// Events apply in queue order, so a move order request is converted against the surface as it
    /// stands after every earlier event in the same drain, and of several requests the last one is the
    /// order flown (008 FR-005, FR-006, contracts C12).
    ///
    /// Allocates nothing when the queue is empty, which is the common case.
    ///
    /// - Returns: whether at least one event was applied, so the frame's allocations can be reported
    ///   apart from those of frames without one (011 FR-004).
    private func applyPendingEvents() -> Bool {
        let events = pendingEvents.withLock { queue -> [SurfaceEvent] in
            guard !queue.isEmpty else { return [] }
            defer { queue.removeAll(keepingCapacity: true) }
            return queue
        }
        guard !events.isEmpty else { return false }

        for event in events {
            switch event {
            case .resized(let new):
                surface = new
                resizeDrawables(to: new)
            case .backingScaleChanged(let new):
                surface = new
                resizeDrawables(to: new)
                // A backing-property change is the signal that the surface may have moved to another
                // display (FR-031), which may refresh at a different rate. Relearn it rather than
                // keeping a budget belonging to the display we left.
                instrumentation.updateBudget(seconds: displayInterval.forget())
            case .visibilityChanged(let isVisible):
                displayLink?.isPaused = !isVisible
                #if SWIFTSKY_INSTRUMENTATION
                // Frames from before the pause are not the last second's (003 FR-008).
                if isVisible { instrumentation.restartOverlayWindow() }
                #endif
            case .moveOrderRequested(let request):
                #if SWIFTSKY_INSTRUMENTATION
                let outcome = request.apply(to: &state, on: surface)
                // The order's planned path rides along for the Debug log line (010 FR-014), noted now and
                // written after the counted stretch.
                pendingOrderLines.append(OrderLogLine(outcome, viewPoint: request.viewPoint, path: state.plannedPath))
                if case .ordered = outcome { arrivalLogged = false }
                #else
                _ = request.apply(to: &state, on: surface)
                #endif
            case .willTerminate:
                // Handled on the main thread by `post`, which routes it to `stopAndDrain`.
                break
            }
        }
        return true
    }

    #if SWIFTSKY_INSTRUMENTATION
    /// Writes the order and arrival lines noted inside a counted stretch, in the order they happened:
    /// orders (step 1), then the arrival (step 4a). Called once the stretch has closed, and after the
    /// paused loop's own event drain.
    private func writePendingLogLines() {
        if !pendingOrderLines.isEmpty {
            for line in pendingOrderLines {
                instrumentation.recordOrder(line)
            }
            pendingOrderLines.removeAll(keepingCapacity: true)
        }
        if let arrival = pendingArrival {
            pendingArrival = nil
            instrumentation.recordArrival(position: arrival.position, tickCount: arrival.tickCount)
        }
    }
    #endif

    /// Sizes the layer's drawables to the surface, on the loop thread (012 T016). Releasing the old
    /// drawables is synchronous GPU-resource teardown; done here it costs the loop an event frame, where on
    /// the main thread it stalled live resize. The frame that applies the event still draws into the
    /// drawable the display link handed it at the old size; the next one gets the new size.
    private func resizeDrawables(to new: RenderSurface) {
        guard new.isRenderable else { return }
        layer.drawableSize = CGSize(width: Double(new.widthPixels), height: Double(new.heightPixels))
    }

    /// How far a frame got: what step 6 records for it.
    private enum FrameOutcome {
        /// Step 2 found no surface to draw into. Counted as skipped; the summary cadence does not advance.
        case notRenderable
        /// The renderer declined the frame (FR-027a, FR-027b). Counted as skipped.
        case skipped
        /// Drawn and presented, in `seconds`.
        case presented(seconds: Double)
    }
}

// MARK: - CAMetalDisplayLinkDelegate

extension FrameLoop: CAMetalDisplayLinkDelegate {
    /// One frame. The normative ordering is in contracts/frame-loop.md and is deliberately literal
    /// here: events, renderability, one clock read, the debug overlay's snapshot (003), simulation,
    /// draw, instrumentation.
    ///
    /// Since 011, steps 1–5 are one counted stretch: every heap allocation the loop's thread makes in them
    /// is counted, the graphics framework's apart (011 FR-001, FR-003). Step 6 runs after the stretch has
    /// closed, so writing the summary is never counted against the frame (011 FR-006, research R6).
    public func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        #if SWIFTSKY_INSTRUMENTATION
        sky_alloc_frame_begin()
        let (outcome, appliedEvent) = drawFrame(update)
        let allocations = sky_alloc_frame_end()
        instrumentation.recordFrameAllocations(
            app: allocations.app,
            graphics: allocations.graphics,
            appliedEvent: appliedEvent
        )
        writePendingLogLines()
        #else
        let (outcome, _) = drawFrame(update)
        #endif

        // 6. Instrumentation. Debug/profiling only, log only, allocation-free (FR-021d–f).
        switch outcome {
        case .notRenderable:
            instrumentation.recordSkipped()
            return
        case .skipped:
            instrumentation.recordSkipped()
        case .presented(let seconds):
            instrumentation.recordPresented(frameSeconds: seconds, tickCount: state.tickCount)
        }

        framesSinceReport += 1
        if framesSinceReport >= Self.reportInterval {
            framesSinceReport = 0
            instrumentation.summary()
        }
    }

    /// Steps 1–5 of one frame: the part the allocation counter counts (011 research R6).
    private func drawFrame(_ update: CAMetalDisplayLink.Update) -> (outcome: FrameOutcome, appliedEvent: Bool) {
        // 1. Events, at the frame boundary and nowhere else. A move order applied here is flown by this
        //    frame's step-4 advance (008 FR-005, SC-005).
        let appliedEvent = applyPendingEvents()

        // 2. Nothing to draw into. Recorded as skipped in step 6.
        guard surface.isRenderable else {
            return (.notRenderable, appliedEvent)
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
        if let budget = displayInterval.observe(gap: elapsed) {
            instrumentation.updateBudget(seconds: budget)
        }

        // 3a. The debug overlay's statistics, four times a second, from this frame's one timestamp
        //     (003 FR-006, FR-008). A plain value handed across — the renderer never reads the
        //     instrumentation (FR-015). With them, the ship and its order as of the latest completed
        //     tick: `state` before step 4 advances it, never the drawn pose (015 FR-005, 013).
        //     Debug/profiling only.
        #if SWIFTSKY_INSTRUMENTATION
        if let statistics = instrumentation.overlayStatistics(at: now) {
            renderer.updateDebugOverlay(statistics, ship: DebugOverlayShip(state))
        }
        #endif

        // 4. Advance on the fixed timestep. `ticks` may be 0 — the frame still draws (FR-021).
        let ticks = accumulator.consume(elapsed: elapsed)
        #if SWIFTSKY_INSTRUMENTATION
        // `--debug-ship-spin` uses the explicit-input entry point, which leaves any order alone (006).
        if debugShipSpin {
            state = Simulation.advance(state, ticks: ticks, input: Self.spinInput, previousPose: &previousPose)
        } else {
            state = Simulation.advance(state, ticks: ticks, previousPose: &previousPose)
        }
        #else
        state = Simulation.advance(state, ticks: ticks, previousPose: &previousPose)
        #endif

        // 4b. The pose the ship is drawn at: between the last two ticks, by how far the next tick has
        //     progressed (013 FR-006). Up to one tick behind the simulation, never ahead of it.
        #if SWIFTSKY_INSTRUMENTATION
        let interpolates = !debugNoInterpolation
        #else
        let interpolates = true
        #endif
        let tickPose = ShipPose(state.ship)
        let shipPose = interpolates
            ? ShipPose.blended(from: previousPose, to: tickPose, fraction: accumulator.tickFraction)
            : tickPose
        // The latest tick at or behind the drawn pose, from the same switch, so the order overlay's
        // reached points always agree with the sprite (014 contract C4, FR-012).
        let poseTick = interpolates && state.tickCount > 0 ? state.tickCount - 1 : state.tickCount

        // 4a. Each arrival is logged once (008 FR-015, SC-007b): one comparison and one flag test, in
        //     debug and profiling builds only. Noted here, written after the counted stretch.
        #if SWIFTSKY_INSTRUMENTATION
        if state.autopilot.phase == .arrived {
            if !arrivalLogged {
                pendingArrival = (state.ship.position, state.tickCount)
                arrivalLogged = true
            }
        } else {
            arrivalLogged = false
        }
        #endif

        // 5. Draw. A `false` return is a skipped frame: retain accumulated time, count it, carry on
        //    (FR-027a, FR-027b).
        let frameStart = CACurrentMediaTime()
        let presented = renderer.render(
            state: state,
            shipPose: shipPose,
            poseTick: poseTick,
            surface: surface,
            drawable: update.drawable,
            timestamp: now
        )
        let frameSeconds = CACurrentMediaTime() - frameStart
        return (presented ? .presented(seconds: frameSeconds) : .skipped, appliedEvent)
    }
}
