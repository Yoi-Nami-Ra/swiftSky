import SwiftSkySimulation
import Testing

@testable import SwiftSkyRendering

/// A surface of the given size in points, for finite, positive scales; the invalid-scale cases build
/// their surfaces directly. The pixel counts must come out whole and fit in `UInt32`, or `UInt32(_:)`
/// would truncate them silently — or trap and take the whole test run down with it. A bad size fails
/// the calling test instead.
private func surface(
    widthPoints: Double,
    heightPoints: Double,
    scale: Double = 2,
    insets: SurfaceInsets = .zero
) throws -> RenderSurface {
    let (widthPixels, heightPixels) = (widthPoints * scale, heightPoints * scale)
    let pixelCounts = 0...Double(UInt32.max)
    try #require(
        widthPixels == widthPixels.rounded() && pixelCounts.contains(widthPixels)
            && heightPixels == heightPixels.rounded() && pixelCounts.contains(heightPixels),
        "\(widthPoints) × \(heightPoints) pt at \(scale)× is not a whole pixel size"
    )
    return RenderSurface(
        widthPixels: UInt32(widthPixels),
        heightPixels: UInt32(heightPixels),
        backingScale: scale,
        safeAreaInsets: insets
    )
}

private func camera(widthPoints: Double, heightPoints: Double, scale: Double = 2) throws -> Camera {
    try #require(Camera(surface: surface(widthPoints: widthPoints, heightPoints: heightPoints, scale: scale)))
}

@Suite("Camera")
struct CameraTests {
    // MARK: - Construction (C1–C3, C2a)

    @Test(
        "No camera for a surface without area",
        arguments: [(0, 1440), (2560, 0), (0, 0)] as [(UInt32, UInt32)]
    )
    func noCameraWithoutArea(width: UInt32, height: UInt32) {
        let surface = RenderSurface(widthPixels: width, heightPixels: height, backingScale: 2)
        #expect(Camera(surface: surface) == nil)
    }

    @Test(
        "No camera for an unusable backing scale",
        arguments: [0, -0.0, -2, .nan, .infinity, -.infinity] as [Double]
    )
    func noCameraForBadScale(scale: Double) {
        let surface = RenderSurface(widthPixels: 2560, heightPixels: 1440, backingScale: scale)
        #expect(Camera(surface: surface) == nil)
    }

    @Test(
        "No camera when the scale would make the half-extents overflow or underflow",
        arguments: [
            (2560, 1440, .leastNonzeroMagnitude),  // both ÷ scale overflow to +∞
            (2560, 1440, 1e-310),
            (1, 1, .greatestFiniteMagnitude),  // both ÷ scale ÷ 2 underflow to subnormals
            // One axis at a time, so each half-extent's guard is exercised on its own.
            (2560, 1, 1e-305),  // only the width overflows
            (1, 2560, 1e-305),  // only the height overflows
            (1, 2560, .greatestFiniteMagnitude),  // only the width underflows
            (2560, 1, .greatestFiniteMagnitude),  // only the height underflows
        ] as [(UInt32, UInt32, Double)]
    )
    func noCameraForExtremeScale(width: UInt32, height: UInt32, scale: Double) {
        let surface = RenderSurface(widthPixels: width, heightPixels: height, backingScale: scale)
        #expect(Camera(surface: surface) == nil)
    }

    @Test("Half-extents are the surface size in points, halved")
    func halfExtents() throws {
        let surface = RenderSurface(widthPixels: 2560, heightPixels: 1440, backingScale: 2)
        let camera = try #require(Camera(surface: surface))
        #expect(camera.halfWidth == 640)
        #expect(camera.halfHeight == 360)
        #expect(camera.widthPoints == 1280)
        #expect(camera.heightPoints == 720)
    }

    @Test("A fractional point size is used exactly, unrounded")
    func fractionalPointSize() throws {
        let surface = RenderSurface(widthPixels: 1001, heightPixels: 667, backingScale: 2)
        let camera = try #require(Camera(surface: surface))
        #expect(camera.halfWidth == 250.25)
        #expect(camera.halfHeight == 166.75)
    }

    @Test("The ship is 40 world units long")
    func shipLength() {
        #expect(GameSpace.shipLength == 40)
    }

    // MARK: - World → view and world → clip (US1)

    @Test(
        "Origin at the centre, corners at the corners, edges at ±1",
        arguments: [(1920, 1080), (1001, 667), (768, 1024)] as [(Double, Double)]
    )
    func centreAndCorners(width: Double, height: Double) throws {
        let camera = try camera(widthPoints: width, heightPoints: height)
        let (w2, h2) = (width / 2, height / 2)

        #expect(camera.view(fromWorld: .zero) == Vector2(x: w2, y: h2))
        #expect(camera.view(fromWorld: Vector2(x: -w2, y: h2)) == Vector2(x: 0, y: 0))
        #expect(camera.view(fromWorld: Vector2(x: w2, y: h2)) == Vector2(x: width, y: 0))
        #expect(camera.view(fromWorld: Vector2(x: -w2, y: -h2)) == Vector2(x: 0, y: height))
        #expect(camera.view(fromWorld: Vector2(x: w2, y: -h2)) == Vector2(x: width, y: height))

        #expect(camera.clip(fromWorld: .zero) == Vector2(x: 0, y: 0))
        #expect(camera.clip(fromWorld: Vector2(x: -w2, y: h2)) == Vector2(x: -1, y: 1))
        #expect(camera.clip(fromWorld: Vector2(x: w2, y: h2)) == Vector2(x: 1, y: 1))
        #expect(camera.clip(fromWorld: Vector2(x: -w2, y: -h2)) == Vector2(x: -1, y: -1))
        #expect(camera.clip(fromWorld: Vector2(x: w2, y: -h2)) == Vector2(x: 1, y: -1))
    }

