import SwiftSkySimulation

/// Turns a Mac click's position into the view space 008's order request takes (009 FR-004).
///
/// AppKit reports a position in an unflipped view from its **bottom-left** corner, +y up. The order
/// request, like the camera, works in view space: from the **top-left** corner, +y down (005 FR-004). So
/// the click is turned once, here, before it is posted: (x, h − y).
///
/// The flip is done here rather than by making `MetalSurfaceView` flipped, because flipping a
/// layer-hosting view changes the coordinate space of everything 001 built in it, for the sake of one
/// input (009 research R3).
///
/// `heightPoints` is the view's `bounds.height` at the moment of the click. That is the geometry the
/// surface was last reported from — `setFrameSize` reports it synchronously, on the main thread, before
/// any later click is handled — so the flip and the loop's conversion agree on the height (research R3).
///
/// Pure and platform-neutral, so it is tested headlessly with 008's conversion (009 FR-008). Any value,
/// even a non-finite one, is passed through: `MoveOrderRequest.apply` decides what it becomes.
enum ClickPosition {
    /// A position from the surface's bottom-left corner, +y up → the same point in view space, from the
    /// top-left corner, +y down.
    static func viewPoint(fromBottomLeft position: Vector2, heightPoints: Double) -> Vector2 {
        Vector2(x: position.x, y: heightPoints - position.y)
    }
}
