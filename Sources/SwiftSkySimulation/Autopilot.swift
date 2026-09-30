/// A move order: fly to `destination` and stop there (006 FR-001).
///
/// Only a finite destination can become an order, so the autopilot never has to check (006 FR-002).
public struct MoveOrder: Sendable, Equatable {
    /// Where the ship should come to rest, in world units.
    public let destination: Vector2

    /// Creates an order, or `nil` if either component of `destination` is not finite (006 FR-002).
    public init?(destination: Vector2) {
        guard destination.x.isFinite, destination.y.isFinite else { return nil }
        self.destination = destination
    }
}

/// What the autopilot is doing on the current tick (006 FR-005).
///
/// Re-evaluated every tick from the ship and the order (research R6). From rest the phases only move
/// forward through this list; from a moving start, a turn-back or a station-keeping correction they may
/// repeat (006 clarifications).
public enum AutopilotPhase: Sendable, Equatable {
    /// Turning to face the burn direction, not yet thrusting.
    case aligning
    /// Thrusting to build the velocity that carries the ship to the destination.
    case burning
    /// Turning to face against the direction of travel, ready to brake.
    case flipping
    /// Thrusting against the motion to stop at the destination.
    case braking
    /// Within both arrival tolerances: the order is complete and the ship keeps station (006 FR-009).
    case arrived
}

/// How close and how slow counts as arrived (006 FR-010).
public struct ArrivalTolerances: Sendable, Equatable {
    /// Largest distance from the destination that counts as there, in world units.
    public let position: Double

    /// Arrival needs the speed to be below this, in world units per second.
    public let speed: Double

    /// Creates tolerances. A negative or non-finite value is treated as zero (006 FR-010).
    public init(position: Double, speed: Double) {
        self.position = Self.sanitised(position)
        self.speed = Self.sanitised(speed)
    }

    /// The default tolerances, and the only place they are written: 1 unit and 1 unit per second
    /// (006 FR-010).
    public static let `default` = ArrivalTolerances(position: 1, speed: 1)

    private static func sanitised(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 0
    }
}

/// The ship's pilot: the current move order, and the one thing it remembers between ticks (006 FR-014).
///
/// A plain value held in `SimulationState`, so a copy of the state flies exactly the same path as the
/// original — what SKY-26's prediction relies on. `order == nil` exactly when `phase == nil`. The
/// per-tick law is `control(for:)`, in `AutopilotLaw.swift`.
public struct Autopilot: Sendable, Equatable {
    /// Fixed for the autopilot's lifetime.
    public let tolerances: ArrivalTolerances

    /// The order being flown, if any. Each new order replaces it whole (006 FR-002).
    public private(set) var order: MoveOrder?

    /// The phase of the latest evaluation; `nil` without an order (006 FR-003). This is the autopilot's
    /// only memory between ticks: it latches arrival and braking (research R6).
    public internal(set) var phase: AutopilotPhase?

    /// An autopilot with no order.
    public init(tolerances: ArrivalTolerances = .default) {
        self.tolerances = tolerances
    }

    /// Replaces the order, forgets everything about the old one, and evaluates the phase against `ship`
    /// at once, so the read-out is valid before the next tick (006 FR-002, story 4).
    public mutating func setOrder(_ order: MoveOrder, for ship: Ship) {
        self.order = order
        phase = nil
        phase = evaluate(ship).phase
    }
}
