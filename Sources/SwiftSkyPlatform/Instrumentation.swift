import os

/// Per-frame measurement for the Principle III gates (FR-021d).
///
/// Compiled only when `SWIFTSKY_INSTRUMENTATION` is defined — debug and profiling builds, never
/// release (FR-021e). Emits to the log and never to the rendered surface or a platform-UI view, so
/// FR-001 and FR-007 stay absolute even while measuring.
///
/// Allocates nothing on the per-frame path (FR-021f): counters are inline integers on a struct the
/// loop owns, and the only string formatting happens in `summary()`, which the loop calls once per
/// reporting interval rather than once per frame.
///
/// Skipped and dropped frames are counted separately, because conflating them would make SC-003
/// unmeasurable: SC-003 forbids both during an idle session while FR-027a mandates skipping under
/// backpressure (FR-027c).
struct Instrumentation {
    #if SWIFTSKY_INSTRUMENTATION

    private static let log = Logger(subsystem: "com.swiftsky.app", category: "frame")

    /// Frames presented successfully.
    private(set) var presentedFrames: UInt64 = 0

    /// Frames the app declined to draw because no drawable was available (FR-027a).
    private(set) var skippedFrames: UInt64 = 0

    /// Frames that missed their display deadline because work overran the budget (FR-027c).
    private(set) var droppedFrames: UInt64 = 0

    private(set) var totalFrameSeconds: Double = 0
    private(set) var worstFrameSeconds: Double = 0

    /// Tick count last observed crossing the logic→render boundary. Logged so SC-020's monotonic
    /// increase is observable rather than merely asserted.
    private(set) var lastTickCount: UInt64 = 0

    /// The frame budget a frame must fit inside to avoid counting as dropped.
    private var budgetSeconds: Double

    init(budgetSeconds: Double) {
        self.budgetSeconds = budgetSeconds
    }

    /// Records a presented frame. No allocation.
    mutating func recordPresented(frameSeconds: Double, tickCount: UInt64) {
        presentedFrames += 1
        totalFrameSeconds += frameSeconds
        if frameSeconds > worstFrameSeconds { worstFrameSeconds = frameSeconds }
        if frameSeconds > budgetSeconds { droppedFrames += 1 }
        lastTickCount = tickCount
    }

    /// Records a frame skipped for want of a drawable. No allocation.
    mutating func recordSkipped() {
        skippedFrames += 1
    }

    /// Updates the display's refresh interval when the surface moves to a different display.
    mutating func updateBudget(seconds: Double) {
        budgetSeconds = seconds
    }

    /// Emits a summary. Called on a reporting interval, never per frame — this is the only place that
    /// formats a string.
    ///
    /// `notice`, not `info`, and that is the entire reason FR-021d's output was invisible: `info`-level
    /// messages live in a memory ring buffer and are not written to the log store, so `log show` — which
    /// reads the store — finds nothing, with no error to say why. `notice` is the lowest level that
    /// persists by default, so the measurements can simply be read back after a run. Debug and
    /// profiling builds only (FR-021e), so this adds no release logging.
    func summary() {
        let mean = presentedFrames > 0 ? totalFrameSeconds / Double(presentedFrames) : 0
        Self.log.notice(
            """
            frames=\(self.presentedFrames, privacy: .public) \
            skipped=\(self.skippedFrames, privacy: .public) \
            dropped=\(self.droppedFrames, privacy: .public) \
            mean=\(mean * 1000, privacy: .public)ms \
            worst=\(self.worstFrameSeconds * 1000, privacy: .public)ms \
            budget=\(self.budgetSeconds * 1000, privacy: .public)ms \
            ticks=\(self.lastTickCount, privacy: .public)
            """
        )
    }

    #else

    // Release: every member is an empty inlinable no-op, so the optimiser leaves nothing behind for
    // SC-004a's symbol inspection to find.
    init(budgetSeconds: Double) {}
    @inline(__always) mutating func recordPresented(frameSeconds: Double, tickCount: UInt64) {}
    @inline(__always) mutating func recordSkipped() {}
    @inline(__always) mutating func updateBudget(seconds: Double) {}
    @inline(__always) func summary() {}

    #endif
}
