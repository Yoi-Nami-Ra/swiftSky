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
/// frame boundary (FR-029, FR-031).
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

    private let renderer: Renderer
    private let layer: CAMetalLayer

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

    /// Applies queued events. Runs at a frame boundary only, which is what makes FR-031 hold rather
    /// than merely being intended.
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
            case .resized(let new), .backingScaleChanged(let new):
                surface = new
            case .visibilityChanged(let isVisible):
                displayLink?.isPaused = !isVisible
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
    /// here: events, renderability, one clock read, simulation, draw, instrumentation.
    public func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        // 1. Events, at the frame boundary and nowhere else.
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

        // 4. Advance on the fixed timestep. `ticks` may be 0 — the frame still draws (FR-021).
        let ticks = accumulator.consume(elapsed: elapsed)
        state = Simulation.advance(state, ticks: ticks)

        // 5. Draw. A `false` return is a skipped frame: retain accumulated time, count it, carry on
        //    (FR-027a, FR-027b).
        let frameStart = CACurrentMediaTime()
        let presented = renderer.render(state: state, surface: surface, drawable: update.drawable)
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
