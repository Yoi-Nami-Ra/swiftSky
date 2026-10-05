import Foundation
import SwiftSkySimulation

/// The order overlay's look, in one place (014 research R7). No design exists yet (014 Assumptions), so
/// these are the spec's choices; a later design changes them here.
///
/// Sizes are in points — world units at 005's fixed scale — and become pixels by the backing scale, so
/// the overlay is the same size on every display (014 FR-010). Ring radii are to the middle of the
/// stroke.
enum OrderOverlayStyle {
    /// The destination marker: outer edge 8 pt (014 FR-004).
    static let markerRadius = 7.0
    static let markerStroke = 2.0

    /// The ship highlight, clear of the 40 pt sprite (014 FR-005).
    static let highlightRadius = 28.0
    static let highlightStroke = 1.5

    /// The planned path's line (014 FR-006).
    static let lineWidth = 1.5

    /// Cyan-green, sRGB (0.35, 0.95, 0.80), at 85 % strength (014 FR-008): linear and premultiplied, as
    /// the shader writes into the sRGB surface. Converted once.
    static let colour: SIMD4<Float> = {
        let strength = 0.85
        func linear(_ encoded: Double) -> Float {
            Float((encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)) * strength)
        }
        return SIMD4(linear(0.35), linear(0.95), linear(0.80), Float(strength))
    }()
}

/// What one frame draws of the current order, in surface pixels from the top-left corner, +y down
/// (014 research R1, contract C2).
///
/// Built every frame from the state and the drawn pose, and kept by nothing, so a new order or an
/// arrival shows on the next frame with no bookkeeping (014 FR-002). The encoder copies it to the GPU as
/// it is, so what the tests check is what is drawn. A plain value of about 4 KB; building one allocates
/// nothing (014 FR-013).
struct OrderOverlay: Sendable {
    /// Room for the drawn ship, all of `PlannedPath.capacity` and the destination: 1 + 256 + 1. A test
    /// keeps the two in step.
    typealias LinePoints = InlineArray<258, Vector2>
    static let lineCapacity = LinePoints.count

    /// The line: the drawn ship position, the planned-path points the ship has not reached, and the
    /// destination (014 FR-006, FR-007). Slots from `lineCount` on are unused.
    let linePoints: LinePoints

    /// 2…258.
    let lineCount: Int

    /// The order's destination, unrounded (014 FR-004, FR-011). The line's last point.
    var markerCentre: Vector2 { linePoints[lineCount - 1] }

    /// The sprite's whole-pixel centre, so ring and sprite never misalign (014 FR-005, research R8).
    let highlightCentre: Vector2

    /// Points → pixels for every size.
    let scale: Double

    /// For pixels → clip space in the shader.
    let surfaceWidthPixels: Double
    let surfaceHeightPixels: Double

    /// The overlay for this frame, or `nil` when nothing of it is drawn: no order, the order complete
    /// (`arrived`), no planned path, or no camera (014 FR-001, FR-015).
    ///
    /// - Parameter shipPose: the drawn pose, the one the sprite is drawn at (013), never `state.ship`
    ///   (014 FR-012).
    /// - Parameter poseTick: the latest tick at or behind `shipPose`; planned-path points at or before it
    ///   are reached and not drawn (014 FR-007, contract C4).
    init?(state: SimulationState, shipPose: ShipPose, poseTick: UInt64, surface: RenderSurface) {
        let autopilot = state.autopilot
        let path = state.plannedPath
        guard
            let order = autopilot.order,
            autopilot.phase != .arrived,
            !path.isEmpty,
            let camera = Camera(surface: surface),
            let sprite = ShipSpritePlacement(position: shipPose.position, heading: shipPose.heading, surface: surface)
        else { return nil }

        let scale = surface.backingScale
        func pixels(_ world: Vector2) -> Vector2 {
            let view = camera.view(fromWorld: world)
            return Vector2(x: view.x * scale, y: view.y * scale)
        }

        var points = LinePoints(repeating: .zero)
        points[0] = pixels(shipPose.position)
        var count = 1
        // `while`, not `for … in`: an unspecialised range iterator allocates in Debug (011 R12).
        var index = 0
        while index < path.count {
            if path.tick(ofPoint: index) > poseTick {
                points[count] = pixels(path[index])
                count += 1
            }
            index += 1
        }
        // Always end on the destination, arrived or capped, so the line ends at the marker (research R3).
        points[count] = pixels(order.destination)
        count += 1

        linePoints = points
        lineCount = count
        highlightCentre = sprite.centrePixels
        self.scale = scale
        surfaceWidthPixels = Double(surface.widthPixels)
        surfaceHeightPixels = Double(surface.heightPixels)
    }
}
