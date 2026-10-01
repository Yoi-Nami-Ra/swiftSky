import Testing

@testable import SwiftSkyPlatform

/// 012 FR-010, SC-001: the main-thread stall probe's arithmetic, without a run loop.
@Suite("Busy stretch tracker")
struct BusyStretchTrackerTests {
    @Test("A stretch is the time from after-waiting to before-waiting")
    func stretch() {
        var tracker = BusyStretchTracker()
        tracker.afterWaiting(at: 1_000)
        #expect(tracker.beforeWaiting(at: 4_500) == 3_500)
    }

    @Test("A before-waiting with no open stretch records nothing")
    func notOpen() {
        var tracker = BusyStretchTracker()
        #expect(tracker.beforeWaiting(at: 10) == nil)
        tracker.afterWaiting(at: 20)
        #expect(tracker.beforeWaiting(at: 30) == 10)
        #expect(tracker.beforeWaiting(at: 40) == nil)
    }

    @Test("A nested run loop's waits split the outer pass into two stretches (research R3)")
    func nested() {
        var tracker = BusyStretchTracker()
        tracker.afterWaiting(at: 0)       // outer pass wakes
        #expect(tracker.beforeWaiting(at: 2_000) == 2_000)   // nested loop waits
        tracker.afterWaiting(at: 5_000)   // nested loop wakes, then exits
        #expect(tracker.beforeWaiting(at: 6_000) == 1_000)   // outer loop waits
    }

    @Test("A clock that goes backwards gives a zero stretch")
    func backwards() {
        var tracker = BusyStretchTracker()
        tracker.afterWaiting(at: 9_000)
        #expect(tracker.beforeWaiting(at: 8_000) == 0)
    }
}

@Suite("Main-thread stall figures")
struct MainThreadStallFiguresTests {
    private static let interval: UInt64 = 8_333_333

    @Test("Packing round-trips")
    func packing() {
        let figures = MainThreadStallFigures(worstMicroseconds: 123_456, overCount: 789)
        let unpacked = MainThreadStallFigures(packed: figures.packed)
        #expect(unpacked == figures)
        #expect(unpacked.worstMicroseconds == 123_456)
        #expect(unpacked.overCount == 789)
        #expect(MainThreadStallFigures.zero.packed == 0)
    }

    @Test("The worst stretch is kept, in microseconds")
    func worst() {
        let figures = MainThreadStallFigures.zero
            .recording(stretchNanoseconds: 3_000_000, intervalNanoseconds: Self.interval)
            .recording(stretchNanoseconds: 7_400_999, intervalNanoseconds: Self.interval)
            .recording(stretchNanoseconds: 1_000, intervalNanoseconds: Self.interval)
        #expect(figures.worstMicroseconds == 7_400)
        #expect(figures.overCount == 0)
    }

    @Test("A stretch equal to the interval is not over; one nanosecond longer is")
    func boundary() {
        let equal = MainThreadStallFigures.zero
            .recording(stretchNanoseconds: Self.interval, intervalNanoseconds: Self.interval)
        #expect(equal.overCount == 0)
        let longer = MainThreadStallFigures.zero
            .recording(stretchNanoseconds: Self.interval + 1, intervalNanoseconds: Self.interval)
        #expect(longer.overCount == 1)
    }

    @Test("Stretches over the interval are counted")
    func counts() {
        var figures = MainThreadStallFigures.zero
        for stretch: UInt64 in [9_000_000, 2_000_000, 50_000_000, 8_400_000] {
            figures = figures.recording(stretchNanoseconds: stretch, intervalNanoseconds: Self.interval)
        }
        #expect(figures.overCount == 3)
        #expect(figures.worstMicroseconds == 50_000)
    }

    @Test("Each stretch is judged against the interval in force when it ends")
    func intervalChange() {
        let figures = MainThreadStallFigures.zero
            .recording(stretchNanoseconds: 10_000_000, intervalNanoseconds: 16_666_667)
            .recording(stretchNanoseconds: 10_000_000, intervalNanoseconds: Self.interval)
        #expect(figures.overCount == 1)
    }

    @Test("Worst and count saturate instead of wrapping")
    func saturation() {
        let full = MainThreadStallFigures(
            worstMicroseconds: MainThreadStallFigures.maxWorstMicroseconds,
            overCount: MainThreadStallFigures.maxOverCount
        )
        let next = full.recording(stretchNanoseconds: UInt64.max, intervalNanoseconds: 1)
        #expect(next.worstMicroseconds == MainThreadStallFigures.maxWorstMicroseconds)
        #expect(next.overCount == MainThreadStallFigures.maxOverCount)
        #expect(MainThreadStallFigures.maxWorstMicroseconds == (1 << 40) - 1)
        #expect(MainThreadStallFigures.maxOverCount == (1 << 24) - 1)
    }
}

#if SWIFTSKY_INSTRUMENTATION

@Suite("Main-thread stall probe")
struct MainThreadStallProbeTests {
    @Test("take() returns what was recorded and leaves zero")
    func take() {
        let probe = MainThreadStallProbe()
        probe.restart(intervalSeconds: 0.008)
        probe.record(stretchNanoseconds: 12_000_000)
        probe.record(stretchNanoseconds: 3_000_000)
        let figures = probe.take()
        #expect(figures.worstMicroseconds == 12_000)
        #expect(figures.overCount == 1)
        #expect(probe.take() == .zero)
    }

    @Test("A stretch recorded after a take lands in the next one (012 FR-005)")
    func nextSummary() {
        let probe = MainThreadStallProbe()
        probe.restart(intervalSeconds: 0.008)
        probe.record(stretchNanoseconds: 1_000_000)
        _ = probe.take()
        probe.record(stretchNanoseconds: 20_000_000)
        let figures = probe.take()
        #expect(figures.worstMicroseconds == 20_000)
        #expect(figures.overCount == 1)
    }

    @Test("A restart discards the figures and switches the interval (012 FR-006)")
    func restart() {
        let probe = MainThreadStallProbe()
        probe.restart(intervalSeconds: 1.0 / 60.0)
        probe.record(stretchNanoseconds: 12_000_000)    // under 16.7 ms
        probe.restart(intervalSeconds: 1.0 / 120.0)
        #expect(probe.take() == .zero)
        probe.record(stretchNanoseconds: 12_000_000)    // over 8.3 ms
        #expect(probe.take().overCount == 1)
    }
}

@Suite("DebugMainStall")
struct DebugMainStallTests {
    @Test("--debug-main-stall is off unless given")
    func parsing() {
        #expect(!DebugMainStall(arguments: ["swiftSky"]).isRequested)
        #expect(DebugMainStall(arguments: ["swiftSky", "--debug-main-stall"]).isRequested)
        #expect(DebugMainStall.stallSeconds == 0.050)
    }
}

#endif
