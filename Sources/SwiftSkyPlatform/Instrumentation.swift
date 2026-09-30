import os
import SwiftSkyRendering

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

    /// Mean and worst over the last second, for the debug overlay (003 FR-004). Fed by
    /// `recordPresented` and restarted with the budget, so it never mixes two budgets' frames (FR-008).
    private var window = FrameTimeWindow()

    /// When the overlay's next snapshot is due: four times a second (003 FR-006).
    private var schedule = OverlayRefreshSchedule()

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
        window.record(frameSeconds: frameSeconds)
    }

    /// Records a frame skipped for want of a drawable. No allocation.
    mutating func recordSkipped() {
        skippedFrames += 1
    }

    /// Updates the frame budget, and **restarts the measurement**.
    ///
    /// The restart is the point, not a side effect. Counters accumulated against the previous budget
    /// are not comparable with ones accumulated against the new budget, and mixing them produces a
    /// self-contradictory report: a real run showed `worst=11.0ms dropped=0 budget=8.3ms`, because that
    /// worst frame was judged against the 16.6 ms default in force before the display's true interval
    /// was known. A reader cannot tell from such a line whether SC-003 was met. Discarding the
    /// pre-budget-change frames makes every reported number belong to one budget.
    mutating func updateBudget(seconds: Double) {
        budgetSeconds = seconds
        presentedFrames = 0
        skippedFrames = 0
        droppedFrames = 0
        totalFrameSeconds = 0
        worstFrameSeconds = 0
        restartOverlayWindow()
    }

    /// The debug overlay's snapshot, on a due refresh only; `nil` on every other frame (003 FR-006).
    ///
    /// The budget, dropped, skipped and tick values are the same fields `summary()` logs, so the
    /// overlay and the log cannot disagree about them (003 FR-013). Taken before the frame is drawn, so
    /// it describes frames up to the previous one — a frame's time is known only once it has been drawn.
    /// No allocation: a closed bucket and a struct copy.
    mutating func overlayStatistics(at timestamp: Double) -> DebugOverlayStatistics? {
        // The refresh that anchors the schedule (at launch, or after a restart) starts the first bucket
        // rather than closing one, so the first value appears after a full second, not three quarters.
        let isAnchoring = schedule.nextDue == nil
        guard schedule.isDue(at: timestamp) else { return nil }
        if !isAnchoring { window.closeBucket() }
        return DebugOverlayStatistics(
            meanFrameSeconds: window.mean,
            worstFrameSeconds: window.worst,
            budgetSeconds: budgetSeconds,
            droppedFrames: droppedFrames,
            skippedFrames: skippedFrames,
            tickCount: lastTickCount
        )
    }

    /// Called when the surface is shown again after being hidden, and by `updateBudget`: frames from
    /// before the pause, or judged against the old budget, are not the last second's. The next frame
    /// refreshes the overlay at once (003 FR-008).
    mutating func restartOverlayWindow() {
        window.restart()
        schedule.restart()
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
