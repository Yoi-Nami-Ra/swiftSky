/// A ship's fixed performance limits (004 FR-003).
///
/// Every property is `let`, so the limits cannot change over the ship's lifetime, and the initialiser
/// sanitises once so the per-tick rule never has to check (004 research R6). Angles are in radians;
/// the degree values are given alongside for readers of the spec (004 research R2).
public struct ShipLimits: Sendable, Equatable {
    /// Forward acceleration at full thrust, in world units per second squared.
    public let maxThrustAcceleration: Double

    /// The fastest the ship can turn, in radians per second.
    public let maxAngularSpeed: Double

    /// The fastest the ship can change its rate of turn, in radians per second squared.
    public let maxAngularAcceleration: Double

    /// Creates limits. A negative or non-finite value is treated as zero: a ship with a zero limit
    /// simply cannot accelerate or turn, which is not an error (004 FR-003).
    public init(maxThrustAcceleration: Double, maxAngularSpeed: Double, maxAngularAcceleration: Double) {
        self.maxThrustAcceleration = Self.sanitised(maxThrustAcceleration)
        self.maxAngularSpeed = Self.sanitised(maxAngularSpeed)
        self.maxAngularAcceleration = Self.sanitised(maxAngularAcceleration)
    }

    /// The default limits, and the only place they are written (004 FR-003): 200 units/s² of thrust,
    /// 180 °/s of turn and 360 °/s² of angular acceleration.
    ///
    /// One world unit is one point on screen (005 FR-001), so these read as 200 pt/s², and were kept
    /// as they are when that scale was fixed (005 FR-012).
    public static let `default` = ShipLimits(
        maxThrustAcceleration: 200,
        maxAngularSpeed: .pi,
        maxAngularAcceleration: 2 * .pi
    )

    private static func sanitised(_ value: Double) -> Double {
        value.isFinite && value > 0 ? value : 0
    }
}

/// What the ship is asked to do on each tick of one `Simulation.advance` call (004 FR-006).
///
/// Sanitised on construction (004 FR-007, research R6): a non-finite value becomes zero, then thrust
/// is clamped to `0...1` and turn to `-1...1`. Every stored value is therefore in range, and a bad
/// input can never make the ship's state non-finite.
public struct ControlInput: Sendable, Equatable {
    /// Forward thrust as a fraction of `ShipLimits.maxThrustAcceleration`, along the heading only. The
    /// engine cannot push backwards or sideways.
    public let thrust: Double

    /// The *target rate of turn*, as a fraction of `ShipLimits.maxAngularSpeed` — not an angular
    /// acceleration (004 FR-008). Positive is counter-clockwise (004 FR-004). `0` means "stop turning":
    /// the ship brings its spin to rest as fast as its angular acceleration allows.
    public let turn: Double

    public init(thrust: Double, turn: Double) {
        self.thrust = Self.clamped(thrust, to: 0...1)
        self.turn = Self.clamped(turn, to: -1...1)
    }

    /// No thrust and no turn. What every tick receives until an input source exists (004 FR-010).
    public static let neutral = ControlInput(thrust: 0, turn: 0)

    private static func clamped(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// The one body the simulation moves (004 FR-001).
///
/// A plain value, copied across the layer boundary with the rest of `SimulationState`
/// (001 FR-012c). The per-tick rule is `step(_:)`, in `ShipMotion.swift`.
public struct Ship: Sendable, Equatable {
    /// Position in the world plane, in world units.
    public var position: Vector2

    /// Velocity in world units per second. Unbounded: there is no drag and no top speed (004 FR-009).
    public var velocity: Vector2

    /// The direction the ship faces, in radians, within (−π, π] (004 FR-004, FR-005).
    public var heading: Double

    /// Rate of turn, in radians per second. Positive is counter-clockwise.
    public var angularVelocity: Double

    /// Fixed for the ship's lifetime (004 FR-003).
    public let limits: ShipLimits

    /// The launch ship: at the origin, at rest, facing heading zero and not turning (004 FR-002).
    public init(limits: ShipLimits = .default) {
        self.init(position: .zero, velocity: .zero, heading: 0, angularVelocity: 0, limits: limits)
    }

    /// A ship mid-flight, for tests. The heading is wrapped into (−π, π]; the angular velocity is taken
    /// as given, so a test may deliberately start above a lowered target.
    public init(
        position: Vector2,
        velocity: Vector2,
        heading: Double,
        angularVelocity: Double,
        limits: ShipLimits = .default
    ) {
        self.position = position
        self.velocity = velocity
        self.heading = Self.wrapped(heading)
        self.angularVelocity = angularVelocity
        self.limits = limits
    }

    /// `heading` brought into (−π, π] (004 FR-005, research R5).
    ///
    /// An in-range heading is returned untouched, so the common tick changes no bits. Otherwise
    /// `remainder(dividingBy:)` — exact in IEEE 754, and correct even if a tick turned more than once
    /// round — gives [−π, π], and an exact −π becomes π. A non-finite heading becomes 0, so a ship can
    /// never hold one.
    static func wrapped(_ heading: Double) -> Double {
        guard heading.isFinite else { return 0 }
        if heading > -.pi, heading <= .pi { return heading }
        let wrapped = heading.remainder(dividingBy: 2 * .pi)
        return wrapped == -.pi ? .pi : wrapped
    }
}
