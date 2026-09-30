import Testing

@testable import SwiftSkyPlatform

@Suite("Overlay refresh")
struct OverlayRefreshTests {
    /// Refreshes over `seconds` of frames at `rate` Hz, starting at an arbitrary timestamp.
    private func refreshes(rate: Double, seconds: Double) -> Int {
        var schedule = OverlayRefreshSchedule()
        let start = 1_000.0
        var count = 0
        for frame in 0..<Int(rate * seconds) where schedule.isDue(at: start + Double(frame) / rate) {
            count += 1
        }
        return count
    }

    @Test("Four refreshes a second, without drift (SC-002)", arguments: [60.0, 120.0, 90.0, 30.0])
    func rate(rate: Double) {
        #expect(abs(refreshes(rate: rate, seconds: 10) - 40) <= 1)
    }

    @Test("The first frame is due, and the next only a whole interval later")
    func firstFrameDue() {
        var schedule = OverlayRefreshSchedule()
        let dues = [5, 5.1, 5.249, 5.25].map { schedule.isDue(at: $0) }
        #expect(dues == [true, false, false, true])
    }

    @Test("A long gap fires one refresh, not a burst, and the grid resumes from it")
    func noBurstAfterGap() {
        var schedule = OverlayRefreshSchedule()
        let dues = [0, 2.0, 2.01, 2.2, 2.25].map { schedule.isDue(at: $0) }
        #expect(dues == [true, true, false, false, true])
    }

    @Test("Restart makes the next frame due at once")
    func restart() {
        var schedule = OverlayRefreshSchedule()
        let dues = [0, 0.1].map { schedule.isDue(at: $0) }
        #expect(dues == [true, false])
        schedule.restart()
        let afterRestart = schedule.isDue(at: 0.1)
        #expect(afterRestart)
    }

    // MARK: - Snapshots

    /// Runs 60 Hz frames of `frameSeconds` each for `seconds`, returning the mean and worst of the last
    /// snapshot taken. (Returned as numbers so this target need not import the rendering layer, which
    /// defines the snapshot type.)
    private func run(
        _ instrumentation: inout Instrumentation,
        from start: Double,
        seconds: Double,
        frameSeconds: Double = 0.002,
        tick: inout UInt64
    ) -> (mean: Double?, worst: Double?)? {
        var last: (mean: Double?, worst: Double?)?
        for frame in 0..<Int(seconds * 60) {
            if let snapshot = instrumentation.overlayStatistics(at: start + Double(frame) / 60) {
                last = (snapshot.meanFrameSeconds, snapshot.worstFrameSeconds)
            }
            tick += 1
            instrumentation.recordPresented(frameSeconds: frameSeconds, tickCount: tick)
        }
        return last
    }

    @Test("Snapshot counts are the instrumentation's own counters (FR-013)")
    func snapshotMatchesCounters() throws {
        var instrumentation = Instrumentation(budgetSeconds: 1.0 / 60.0)
        var tick: UInt64 = 0
        instrumentation.recordSkipped()
        instrumentation.recordSkipped()
        _ = run(&instrumentation, from: 0, seconds: 1, tick: &tick)
        instrumentation.recordPresented(frameSeconds: 0.05, tickCount: tick)

        let taken = instrumentation.overlayStatistics(at: 1.25)
        let snapshot = try #require(taken)
        #expect(snapshot.budgetSeconds == 1.0 / 60.0)
        #expect(snapshot.droppedFrames == instrumentation.droppedFrames)
        #expect(snapshot.droppedFrames == 1)
        #expect(snapshot.skippedFrames == instrumentation.skippedFrames)
        #expect(snapshot.skippedFrames == 2)
        #expect(snapshot.tickCount == instrumentation.lastTickCount)
        #expect(snapshot.tickCount == 60)
    }

    @Test("Mean and worst appear after one full second, and not before")
    func firstValueAfterOneSecond() throws {
        var instrumentation = Instrumentation(budgetSeconds: 1.0 / 60.0)
        var tick: UInt64 = 0
        let early = run(&instrumentation, from: 0, seconds: 0.95, tick: &tick)
        #expect(early != nil)
        #expect(early?.mean == nil)
        #expect(early?.worst == nil)

        let taken = instrumentation.overlayStatistics(at: 1.0)
        let full = try #require(taken)
        let mean = try #require(full.meanFrameSeconds)
        #expect(abs(mean - 0.002) < 1e-12)
        #expect(full.worstFrameSeconds == 0.002)
    }

    @Test("A budget change restarts mean and worst with the counters (FR-008)")
    func budgetChangeRestarts() {
        var instrumentation = Instrumentation(budgetSeconds: 1.0 / 60.0)
        var tick: UInt64 = 0
        let before = run(&instrumentation, from: 0, seconds: 2, tick: &tick)
        #expect(before?.mean != nil)

        instrumentation.updateBudget(seconds: 1.0 / 120.0)
        let after = instrumentation.overlayStatistics(at: 2.001)
        #expect(after?.meanFrameSeconds == nil)
        #expect(after?.worstFrameSeconds == nil)
        #expect(after?.budgetSeconds == 1.0 / 120.0)
        #expect(after?.droppedFrames == 0)
    }

    @Test("Becoming visible again restarts the window and refreshes at once (FR-008)")
    func visibilityRestarts() {
        var instrumentation = Instrumentation(budgetSeconds: 1.0 / 60.0)
        var tick: UInt64 = 0
        _ = run(&instrumentation, from: 0, seconds: 2, tick: &tick)

        instrumentation.restartOverlayWindow()
        let resumed = instrumentation.overlayStatistics(at: 7.0)
        #expect(resumed != nil)
        #expect(resumed?.meanFrameSeconds == nil)
        #expect(resumed?.tickCount == tick)
    }

    // MARK: - Launch arguments

    @Test(
        "The overlay is the default; the test strings replace it; --no-debug-overlay hides it (FR-001, FR-011, FR-012)",
        arguments: [
            ([String](), DebugTextMode.overlay),
            (["--no-debug-overlay"], .none),
            (["--debug-text"], .testString),
            (["--debug-text", "--no-debug-overlay"], .testString),
            (["--debug-text-fill", "--debug-text", "--no-debug-overlay"], .fill),
        ]
    )
    func launchArguments(arguments: [String], expected: DebugTextMode) {
        let mode = DebugTextMode(arguments: ["swiftSky"] + arguments)
        #expect(mode == expected)
        #expect((mode.overlay != nil) == (expected == .overlay))
        #expect((mode.pattern != nil) == (expected == .testString || expected == .fill))
    }
}
