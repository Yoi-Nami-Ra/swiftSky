/// What the renderer should currently draw — the single typed hand-off across the layer boundary
/// (FR-012, FR-012a).
///
/// It holds the tick count, the one ship (004 FR-001) and its autopilot — the current move order and
/// the autopilot's memory between ticks — so that a copy of the state, advanced on its own, flies
/// exactly the same path as the original (006 FR-003, FR-014), plus that order's planned path (010
/// FR-001). It carries no presentation concept — the quad's colour belongs to the rendering layer, not
/// here (FR-012b), and the tick count must never affect what is visible. The renderer draws the ship
/// from its position and heading (007 FR-001) and writes nothing back; it draws nothing from the order
/// or its path until SKY-30.
///
/// A value type, so handing it to the renderer is a copy. That is also what makes it safe to move
/// between isolation domains without any concurrency annotation (FR-012c, FR-012d, FR-030). With the
/// path's inline points it is about 4.2 KB, still with nothing on the heap (010 research R2).
public struct SimulationState: Sendable, Equatable {
    /// Total fixed-timestep ticks advanced since launch. Monotonically non-decreasing (SC-020).
    public var tickCount: UInt64

    /// The one ship the simulation moves (004 FR-001).
    public var ship: Ship

    /// The ship's pilot: the current move order, if any, and its phase (006 FR-003). No order at launch.
    public var autopilot: Autopilot

    /// The current order's planned path; empty until an order is accepted (010 FR-001). Written only by
    /// `setOrder(to:)`, so no advance can change it (FR-008).
    public private(set) var plannedPath: PlannedPath

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
        self.autopilot = Autopilot()
        self.plannedPath = .empty
    }

    /// Gives the ship a move order to `destination`, replacing any current order (006 FR-002), and
    /// predicts the order's path from here (010 FR-007). Every way of giving an order — the player's tap
    /// and click included — comes through here.
    ///
    /// - Returns: `false`, leaving the state unchanged, if `destination` is not finite.
    @discardableResult
    public mutating func setOrder(to destination: Vector2) -> Bool {
        guard let order = MoveOrder(destination: destination) else { return false }
        autopilot.setOrder(order, for: ship)
        plannedPath = PlannedPath(predictingFrom: ship, autopilot: autopilot, tickCount: tickCount)
        return true
    }

    /// The distance from the ship to the order's destination, in world units; `nil` without an order
    /// (006 FR-003).
    public var distanceRemaining: Double? {
        guard let destination = autopilot.order?.destination else { return nil }
        let dx = destination.x - ship.position.x
        let dy = destination.y - ship.position.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