    @Test("One world unit is one point, with +y up")
    func oneUnitIsOnePoint() throws {
        let camera = try camera(widthPoints: 1920, heightPoints: 1080)
        let base = camera.view(fromWorld: Vector2(x: 37, y: -12))
        let right = camera.view(fromWorld: Vector2(x: 38, y: -12))
        let up = camera.view(fromWorld: Vector2(x: 37, y: -11))

        #expect(right.x - base.x == 1)
        #expect(right.y == base.y)
        #expect(up.y - base.y == -1)
        #expect(up.x == base.x)
    }

    @Test("Points beyond the surface map off it, unclamped and finite")
    func offSurface() throws {
        let camera = try camera(widthPoints: 1920, heightPoints: 1080)
        let farAway = [(1e6, 1e6), (-1e6, 1e6), (1e6, -1e6), (-1e6, -1e6)].map { Vector2(x: $0.0, y: $0.1) }
        for world in farAway {
            let view = camera.view(fromWorld: world)
            let clip = camera.clip(fromWorld: world)
            #expect(view.x.isFinite && view.y.isFinite && clip.x.isFinite && clip.y.isFinite)
            #expect(view.x < 0 || view.x > 1920)
            #expect(view.y < 0 || view.y > 1080)
            #expect(abs(clip.x) > 1 && abs(clip.y) > 1)
        }

        // And back: a pointer dragged past the window edge gives the world point that would be there.
        #expect(camera.world(fromView: Vector2(x: -100, y: 1200)) == Vector2(x: -1060, y: -660))
        #expect(camera.world(fromView: Vector2(x: 1e6, y: -1e6)) == Vector2(x: 1e6 - 960, y: 1e6 + 540))
    }

    @Test("A non-finite input passes through as non-finite")
    func nonFinitePassesThrough() throws {
        let camera = try camera(widthPoints: 1920, heightPoints: 1080)
        #expect(camera.view(fromWorld: Vector2(x: .nan, y: 0)).x.isNaN)
        #expect(camera.view(fromWorld: Vector2(x: 0, y: .infinity)).y.isInfinite)
        #expect(camera.clip(fromWorld: Vector2(x: .infinity, y: 0)).x.isInfinite)
        #expect(camera.world(fromView: Vector2(x: 0, y: .nan)).y.isNaN)
    }

    // MARK: - View → world (US2)

    @Test("Known view positions map to known world points")
    func viewToWorld() throws {
        let camera = try camera(widthPoints: 1001, heightPoints: 667)
        #expect(camera.world(fromView: Vector2(x: 500.5, y: 333.5)) == .zero)
        #expect(camera.world(fromView: Vector2(x: 0, y: 0)) == Vector2(x: -500.5, y: 333.5))
        #expect(camera.world(fromView: Vector2(x: 1001, y: 667)) == Vector2(x: 500.5, y: -333.5))
    }

    @Test("View → world → view round-trips within 1e-9 points, on and off the surface")
    func roundTrip() throws {
        let (width, height) = (1001.0, 667.0)
        let camera = try camera(widthPoints: width, heightPoints: height)
        // A 40 × 25 grid: 1,000 positions from −1× to +2× the surface in each axis (SC-002).
        for i in 0..<40 {
            for j in 0..<25 {
                let start = Vector2(
                    x: -width + 3 * width * Double(i) / 39,
                    y: -height + 3 * height * Double(j) / 24
                )
                let back = camera.view(fromWorld: camera.world(fromView: start))
                #expect(abs(back.x - start.x) <= 1e-9)
                #expect(abs(back.y - start.y) <= 1e-9)
            }
        }
    }

    // MARK: - Every display and window size (US3)

    @Test("The same point size gives the same camera at 1×, 2× and 3×")
    func backingScaleIndependence() throws {
        let cameras = try [1.0, 2, 3].map { try camera(widthPoints: 1001, heightPoints: 667, scale: $0) }
        #expect(cameras[0] == cameras[1])
        #expect(cameras[1] == cameras[2])

        for world in [Vector2.zero, Vector2(x: 123.25, y: -45.5), Vector2(x: -500.5, y: 333.5)] {
            let views = cameras.map { $0.view(fromWorld: world) }
            let clips = cameras.map { $0.clip(fromWorld: world) }
            #expect(views.allSatisfy { $0 == views[0] })
            #expect(clips.allSatisfy { $0 == clips[0] })
        }
    }

    @Test("A resize puts the origin at the new centre, including odd point sizes")
    func resize() throws {
        let before = try camera(widthPoints: 1280, heightPoints: 720)
        let after = try camera(widthPoints: 1001, heightPoints: 667)
        #expect(before.view(fromWorld: .zero) == Vector2(x: 640, y: 360))
        #expect(after.view(fromWorld: .zero) == Vector2(x: 500.5, y: 333.5))
    }

    @Test(
        "Safe-area insets change nothing: the origin is the centre of the whole surface",
        arguments: [
            SurfaceInsets(top: 59, left: 0, bottom: 34, right: 0),  // portrait: status bar, home indicator
            SurfaceInsets(top: 0, left: 59, bottom: 21, right: 59),  // landscape: camera cutout on the sides
        ]
    )
    func insetsIgnored(insets: SurfaceInsets) throws {
        let inset = try #require(Camera(surface: surface(widthPoints: 1001, heightPoints: 667, insets: insets)))
        let plain = try #require(Camera(surface: surface(widthPoints: 1001, heightPoints: 667)))
        #expect(inset == plain)
        #expect(inset.view(fromWorld: .zero) == Vector2(x: 500.5, y: 333.5))
    }
}
