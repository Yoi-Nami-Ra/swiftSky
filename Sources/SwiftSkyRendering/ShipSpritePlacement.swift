import Foundation
import SwiftSkySimulation

/// Where the ship's image is drawn for one pose on one surface (007 FR-006–FR-008, research R6).
///
/// Built every frame from the ship's position and heading. It is the whole of the placement: the vertex
/// shader draws `clipCorners` as they are, so what the tests check is what is drawn (research R5). A
/// plain value of doubles; building one allocates nothing (007 FR-011).
///
/// The steps, in order:
/// 1. The camera maps the ship's world position to view points (005 FR-004). No camera, no placement
///    (007 FR-012).
/// 2. Those points, times the backing scale, are rounded to a whole surface pixel (007 FR-006a). With
///    the ship 40, 80 or 120 pixels across at 1×, 2× and 3×, a whole-pixel centre puts the image's
///    pixel grid on the surface's at every quarter turn, on any surface size (007 FR-010).
/// 3. The image is turned by heading − π/2 (005 FR-010), counter-clockwise positive in world space.
///    This is built from the world-space angle and flipped **once** to pixels, where +y points down.
///    Building it in pixel space with the same angle would turn the ship the wrong way — the trap the
///    `GameSpace` note warns about. In pixels, the image's up direction (towards the ship's front) is
///    `f = (cos h, −sin h)` and its right direction is `r = (sin h, cos h)`: at heading zero, the top
///    points right and the right side points down, a quarter turn clockwise.
/// 4. Each corner is half the ship's length along `f` and along `r` from the centre, so the shape is a
///    square at every heading and on every surface (007 FR-008).
///
/// Corners are named by their place in the *image* — `topLeft` is the image's top-left pixel wherever
/// it lands on screen.
struct ShipSpritePlacement: Sendable, Equatable {
    /// The drawn centre, in whole surface pixels from the top-left corner, +y down.
    let centrePixels: Vector2

    /// The image's corners in surface pixels, +y down.
    let topLeft: Vector2
    let topRight: Vector2
    let bottomLeft: Vector2
    let bottomRight: Vector2

    /// The surface's size in pixels, for the conversion to clip space.
    let surfaceWidthPixels: Double
    let surfaceHeightPixels: Double

    /// The placement for a ship at `position` facing `heading` on `surface`, or `nil` when the surface
    /// has no camera (005 FR-008, 007 FR-012).
    init?(position: Vector2, heading: Double, surface: RenderSurface) {
        guard let camera = Camera(surface: surface) else { return nil }
        let scale = surface.backingScale

        let view = camera.view(fromWorld: position)
        let centre = Vector2(x: (view.x * scale).rounded(), y: (view.y * scale).rounded())

        let half = GameSpace.shipLength / 2 * scale
        let cosine = cos(heading)
        let sine = sin(heading)
        let upX = half * cosine, upY = -half * sine
        let rightX = half * sine, rightY = half * cosine

        centrePixels = centre
        topLeft = Vector2(x: centre.x + upX - rightX, y: centre.y + upY - rightY)
        topRight = Vector2(x: centre.x + upX + rightX, y: centre.y + upY + rightY)
        bottomLeft = Vector2(x: centre.x - upX - rightX, y: centre.y - upY - rightY)
        bottomRight = Vector2(x: centre.x - upX + rightX, y: centre.y - upY + rightY)
        surfaceWidthPixels = Double(surface.widthPixels)
        surfaceHeightPixels = Double(surface.heightPixels)
    }

    /// A point in surface pixels (+y down) → clip space (edges at ±1, +y up).
    func clip(_ pixel: Vector2) -> Vector2 {
        Vector2(x: pixel.x / surfaceWidthPixels * 2 - 1, y: 1 - pixel.y / surfaceHeightPixels * 2)
    }

    /// The corners in clip space, in triangle-strip order: bottom-left, bottom-right, top-left,
    /// top-right. `swiftsky_sprite_vertex` gives them texture coordinates in the same order.
    var clipCorners: (Vector2, Vector2, Vector2, Vector2) {
        (clip(bottomLeft), clip(bottomRight), clip(topLeft), clip(topRight))
    }
}
