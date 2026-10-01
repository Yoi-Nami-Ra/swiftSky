import SwiftSkyRendering
import SwiftSkySimulation

/// "Order the ship to the world point under this view position" (008 FR-004, FR-006, FR-007).
///
/// Posted by the iOS tap, and by SKY-11's click, carried into the frame loop inside
/// `SurfaceEvent.moveOrderRequested`, and applied there at a frame boundary. The position is in the
/// surface's **view** space: points from its top-left corner, +y down (005 FR-004). It is converted in
/// the loop rather than on the main thread, against the surface the loop has applied up to that event,
/// so a tap is always read against the geometry the player saw and never races a resize (008 research
/// R2).
///
/// It lives in the platform layer because that is the only layer allowed to name both the rendering
/// layer's `Camera` and the logic layer's `SimulationState` (001 FR-010). The logic layer sees only a
/// world point, through `setOrder(to:)` (008 FR-009, research R3).
///
/// Nothing here is iOS-specific, so the macOS click reuses it as it is (008 FR-010). What SKY-11 has
/// left to do is post `.moveOrderRequested` from the click's location in the view's points, flipped
/// from AppKit's bottom-left origin unless the view is flipped.
public struct MoveOrderRequest: Sendable, Equatable {
    /// Where on the surface the order was given, in points from its top-left corner, +y down.
    ///
    /// Any value is accepted, even a non-finite one; `apply` decides what it becomes.
    public let viewPoint: Vector2

    public init(viewPoint: Vector2) {
        self.viewPoint = viewPoint
    }

    /// Turns the request into the ship's move order, replacing any current order whole (006 FR-002).
    ///
    /// Without a camera for `surface` — zero area or an unusable backing scale (005 FR-008) — or with a
    /// world point that cannot be an order (006 FR-002), the request is dropped and `state` is left
    /// exactly as it was (008 FR-006, FR-007). The outcome is returned rather than logged, so this stays
    /// a pure function the tests can check; the frame loop decides what to log (research R6).
    ///
    /// Pure and allocation-free: a camera is two `Double`s, built from a few divisions (005 FR-007,
    /// 008 FR-011, FR-012).
    func apply(to state: inout SimulationState, on surface: RenderSurface) -> MoveOrderOutcome {
        guard let camera = Camera(surface: surface) else { return .noCamera }
        let destination = camera.world(fromView: viewPoint)
        return state.setOrder(to: destination) ? .ordered(destination: destination) : .invalidDestination
    }
}

/// What applying a `MoveOrderRequest` did (008 data-model).
enum MoveOrderOutcome: Equatable {
    /// The ship's order is now to `destination`, in world units.
    case ordered(destination: Vector2)
    /// The surface had no camera; the state is unchanged.
    case noCamera
    /// The world point was not finite; the state is unchanged.
    case invalidDestination
}
