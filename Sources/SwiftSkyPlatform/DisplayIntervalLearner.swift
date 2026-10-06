/// Learns the display's frame interval — the frame budget — from the gaps between the display link's
/// scheduled presentation times (016).
///
/// SC-003's budget is "16.6 ms, **or the display's native rate**", so a fixed 1/60 is only correct on a
/// 60 Hz display. Left hardcoded it silently over-reports success: on a 120 Hz display a 12 ms frame
/// misses its deadline and is not counted as dropped, making the gate pass by being wrong.
///
/// ## The rules
///
/// - **Shorter intervals are believed only on adjacent agreement.** A gap shorter than the budget (by
///   more than the tolerance)
///   becomes a *candidate*, and only the very next plausible gap can confirm it (within 5%). Any other
///   plausible gap clears it. A real display produces runs of equal gaps; stray gaps — a startup
///   outlier, a CPU-starved simulator's catch-up after a late frame, jitter on a variable-refresh panel
///   — rarely come in adjacent agreeing pairs.
/// - **Never below the display's fastest interval.** Gaps are *not* always whole display intervals: a
///   live resize on a 120 Hz Mac produced a burst of 4.17 ms gaps, and a window moved to a 60 Hz display
///   kept producing 8.33 ms gaps for a while. Both are sustained, so adjacency alone accepts them. The
///   floor, `1 / maximumFramesPerSecond` of the screen the surface is on, rejects them. An adopted interval
///   is clamped to the floor, so rounding just under a real 120 Hz interval still reads exactly 1/120.
/// - **The minimum, not the mean.** On confirmation the smaller of the two gaps is taken. A missed frame
///   lengthens a gap, so averaging would let exactly the frames SC-003 forbids raise the bar they must
///   clear. Within one display the budget only shrinks.
/// - **Forget on a display change.** A backing-scale change (the surface may be on another display), or
///   a floor above the learned interval (it is on a slower one), resets the budget to 1/60 s to relearn.
///
/// Until something is learned, any plausible gap can be a candidate, so the default 1/60 s is confirmed
/// on a 60 Hz display and replaced on one capped below 60 Hz.
///
/// A pure value: no screen, display link or Metal, so it is tested headlessly; no allocation, so it runs
/// on the frame loop's hot path. The loop calls `observe(gap:)` once per frame and passes any budget it
/// returns to `Instrumentation.updateBudget(seconds:)`, which restarts the counters.
struct DisplayIntervalLearner {
    /// The budget before anything is learned, and after a forget.
    static let defaultInterval = 1.0 / 60.0

    /// How close two gaps must be to count as the same display interval, and how far under the floor a
    /// gap may round before it is not plausible.
    static let tolerance = 0.05

    /// 250 Hz and 20 Hz. Nothing outside this is a real display interval: a first frame, a
    /// paused-and-resumed loop or a stalled display produce such gaps, and they teach nothing.
    static let fastestPlausibleInterval = 1.0 / 250.0
    static let slowestPlausibleInterval = 1.0 / 20.0

    /// The budget every frame is judged against, in seconds.
    private(set) var interval = Self.defaultInterval

    /// Whether `interval` was confirmed from gaps, rather than being the default.
    private(set) var isLearned = false

    /// A shorter gap waiting for the very next plausible gap to agree with it.
    private var candidate: Double?

    /// The current display's fastest interval; the budget never goes below it.
    private(set) var floor = Self.fastestPlausibleInterval

    /// Feeds one gap between consecutive scheduled presentation times.
    ///
    /// - Returns: the new budget when it changed, otherwise `nil`.
    mutating func observe(gap: Double) -> Double? {
        let lowest = max(Self.fastestPlausibleInterval, floor * (1 - Self.tolerance))
        guard gap >= lowest, gap <= Self.slowestPlausibleInterval else { return nil }

        if let waiting = candidate, abs(waiting - gap) <= waiting * Self.tolerance {
            candidate = nil
            let adopted = max(min(waiting, gap), floor)
            isLearned = true
            guard adopted != interval else { return nil }
            interval = adopted
            return adopted
        }

        // "Shorter" means shorter by more than the tolerance: a gap within it agrees with the budget, so
        // timestamp rounding cannot nudge a learned interval down by a few nanoseconds and restart the
        // counters each time.
        candidate = (!isLearned || gap < interval * (1 - Self.tolerance)) ? gap : nil
        return nil
    }

    /// Drops what was learned, so the next gaps relearn on the display the surface is now on. Keeps the
    /// floor.
    ///
    /// - Returns: the budget now in force, always `defaultInterval`.
    mutating func forget() -> Double {
        interval = Self.defaultInterval
        isLearned = false
        candidate = nil
        return interval
    }

    /// Sets the floor from the maximum frame rate of the screen the surface is on; 0 or less means
    /// unknown, leaving only the plausible range. A floor above the learned interval means the surface
    /// is now on a slower display, so the interval is forgotten.
    ///
    /// - Returns: the new budget when it changed, otherwise `nil`.
    mutating func setMaximumFramesPerSecond(_ framesPerSecond: Int) -> Double? {
        floor = framesPerSecond > 0
            ? max(1.0 / Double(framesPerSecond), Self.fastestPlausibleInterval)
            : Self.fastestPlausibleInterval
        candidate = nil
        guard isLearned, interval < floor * (1 - Self.tolerance) else { return nil }
        return forget()
    }
}
