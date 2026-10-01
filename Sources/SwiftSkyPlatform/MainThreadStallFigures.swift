/// Turns the main run loop's activity into busy stretches (012 FR-001, FR-003, research R1, R3).
///
/// A stretch opens when the run loop wakes (after-waiting) and closes when it is about to wait again
/// (before-waiting): the time in between is time in which the main thread could not take the next event.
/// Waiting is never counted. A nested run loop (live resize, a menu) waits inside the outer pass, and its
/// waits close and open stretches like the outer loop's, so the stretch measured is always busy time.
///
/// Main thread only. Compiled in every build, like `FrameAllocationCounts`, so it is tested headlessly;
/// only `MainThreadStallProbe` uses it, and only in instrumented builds.
struct BusyStretchTracker {
    /// Clock, in nanoseconds, of the after-waiting that opened the current stretch; `nil` while waiting.
    private(set) var openedAt: UInt64?

    /// The run loop woke for work.
    mutating func afterWaiting(at nanoseconds: UInt64) {
        openedAt = nanoseconds
    }

    /// The run loop is about to wait. Returns the stretch that just ended, or `nil` if none was open (the
    /// first pass after the observers are installed). A clock that went backwards gives 0.
    mutating func beforeWaiting(at nanoseconds: UInt64) -> UInt64? {
        guard let opened = openedAt else { return nil }
        openedAt = nil
        return nanoseconds >= opened ? nanoseconds - opened : 0
    }
}

/// The two main-thread figures of one summary interval, packed into one word so that a summary always
/// gets a worst stretch and a count that belong together (012 FR-004, research R4): the worst stretch in
/// microseconds in the high 40 bits (`mainworst=`), the number of stretches longer than the frame interval
/// in the low 24 (`mainover=`). Both saturate; a summary covers a few seconds, so neither comes close.
///
/// Plain integers, so recording allocates nothing (012 FR-007). Compiled in every build and tested
/// headlessly, like `FrameAllocationCounts`.
struct MainThreadStallFigures: Equatable {
    static let maxWorstMicroseconds: UInt64 = (1 << 40) - 1
    static let maxOverCount: UInt64 = (1 << 24) - 1

    static let zero = MainThreadStallFigures(worstMicroseconds: 0, overCount: 0)

    /// The longest busy stretch that ended in the interval.
    let worstMicroseconds: UInt64

    /// Busy stretches longer than the frame interval in force when each ended.
    let overCount: UInt64

    init(worstMicroseconds: UInt64, overCount: UInt64) {
        self.worstMicroseconds = min(worstMicroseconds, Self.maxWorstMicroseconds)
        self.overCount = min(overCount, Self.maxOverCount)
    }

    init(packed: UInt64) {
        worstMicroseconds = packed >> 24
        overCount = packed & Self.maxOverCount
    }

    var packed: UInt64 {
        worstMicroseconds << 24 | overCount
    }

    /// The figures with one more ended stretch. A stretch exactly as long as the interval is not over:
    /// 001 SC-016 forbids stalls *longer* than one frame interval.
    func recording(stretchNanoseconds: UInt64, intervalNanoseconds: UInt64) -> MainThreadStallFigures {
        let stretchMicroseconds = stretchNanoseconds / 1000
        let over = stretchNanoseconds > intervalNanoseconds
        return MainThreadStallFigures(
            worstMicroseconds: max(worstMicroseconds, stretchMicroseconds),
            overCount: over && overCount < Self.maxOverCount ? overCount + 1 : overCount
        )
    }
}
