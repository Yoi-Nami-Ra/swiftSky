import Testing

@testable import SwiftSkyPlatform

@Suite("Frame-time window")
struct FrameTimeWindowTests {
    /// Records `frames` frames of `seconds` each, then closes the bucket: one refresh period.
    private func period(_ window: inout FrameTimeWindow, frames: Int = 15, seconds: Double = 0.001) {
        for _ in 0..<frames { window.record(frameSeconds: seconds) }
        window.closeBucket()
    }

    @Test("The window is exactly one second of refresh periods")
    func oneSecond() {
        #expect(Double(FrameTimeWindow.bucketCount) * OverlayRefreshSchedule.interval == FrameTimeWindow.windowSeconds)
    }

    @Test("Mean and worst are nil until four buckets have closed")
    func nilUntilFull() {
        var window = FrameTimeWindow()
        for _ in 0..<3 {
            period(&window)
            #expect(window.mean == nil)
            #expect(window.worst == nil)
        }
        period(&window)
        #expect(abs(window.mean! - 0.001) < 1e-12)
        #expect(window.worst == 0.001)
    }

    @Test("Mean is weighted by frames across the four buckets")
    func mean() {
        var window = FrameTimeWindow()
        period(&window, frames: 1, seconds: 0.004)
        period(&window, frames: 3, seconds: 0.002)
        period(&window, frames: 0)
        period(&window, frames: 4, seconds: 0.001)
        // (0.004 + 3 × 0.002 + 4 × 0.001) / 8
        #expect(abs(window.mean! - 0.014 / 8) < 1e-12)
        #expect(window.worst == 0.004)
    }

    @Test("Only the last four closed buckets count once a fifth closes")
    func slides() {
        var window = FrameTimeWindow()
        period(&window, seconds: 0.010)
        for _ in 0..<3 { period(&window, seconds: 0.001) }
        #expect(window.worst == 0.010)
        period(&window, seconds: 0.001)
        #expect(window.worst == 0.001)
        #expect(abs(window.mean! - 0.001) < 1e-12)
    }

    @Test("A slow frame stays the worst for exactly four closes, however far apart frames are (FR-008)")
    func slowFrameSurvivesGap() {
        var window = FrameTimeWindow()
        for _ in 0..<4 { period(&window) }

        // A 0.3 s frame — a breakpoint, a hitch — then nothing else in that period: the gap that follows
        // it is not a restart trigger.
        window.record(frameSeconds: 0.3)
        window.closeBucket()
        for close in 1...3 {
            period(&window)
            #expect(window.worst == 0.3, "close \(close) after the slow frame")
        }
        period(&window)
        #expect(window.worst == 0.001)
    }

    @Test("Restart returns to nil")
    func restart() {
        var window = FrameTimeWindow()
        for _ in 0..<4 { period(&window) }
        #expect(window.mean != nil)
        window.restart()
        #expect(window.mean == nil)
        #expect(window.worst == nil)
        #expect(window.closedCount == 0)

        // The frames from before the restart are gone for good.
        window.record(frameSeconds: 0.5)
        window.restart()
        for _ in 0..<4 { period(&window) }
        #expect(window.worst == 0.001)
    }

    @Test("A second with no drawn frames has no mean")
    func noFrames() {
        var window = FrameTimeWindow()
        for _ in 0..<4 { period(&window, frames: 0) }
        #expect(window.mean == nil)
        #expect(window.worst == 0)
    }
}
