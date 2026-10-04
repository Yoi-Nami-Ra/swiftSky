/// Carries unconsumed real time between frames and decides how many fixed ticks a frame advances
/// (FR-021a).
///
/// The accumulator never reads a clock. Elapsed time is always injected by the caller, which is
/// exactly what makes it testable synchronously with synthetic values and what keeps the simulation
/// deterministic regardless of thread scheduling (FR-033, SC-013).
public struct TimeAccumulator: Sendable, Equatable {
    /// Real time not yet converted into ticks. Always non-negative.
    public private(set) var unconsumed: Double

    public init() {
        self.unconsumed = 0
    }

    /// How far the current tick has progressed: `unconsumed` as a fraction of one tick, always in [0, 1)
    /// (013 FR-001). The blend factor between the last two ticks' poses.
    public var tickFraction: Double {
        min(max(unconsumed / FixedTimestep.tickDuration, 0), 1.0.nextDown)
    }

    /// Adds `seconds` of elapsed real time and returns the whole number of ticks to advance.
    ///
    /// Returning `0` is normal and common: the simulation runs at 60 Hz while the display may be
    /// faster, so some frames advance no tick at all. The frame still draws (FR-021).
    ///
    /// If more than `FixedTimestep.catchUpClamp` ticks have accumulated, the return value is clamped
    /// and **the excess is discarded** (FR-021b) — a 10-second stall advances 4 ticks, not 600. The
    /// simulation falls behind by the discarded amount, which is documented behaviour rather than a
    /// defect.
    ///
    /// - Parameter seconds: Elapsed real time since the previous frame. Non-positive values are
    ///   ignored, since a monotonic clock cannot go backwards and treating it as negative time would
    ///   let `unconsumed` break its own invariant.
    /// - Returns: Whole ticks to advance, in `0...FixedTimestep.catchUpClamp`.
    public mutating func consume(elapsed seconds: Double) -> Int {
        if seconds > 0, seconds.isFinite {
            unconsumed += seconds
        }

        let wholeTicks = Int((unconsumed / FixedTimestep.tickDuration).rounded(.down))
        guard wholeTicks > 0 else { return 0 }

        if wholeTicks > FixedTimestep.catchUpClamp {
            // Discard the overshoot, keeping only the sub-tick remainder so the next frame starts
            // from a clean phase rather than immediately clamping again.
            unconsumed = unconsumed.truncatingRemainder(dividingBy: FixedTimestep.tickDuration)
            return FixedTimestep.catchUpClamp
        }

        // The division above can round up to a whole tick that `unconsumed` falls a few ulps short of,
        // which would leave it just below zero (013 research R1).
        unconsumed = max(0, unconsumed - Double(wholeTicks) * FixedTimestep.tickDuration)
        return wholeTicks
    }
}
