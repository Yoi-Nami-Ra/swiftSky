/// The simulation's fixed timestep, decoupled from any display's refresh rate (FR-021a).
///
/// These are the only place the tick rate and catch-up bound are written down (FR-021b). A 120 Hz
/// display does not make the simulation run twice as fast; it makes it draw twice as often between
/// the same ticks.
public enum FixedTimestep {
    /// Simulation ticks per second. Deliberately independent of display refresh rate.
    public static let tickRate: Int = 60

    /// Duration of a single tick, in seconds.
    public static let tickDuration: Double = 1.0 / Double(tickRate)

    /// The most ticks a single frame may advance.
    ///
    /// After a long stall — a debugger pause, a resume from background, display sleep — the elapsed
    /// time handed to the accumulator can be seconds or minutes. Advancing every missed tick would
    /// starve the frame budget, so the excess is discarded instead: the simulation loses time rather
    /// than stalling trying to reclaim it (FR-021b).
    public static let catchUpClamp: Int = 4
}
