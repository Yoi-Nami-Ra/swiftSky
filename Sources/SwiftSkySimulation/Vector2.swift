/// A point or displacement in the world plane: a position in world units, or a velocity in units per
/// second.
///
/// Positive `y` is "up" for the heading convention: heading zero points along positive `x`, and a
/// positive heading is counter-clockwise (004 FR-004).
///
/// Deliberately a two-field struct with four operators rather than `SIMD2<Double>`. SIMD arithmetic
/// may be fused or vectorised differently from scalar code, and a vector this small is easier to see
/// is bit-stable than to prove `SIMD2` is (004 research R10).
public struct Vector2: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vector2(x: 0, y: 0)

    public static func + (lhs: Vector2, rhs: Vector2) -> Vector2 {
        Vector2(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func += (lhs: inout Vector2, rhs: Vector2) {
        lhs = lhs + rhs
    }

    public static func * (lhs: Vector2, rhs: Double) -> Vector2 {
        Vector2(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}
