import Foundation
import SwiftSkySimulation
import Testing

@testable import SwiftSkyRendering

/// A surface of the given size in points. The pixel counts must come out whole, or the test fails
/// rather than truncating them (as in `CameraTests`).
private func surface(widthPoints: Double, heightPoints: Double, scale: Double = 2) throws -> RenderSurface {
    let (widthPixels, heightPixels) = (widthPoints * scale, heightPoints * scale)
    try #require(
        widthPixels == widthPixels.rounded() && heightPixels == heightPixels.rounded()
            && widthPixels >= 0 && heightPixels >= 0,
        "\(widthPoints) × \(heightPoints) pt at \(scale)× is not a whole pixel size"
    )
    return RenderSurface(widthPixels: UInt32(widthPixels), heightPixels: UInt32(heightPixels), backingScale: scale)
}

private func placement(
    at position: Vector2 = .zero,
    heading: Double = 0,
    on surface: RenderSurface
) throws -> ShipSpritePlacement {
    try #require(ShipSpritePlacement(position: position, heading: heading, surface: surface))
}

private func distance(_ a: Vector2, _ b: Vector2) -> Double {
    ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
}

private func isNear(_ a: Vector2, _ b: Vector2, within tolerance: Double) -> Bool {
    abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

@Suite("ShipSpritePlacement")
struct ShipSpritePlacementTests {
    // MARK: - No camera, no placement (C1)

    @Test(
        "No placement for a surface without a camera",
        arguments: [(0, 1440, 2), (2560, 0, 2), (0, 0, 2), (2560, 1440, 0), (2560, 1440, .nan)]
            as [(UInt32, UInt32, Double)]
    )
    func noPlacementWithoutCamera(width: UInt32, height: UInt32, scale: Double) {
        let surface = RenderSurface(widthPixels: width, heightPixels: height, backingScale: scale)
        #expect(ShipSpritePlacement(position: .zero, heading: 0, surface: surface) == nil)
    }

    @Test("A placement for every surface that has a camera")
    func placementWithCamera() throws {
        let surface = try surface(widthPoints: 1280, heightPoints: 720)
        #expect(Camera(surface: surface) != nil)
        #expect(ShipSpritePlacement(position: .zero, heading: 0, surface: surface) != nil)
    }

    // MARK: - At launch (US1, C2, C5)

    @Test("At the origin on a 1280 × 720 pt 2× surface, the ship covers 1240…1320 × 680…760 px")
    func launchPlacement() throws {
        let ship = try placement(on: surface(widthPoints: 1280, heightPoints: 720))
        #expect(ship.centrePixels == Vector2(x: 1280, y: 720))
        let corners = [ship.topLeft, ship.topRight, ship.bottomLeft, ship.bottomRight]
        let tolerance = 1e-9
        #expect(abs(corners.map(\.x).min()! - 1240) <= tolerance)
        #expect(abs(corners.map(\.x).max()! - 1320) <= tolerance)
        #expect(abs(corners.map(\.y).min()! - 680) <= tolerance)
        #expect(abs(corners.map(\.y).max()! - 760) <= tolerance)
    }

    @Test("At heading zero the image's top edge is the right-hand edge, running down the screen")
    func headingZeroFacesRight() throws {
        let ship = try placement(on: surface(widthPoints: 1280, heightPoints: 720))
        let k = 40.0  // half of 40 pt at 2×
        #expect(abs(ship.topLeft.x - (ship.centrePixels.x + k)) <= 1e-9)
        #expect(abs(ship.topRight.x - (ship.centrePixels.x + k)) <= 1e-9)
        // The image's left-to-right runs +y in pixels: the image's right side points down.
        #expect(ship.topRight.y > ship.topLeft.y)
        #expect(abs(ship.topRight.y - ship.topLeft.y - 2 * k) <= 1e-9)
    }

    @Test(
        "The centre is a whole pixel, within half a pixel of the camera's position, and the corners' mean",
        arguments: [
            (Vector2(x: 0, y: 0), 1280.0, 720.0, 2.0),
            (Vector2(x: 0.3, y: -0.2), 1280, 720, 2),
            (Vector2(x: 12.25, y: 7.75), 1001, 667, 1),
            (Vector2(x: -3.4, y: 101.6), 390, 844, 3),
        ] as [(Vector2, Double, Double, Double)]
    )
    func centreIsSnapped(position: Vector2, widthPoints: Double, heightPoints: Double, scale: Double) throws {
        let surface = try surface(widthPoints: widthPoints, heightPoints: heightPoints, scale: scale)
        let ship = try placement(at: position, heading: 0.7, on: surface)
        let view = try #require(Camera(surface: surface)).view(fromWorld: position)

        #expect(ship.centrePixels.x == ship.centrePixels.x.rounded())
        #expect(ship.centrePixels.y == ship.centrePixels.y.rounded())
        #expect(abs(ship.centrePixels.x - view.x * scale) <= 0.5)
        #expect(abs(ship.centrePixels.y - view.y * scale) <= 0.5)

        let mean = Vector2(
            x: (ship.topLeft.x + ship.topRight.x + ship.bottomLeft.x + ship.bottomRight.x) / 4,
            y: (ship.topLeft.y + ship.topRight.y + ship.bottomLeft.y + ship.bottomRight.y) / 4
        )
        #expect(isNear(mean, ship.centrePixels, within: 1e-9))
    }
}
