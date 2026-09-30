/// The game space's fixed facts (005 FR-001, FR-002, FR-009, FR-010).
///
/// The world is flat, seen top-down, and unbounded: no edges, no wrapping, no collisions. One world
/// unit is one point on screen, with SKY-24's convention of +x right, +y up and angles
/// counter-clockwise positive (004 FR-004). `Camera` maps it onto a surface.
public enum GameSpace {
    /// The ship's length, in world units: 40, so its 80 × 80 px sprite draws at 40 × 40 pt,
    /// pixel-exact on 2× displays (005 FR-009). Shared by the ship sprite (SKY-27) and the order
    /// overlay's ship highlight (SKY-30).
    ///
    /// Note for SKY-27: the sprite's top edge is the ship's front, but heading zero points along +x.
    /// Draw the sprite rotated by `heading − π/2` — a quarter turn clockwise at heading zero
    /// (005 FR-010). That angle is counter-clockwise positive in world or clip space (+y up); build
    /// the rotation there, not in view points, where +y points down and the same angle turns the
    /// other way.
    public static let shipLength: Double = 40
}
