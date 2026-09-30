/// What the renderer should currently draw — the single typed hand-off across the layer boundary
/// (FR-012, FR-012a).
///
/// It holds the tick count and the one ship (004 FR-001). It carries no presentation concept — the
/// quad's colour belongs to the rendering layer, not here (FR-012b), and the tick count must never
/// affect what is visible. The renderer receives the ship but draws nothing from it until SKY-27
/// (004 research R9).
///
/// A value type, so handing it to the renderer is a copy. That is also what makes it safe to move
/// between isolation domains without any concurrency annotation (FR-012c, FR-012d, FR-030).
public struct SimulationState: Sendable, Equatable {
    /// Total fixed-timestep ticks advanced since launch. Monotonically non-decreasing (SC-020).
    public var tickCount: UInt64

    /// The one ship the simulation moves (004 FR-001).
    public var ship: Ship

    /// The state at launch, before any tick has been advanced, with the launch ship (004 FR-002).
    public init() {
        self.init(tickCount: 0)
    }

    /// Creates a state with an explicit tick count and the launch ship. Useful for tests that start
    /// mid-run.
    public init(tickCount: UInt64) {
        self.init(tickCount: tickCount, ship: Ship())
    }

    /// Creates a state with an explicit tick count and ship. Useful for tests that start mid-flight.
    public init(tickCount: UInt64, ship: Ship) {
        self.tickCount = tickCount
        self.ship = ship
    }
}
