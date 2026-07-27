/// Advances the simulation.
///
/// `advance` is a pure function: no clock, no randomness, no I/O, no global state (FR-015, FR-033).
/// The same inputs always produce the same output, which is what SC-013's byte-identical guarantee
/// across ten headless runs rests on.
///
/// Note there is no actor, no lock, and no isolation annotation anywhere in this layer. Isolation is
/// the frame loop's responsibility (FR-028); these types simply don't need it, and adding it here
/// would force every simulation test to become asynchronous for no benefit (FR-012c, FR-012d).
public enum Simulation {
    /// Advances `state` by `ticks` fixed timesteps.
    ///
    /// - Parameters:
    ///   - state: The current state.
    ///   - ticks: Whole ticks to advance. `0` is legal and returns `state` unchanged.
    /// - Returns: The state after `ticks` advances.
    public static func advance(_ state: SimulationState, ticks: Int) -> SimulationState {
        guard ticks > 0 else { return state }
        var next = state
        next.tickCount += UInt64(ticks)
        return next
    }
}
