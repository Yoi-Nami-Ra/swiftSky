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

    // MARK: - Rotation (US2, C3, C4, C6, C9, SC-002)

    @Test("The image's top edge follows the heading: up at +π/2, left at π, down at −π/2")
    func topEdgeFollowsHeading() throws {
        let surface = try surface(widthPoints: 1280, heightPoints: 720)
        func topEdgeMidpoint(_ heading: Double) throws -> Vector2 {
            let ship = try placement(heading: heading, on: surface)
            return Vector2(x: (ship.topLeft.x + ship.topRight.x) / 2, y: (ship.topLeft.y + ship.topRight.y) / 2)
        }
        let centre = Vector2(x: 1280, y: 720)
        #expect(isNear(try topEdgeMidpoint(.pi / 2), Vector2(x: centre.x, y: centre.y - 40), within: 1e-9))
        #expect(isNear(try topEdgeMidpoint(.pi), Vector2(x: centre.x - 40, y: centre.y), within: 1e-9))
        #expect(isNear(try topEdgeMidpoint(-.pi / 2), Vector2(x: centre.x, y: centre.y + 40), within: 1e-9))
        // Upright at +π/2: the image's top-left is the screen's top-left of the square.
        let upright = try placement(heading: .pi / 2, on: surface)
        #expect(isNear(upright.topLeft, Vector2(x: centre.x - 40, y: centre.y - 40), within: 1e-9))
    }

    @Test(
        "At every heading the ship is a 40 pt square: equal sides and right angles",
        arguments: (0..<8).map { Double($0) * .pi / 4 } + [0.1, 2.5, -1.9]
    )
    func squareAtEveryHeading(heading: Double) throws {
        let ship = try placement(at: Vector2(x: 13, y: -7), heading: heading, on: surface(widthPoints: 1280, heightPoints: 720))
        let sides = [
            distance(ship.topLeft, ship.topRight),
            distance(ship.topRight, ship.bottomRight),
            distance(ship.bottomRight, ship.bottomLeft),
            distance(ship.bottomLeft, ship.topLeft),
        ]
        for side in sides { #expect(abs(side - 80) <= 1e-6) }  // 40 pt at 2×

        // Right angles, from the dot products of adjacent sides.
        func angle(_ corner: Vector2, _ a: Vector2, _ b: Vector2) -> Double {
            let (ux, uy) = (a.x - corner.x, a.y - corner.y)
            let (vx, vy) = (b.x - corner.x, b.y - corner.y)
            return acos((ux * vx + uy * vy) / ((ux * ux + uy * uy).squareRoot() * (vx * vx + vy * vy).squareRoot()))
        }
        #expect(abs(angle(ship.topLeft, ship.topRight, ship.bottomLeft) - .pi / 2) <= 1e-6)
        #expect(abs(angle(ship.topRight, ship.bottomRight, ship.topLeft) - .pi / 2) <= 1e-6)
        #expect(abs(angle(ship.bottomRight, ship.bottomLeft, ship.topRight) - .pi / 2) <= 1e-6)
        #expect(abs(angle(ship.bottomLeft, ship.topLeft, ship.bottomRight) - .pi / 2) <= 1e-6)
    }

    @Test(
        "Corners match an independent rotation by heading − π/2 (SC-002)",
        arguments: (0..<8).map { Double($0) * .pi / 4 }
    )
    func cornersMatchRotation(heading: Double) throws {
        let ship = try placement(heading: heading, on: surface(widthPoints: 1280, heightPoints: 720))
        // Rotate the unrotated image's corner offsets (in world space, +y up) by heading − π/2, then flip
        // y for pixels. The image's top-left is at (−20, +20) pt before rotation, and so on.
        let angle = heading - .pi / 2
        func expected(_ x: Double, _ y: Double) -> Vector2 {
            let rx = x * cos(angle) - y * sin(angle)
            let ry = x * sin(angle) + y * cos(angle)
            return Vector2(x: 1280 + rx * 2, y: 720 - ry * 2)
        }
        #expect(isNear(ship.topLeft, expected(-20, 20), within: 1e-6))
        #expect(isNear(ship.topRight, expected(20, 20), within: 1e-6))
        #expect(isNear(ship.bottomLeft, expected(-20, -20), within: 1e-6))
        #expect(isNear(ship.bottomRight, expected(20, -20), within: 1e-6))
    }

    @Test(
        "At quarter turns every corner is a whole pixel, even on an odd-width surface",
        arguments: [0, .pi / 2, .pi, -.pi / 2] as [Double]
    )
    func quarterTurnsArePixelExact(heading: Double) throws {
        let ship = try placement(heading: heading, on: surface(widthPoints: 1000.5, heightPoints: 600))  // 2,001 px
        for corner in [ship.topLeft, ship.topRight, ship.bottomLeft, ship.bottomRight] {
            #expect(abs(corner.x - corner.x.rounded()) <= 1e-9)
            #expect(abs(corner.y - corner.y.rounded()) <= 1e-9)
        }
    }

    @Test("No jump at the heading's wrap point: π and just above −π give the same corners")
    func noJumpAtWrap() throws {
        let surface = try surface(widthPoints: 1280, heightPoints: 720)
        let a = try placement(heading: .pi, on: surface)
        let b = try placement(heading: (-Double.pi).nextUp, on: surface)
        for (p, q) in [(a.topLeft, b.topLeft), (a.topRight, b.topRight), (a.bottomLeft, b.bottomLeft), (a.bottomRight, b.bottomRight)] {
            #expect(isNear(p, q, within: 1e-9))
        }
    }

    @Test("A ship away from the origin is centred on the camera's view position")
    func awayFromOrigin() throws {
        let surface = try surface(widthPoints: 1280, heightPoints: 720)
        let ship = try placement(at: Vector2(x: 100, y: -50), heading: 1, on: surface)
        let view = try #require(Camera(surface: surface)).view(fromWorld: Vector2(x: 100, y: -50))
        #expect(ship.centrePixels == Vector2(x: view.x * 2, y: view.y * 2))  // (1480, 820): already whole
        #expect(ship.centrePixels == Vector2(x: 1480, y: 820))
    }

    // MARK: - Any window (US3, C7, C8, C10, SC-003)

    @Test(
        "The same size in points gives the same ship at 1×, 2× and 3×",
        arguments: [(Vector2(x: 0, y: 0), 0.0), (Vector2(x: 31.5, y: -12.25), 1.2), (Vector2(x: -400, y: 250), -2.9)]
            as [(Vector2, Double)]
    )
    func sameAtEveryScale(position: Vector2, heading: Double) throws {
        var views: [Vector2] = []
        for scale in [1.0, 2.0, 3.0] {
            let surface = try surface(widthPoints: 1280, heightPoints: 720, scale: scale)
            let ship = try placement(at: position, heading: heading, on: surface)
            views.append(try #require(Camera(surface: surface)).view(fromWorld: position))
            #expect(abs(distance(ship.topLeft, ship.topRight) / scale - 40) <= 1e-9)
            #expect(abs(distance(ship.topLeft, ship.bottomLeft) / scale - 40) <= 1e-9)
        }
        #expect(views[0] == views[1])
        #expect(views[1] == views[2])
    }

    @Test(
        "At the origin the ship is centred on wide, tall and odd-sized surfaces, 80 px across at 2×",
        arguments: [(1280.0, 720.0), (390, 844), (1001, 667)] as [(Double, Double)]
    )
    func centredOnEveryShape(widthPoints: Double, heightPoints: Double) throws {
        let ship = try placement(on: surface(widthPoints: widthPoints, heightPoints: heightPoints))
        #expect(ship.centrePixels == Vector2(x: widthPoints, y: heightPoints))  // (W/2, H/2) px at 2×
        #expect(abs(distance(ship.topLeft, ship.topRight) - 80) <= 1e-9)
        #expect(abs(distance(ship.topLeft, ship.bottomLeft) - 80) <= 1e-9)
    }

    @Test(
        "Far from the origin the centre is still the whole pixel nearest the camera's position",
        arguments: [
            Vector2(x: 1e6, y: 0), Vector2(x: -1e6, y: 0), Vector2(x: 0, y: 1e6), Vector2(x: 0, y: -1e6),
            Vector2(x: 1e6, y: -1e6), Vector2(x: 123_456.789, y: -987_654.321),
        ]
    )
    func farFromOrigin(position: Vector2) throws {
        let surface = try surface(widthPoints: 1280, heightPoints: 720)
        let ship = try placement(at: position, heading: 0.3, on: surface)
        let view = try #require(Camera(surface: surface)).view(fromWorld: position)
        #expect(ship.centrePixels.x == ship.centrePixels.x.rounded())
        #expect(ship.centrePixels.y == ship.centrePixels.y.rounded())
        #expect(abs(ship.centrePixels.x - view.x * 2) <= 0.5)
        #expect(abs(ship.centrePixels.y - view.y * 2) <= 0.5)
    }

    @Test("At the origin the clip-space corners are symmetric about the centre of clip space")
    func clipCornersSymmetric() throws {
        let ship = try placement(heading: 0.8, on: surface(widthPoints: 1280, heightPoints: 720))
        let (bottomLeft, bottomRight, topLeft, topRight) = ship.clipCorners
        #expect(isNear(Vector2(x: bottomLeft.x + topRight.x, y: bottomLeft.y + topRight.y), .zero, within: 1e-12))
        #expect(isNear(Vector2(x: bottomRight.x + topLeft.x, y: bottomRight.y + topLeft.y), .zero, within: 1e-12))
        // And they are the pixel corners, converted.
        #expect(isNear(topLeft, ship.clip(ship.topLeft), within: 0))
    }
}
