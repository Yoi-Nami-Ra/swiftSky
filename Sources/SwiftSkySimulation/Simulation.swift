/// Advances the simulation.
///
/// `advance` is a pure function of the state, a whole number of ticks and, optionally, one control input
/// (without one, the state's autopilot chooses each tick's input, 006 FR-011): no clock,
/// no randomness, no I/O, no global state (FR-012c as extended by 004, FR-015, FR-033). The same inputs
/// always produce the same output, which is what SC-013's byte-identical guarantee across ten headless
/// runs rests on.
///
/// Note there is no actor, no lock, and no isolation annotation anywhere in this layer. Isolation is
/// the frame loop's responsibility (FR-028); these types simply don't need it, and adding it here
/// would force every simulation test to become asynchronous for no benefit (FR-012c, FR-012d).
public enum Simulation {
    /// Advances `state` by `ticks` fixed timesteps, flown by the autopilot.
    ///
    /// With an order, each tick's input is the one the autopilot chooses for that tick, from the state
    /// at its start, so advancing n ticks at once is bit-identical to advancing one tick n times
    /// (006 FR-011). Without an order every tick gets the neutral input, exactly as before 006 — which
    /// is why the frame loop's call is unchanged until something issues orders (004 FR-010).
    ///
    /// - Parameters:
    ///   - state: The current state.
    ///   - ticks: Whole ticks to advance. `0` is legal and returns `state` unchanged.
    /// - Returns: The state after `ticks` advances.
    public static func advance(_ state: SimulationState, ticks: Int) -> SimulationState {
        var previousPose = ShipPose(state.ship)
        return advance(state, ticks: ticks, previousPose: &previousPose)
    }

    /// `advance(_:ticks:)`, also recording the ship's pose from immediately before the last tick
    /// (013 FR-005, research R4).
    ///
    /// The returned state is bit-identical to `advance(_:ticks:)`'s. `previousPose` is left alone when
    /// `ticks` is 0, so on a frame that advances no tick the drawing keeps blending between the same two
    /// poses; on a multi-tick frame it is the pose one tick before the result, never the one before the
    /// frame.
    public static func advance(
        _ state: SimulationState,
        ticks: Int,
        previousPose: inout ShipPose
    ) -> SimulationState {
        guard ticks > 0 else { return state }
        var next = state
        for _ in 1..<ticks {
            tick(&next.ship, &next.autopilot)
        }
        previousPose = ShipPose(next.ship)
        tick(&next.ship, &next.autopilot)
        next.tickCount += UInt64(ticks)
        return next
    }

    /// One tick flown by the autopilot: the input it chooses for `ship`, then the ship stepped with it.
    ///
    /// The phase the autopilot records is evaluated from the ship at the start of the tick (006 research
    /// R6). Shared by `advance(_:ticks:)` and the path prediction, so a predicted path is the real flight
    /// by construction rather than by keeping two copies of these lines in step (010 FR-002, research R3).
    @inline(__always)
    static func tick(_ ship: inout Ship, _ autopilot: inout Autopilot) {
        let input = autopilot.control(for: ship)
        ship.step(input)
    }

    /// Advances `state` by `ticks` fixed timesteps, every one of them driven by `input`.
    ///
    /// Every tick of one call gets the same input, so advancing n ticks at once is bit-identical to
    /// advancing one tick n times (004 FR-011). The autopilot is bypassed and left untouched: its order
    /// and phase survive, and it resumes from the resulting ship on the next autopilot-driven advance
    /// (006 FR-011, clarifications).
    ///
    /// - Parameters:
    ///   - state: The current state.
    ///   - ticks: Whole ticks to advance. `0` is legal and returns `state` unchanged.
    ///   - input: What the ship is asked to do on each of those ticks.
    /// - Returns: The state after `ticks` advances.
    public static func advance(
        _ state: SimulationState,
        ticks: Int,
        input: ControlInput
    ) -> SimulationState {
        var previousPose = ShipPose(state.ship)
        return advance(state, ticks: ticks, input: input, previousPose: &previousPose)
    }

    /// `advance(_:ticks:input:)`, also recording the ship's pose from immediately before the last tick,
    /// exactly as `advance(_:ticks:previousPose:)` does (013 FR-005).
    public static func advance(
        _ state: SimulationState,
        ticks: Int,
        input: ControlInput,
        previousPose: inout ShipPose
    ) -> SimulationState {
        guard ticks > 0 else { return state }
        var next = state
        for _ in 1..<ticks {
            next.ship.step(input)
        }
        previousPose = ShipPose(next.ship)
        next.ship.step(input)
        next.tickCount += UInt64(ticks)
        return next
    }
}
