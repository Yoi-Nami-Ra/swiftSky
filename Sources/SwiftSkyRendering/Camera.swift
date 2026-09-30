import SwiftSkySimulation

/// The fixed mapping between the world and one drawable surface (005 FR-003…FR-008).
///
/// One world unit is one point (005 FR-001). The camera never moves: the world origin sits at the
/// centre of the *whole* surface — not the safe area — so a bigger window shows more world around the
/// same centre, and nothing scales (005 FR-003). It maps between three spaces, all carried as
/// `Vector2` (005 research R2):
///
/// | Space | Origin | Axes | Unit |
/// |-------|--------|------|------|
/// | World | the surface centre | +x right, +y up | world unit = point |
/// | View | the surface's top-left corner | +x right, +y **down** | point |
/// | Clip (normalised device coordinates) | the surface centre | +x right, +y up | edges at ±1 |
///
/// A zero-area surface is routine (001 FR-027a) and has no camera: the initialiser returns `nil`, so a
/// camera that exists always has finite, positive half-extents and no mapping can divide by zero
/// (005 FR-008).
///
/// A plain value of two `Double`s. When the surface changes, build a new camera from it rather than
/// updating one in place; building and mapping never allocate (005 FR-007).
public struct Camera: Sendable, Equatable {
    /// Half the surface width, in points: w/2.
    public let halfWidth: Double

    /// Half the surface height, in points: h/2.
    public let halfHeight: Double

    /// The surface width in points.
    public var widthPoints: Double { 2 * halfWidth }

    /// The surface height in points.
    public var heightPoints: Double { 2 * halfHeight }

    /// The camera for `surface`, or `nil` if it has zero width or height, or a backing scale that is
    /// not finite and positive (005 FR-008).
    ///
    /// Points are pixels divided by the backing scale, exactly and unrounded (005 FR-004), so 1,001 px
    /// at 2× is 500.5 points. Division rather than a reciprocal keeps the same point size bit-identical
    /// at 1×, 2× and 3× (005 FR-006, research R4). The safe-area insets are deliberately not read
    /// (005 FR-003).
    ///
    /// The half-extents are checked as well as the scale: a finite but vanishingly small scale
    /// overflows `pixels / scale` to infinity, and an absurdly large one underflows it to a subnormal.
    /// Neither is a usable camera, so both give `nil` too.
    public init?(surface: RenderSurface) {
        let scale = surface.backingScale
        guard surface.isRenderable, scale.isFinite, scale > 0 else { return nil }
        let halfWidth = Double(surface.widthPixels) / scale / 2
        let halfHeight = Double(surface.heightPixels) / scale / 2
        guard halfWidth.isNormal, halfHeight.isNormal else { return nil }
        self.halfWidth = halfWidth
        self.halfHeight = halfHeight
    }

    /// A world point → its view position, in points from the surface's top-left corner, +y down:
    /// (w/2 + x, h/2 − y) (005 FR-004).
    ///
    /// Not clamped: a world point beyond the visible edges gives a position off the surface
    /// (005 FR-002).
    public func view(fromWorld world: Vector2) -> Vector2 {
        Vector2(x: halfWidth + world.x, y: halfHeight - world.y)
    }

    /// A view position, in points from the surface's top-left corner, → the world point under it:
    /// (vx − w/2, h/2 − vy) (005 FR-004).
    ///
    /// The inverse of `view(fromWorld:)` to within 1e-9 points (005 FR-005). A position off the surface
    /// — a pointer dragged past the window edge — is legal and gives the world point that would be
    /// there (005 FR-002). SKY-10 and SKY-11 turn taps and clicks into world points with this.
    public func world(fromView view: Vector2) -> Vector2 {
        Vector2(x: view.x - halfWidth, y: halfHeight - view.y)
    }

    /// A world point → normalised device coordinates (clip space): (x ÷ (w/2), y ÷ (h/2)), so the
    /// surface's edges are at ±1 with +y up (005 FR-004).
    ///
    /// Divides rather than multiplying by a reciprocal: division is correctly rounded, so an edge lands
    /// on exactly ±1, where `x * (1 / halfWidth)` can miss by an ulp (005 research R4). Not clamped: a
    /// point off the surface gives values beyond ±1 (005 FR-002).
    public func clip(fromWorld world: Vector2) -> Vector2 {
        Vector2(x: world.x / halfWidth, y: world.y / halfHeight)
    }
}
