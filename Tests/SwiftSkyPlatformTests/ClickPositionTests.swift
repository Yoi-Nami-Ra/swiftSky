import SwiftSkyRendering
import SwiftSkySimulation
import Testing

@testable import SwiftSkyPlatform

/// A surface `widthPoints × heightPoints` points at `scale`; the sizes used are whole pixel counts.
private func surface(widthPoints: Double, heightPoints: Double, scale: Double) -> RenderSurface {
    RenderSurface(
        widthPixels: UInt32(widthPoints * scale),
        heightPixels: UInt32(heightPoints * scale),
        backingScale: scale
    )
}

/// Where a click at `bottomLeft` on `surface` sends the ship, through 008's order request; `nil` if dropped.
private func destination(ofClickAt bottomLeft: Vector2, on surface: RenderSurface, heightPoints: Double) -> Vector2? {
    var state = SimulationState()
    let view = ClickPosition.viewPoint(fromBottomLeft: bottomLeft, heightPoints: heightPoints)
    if case .ordered(let destination) = MoveOrderRequest(viewPoint: view).apply(to: &state, on: surface) {
        return destination
    }
    return nil
}

private func near(_ a: Vector2?, _ b: Vector2, within tolerance: Double = 1e-9) -> Bool {
    guard let a else { return false }
    return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

@Suite("Click position")
struct ClickPositionTests {
    // MARK: - User Story 1

    @Test("Corners and centre flip from bottom-left to top-left (C1)")
    func cornersFlip() {
        let h = 800.0
        let flip = { (x: Double, y: Double) in ClickPosition.viewPoint(fromBottomLeft: Vector2(x: x, y: y), heightPoints: h) }
        #expect(flip(0, 0) == Vector2(x: 0, y: 800))         // bottom-left
        #expect(flip(0, 800) == Vector2(x: 0, y: 0))         // top-left
        #expect(flip(1_280, 800) == Vector2(x: 1_280, y: 0)) // top-right
        #expect(flip(1_280, 0) == Vector2(x: 1_280, y: 800)) // bottom-right
        #expect(flip(640, 400) == Vector2(x: 640, y: 400))   // centre
    }

    @Test("A click near the top goes up and one near the bottom goes down: never mirrored (C4)")
    func notMirrored() throws {
        let surface = surface(widthPoints: 1_280, heightPoints: 800, scale: 2)
        let high = try #require(destination(ofClickAt: Vector2(x: 640, y: 700), on: surface, heightPoints: 800))
        let low = try #require(destination(ofClickAt: Vector2(x: 640, y: 100), on: surface, heightPoints: 800))
        #expect(high.y == 300)
        #expect(low.y == -300)
    }

    @Test("Fractional positions pass through exactly (C5)")
    func fractional() {
        let view = ClickPosition.viewPoint(fromBottomLeft: Vector2(x: 100.25, y: 50.5), heightPoints: 800)
        #expect(view == Vector2(x: 100.25, y: 749.5))
    }
}
