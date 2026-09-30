#if SWIFTSKY_INSTRUMENTATION

/// When the debug overlay's values next change: four times a second (003 FR-006, research.md R3).
///
/// Debug and Profiling builds only. Driven solely by the timestamp the frame loop reads once per frame
/// (001 FR-033) — this reads no clock of its own.
///
/// The due times sit on a fixed grid rather than "one interval after the last refresh". At 60 Hz a
/// "since last" rule fires on the first frame *after* each 0.25 s mark and drifts slower than four a
/// second; the grid keeps the long-run rate exact (SC-002). A frame that arrives more than a whole
/// interval late — after a hitch, say — re-anchors the grid instead of firing a burst of catch-up
/// refreshes.
struct OverlayRefreshSchedule {
    /// Refreshes per second. The one place the rate is named (FR-006).
    static let refreshRate = 4.0

    static let interval = 1.0 / refreshRate

    /// The next refresh time, or `nil` when the next frame is due at once: at launch, and after a
    /// restart, so the overlay is populated on the first frame drawn.
    private(set) var nextDue: Double?

    /// Whether the frame at `timestamp` should refresh the overlay. Advances the schedule when it
    /// does.
    mutating func isDue(at timestamp: Double) -> Bool {
        guard let due = nextDue else {
            nextDue = timestamp + Self.interval
            return true
        }
        guard timestamp >= due else { return false }

        var following = due + Self.interval
        if following <= timestamp {
            following = timestamp + Self.interval
        }
        nextDue = following
        return true
    }

    /// Makes the next frame due at once.
    mutating func restart() {
        nextDue = nil
    }
}

#endif
