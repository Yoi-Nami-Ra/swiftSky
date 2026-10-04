/// Where the ship is and which way it faces: the two things drawing needs from it (013).
///
/// A plain 24-byte value, so the frame loop can keep the pose of the tick before the current one
/// without copying the whole state (013 FR-005), and every layer that draws from the ship can share one
/// blended pose (013 FR-007).
public struct ShipPose: Sendable, Equatable {
    /// World units, as `Ship.position`.
    public var position: Vector2

    /// Radians, as `Ship.heading`. Stored as given.
    public var heading: Double

    public init(position: Vector2, heading: Double) {
        self.position = position
        self.heading = heading
    }

    /// The ship's position and heading, bit for bit.
    public init(_ ship: Ship) {
        self.init(position: ship.position, heading: ship.heading)
    }

    /// The pose `fraction` of the way from `previous` to `current` (013 FR-002, FR-003, research R3).
    ///
    /// Position is blended linearly; heading along the shorter arc, crossing ±π when that is shorter,
    /// with an exactly opposite pair turning counter-clockwise, and the result in (−π, π]. `fraction` is
    /// clamped into [0, 1).
    ///
    /// Fraction 0 returns `previous`, and a component equal in both poses is returned as `previous`
    /// holds it. Both cases are bit-exact on purpose: `a + (b − a) × t` is not, since `−0 + 0` is `+0`.
    public static func blended(from previous: ShipPose, to current: ShipPose, fraction: Double) -> ShipPose {
        let t = min(max(fraction, 0), 1.0.nextDown)
        guard t > 0 else { return previous }

        return ShipPose(
            position: Vector2(
                x: lerp(previous.position.x, current.position.x, t),
                y: lerp(previous.position.y, current.position.y, t)
            ),
            heading: blendedHeading(previous.heading, current.heading, t)
        )
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a == b ? a : a + (b - a) * t
    }

    private static func blendedHeading(_ from: Double, _ to: Double, _ t: Double) -> Double {
        if from == to { return from }
        var delta = (to - from).remainder(dividingBy: 2 * .pi)
        if delta <= -.pi { delta = .pi }
        return Ship.wrapped(from + delta * t)
    }
}
