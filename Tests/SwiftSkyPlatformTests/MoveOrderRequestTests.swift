import SwiftSkyRendering
import SwiftSkySimulation
import Testing

@testable import SwiftSkyPlatform

/// A surface `widthPoints × heightPoints` points at `scale`. The sizes used here are whole pixel
/// counts at every scale they are used with, so the camera's size in points is exactly the one asked for.
private func surface(widthPoints: Double, heightPoints: Double, scale: Double) -> RenderSurface {
    RenderSurface(
        widthPixels: UInt32(widthPoints * scale),
        heightPixels: UInt32(heightPoints * scale),
        backingScale: scale
    )
}

private func request(_ x: Double, _ y: Double) -> MoveOrderRequest {
    MoveOrderRequest(viewPoint: Vector2(x: x, y: y))
}

/// The destination of an `.ordered` outcome, or `nil`.
private func destination(_ outcome: MoveOrderOutcome) -> Vector2? {
    if case .ordered(let destination) = outcome { destination } else { nil }
}

/// `true` when `a` and `b` are within `tolerance` on both axes.
private func near(_ a: Vector2?, _ b: Vector2, within tolerance: Double = 1e-9) -> Bool {
    guard let a else { return false }
    return abs(a.x - b.x) <= tolerance && abs(a.y - b.y) <= tolerance
}

/// The surface shapes of contracts C3: portrait phone, landscape phone, a narrow iPad Split View pane,
/// and the odd 1,001 × 667 point surface 005 uses.
private let shapes: [(Double, Double)] = [(393, 852), (852, 393), (320, 1_194), (1_001, 667)]

/// A state whose ship has been flying towards `(300, 200)` for half a second.
private func flyingState() -> SimulationState {
    var state = SimulationState()
    state.setOrder(to: Vector2(x: 300, y: 200))
    return Simulation.advance(state, ticks: 30)
}

@Suite("Move order request")
struct MoveOrderRequestTests {
    // MARK: - User Story 1

    @Test("A tap at the surface's centre orders the ship to the world origin (C1)")
    func centreIsOrigin() {
        var state = SimulationState()
        let outcome = request(196.5, 426).apply(to: &state, on: surface(widthPoints: 393, heightPoints: 852, scale: 3))
        #expect(outcome == .ordered(destination: .zero))
        #expect(state.autopilot.order?.destination == .zero)
    }

    @Test(
        "The destination is (vx − w/2, h/2 − vy), the camera's view → world mapping (C2)",
        arguments: [(0.0, 0.0), (10.0, 20.0), (300.0, 100.0), (393.0, 852.0), (-50.0, 900.0)]
    )
    func cameraMapping(vx: Double, vy: Double) throws {
        let surface = surface(widthPoints: 393, heightPoints: 852, scale: 2)
        var state = SimulationState()
        let outcome = request(vx, vy).apply(to: &state, on: surface)
        let camera = try #require(Camera(surface: surface))
        #expect(outcome == .ordered(destination: Vector2(x: vx - 196.5, y: 426 - vy)))
        #expect(outcome == .ordered(destination: camera.world(fromView: Vector2(x: vx, y: vy))))
    }

    @Test("Right of centre is +x and above centre is +y (C2)")
    func axes() {
        let surface = surface(widthPoints: 393, heightPoints: 852, scale: 2)
        var state = SimulationState()
        let upRight = destination(request(296.5, 326).apply(to: &state, on: surface))
        #expect(upRight == Vector2(x: 100, y: 100))
        let downLeft = destination(request(96.5, 526).apply(to: &state, on: surface))
        #expect(downLeft == Vector2(x: -100, y: -100))
    }

    @Test("An applied request is the order, and the phase is evaluated at once (C5)")
    func orderIsSet() {
        var state = SimulationState()
        let outcome = request(10, 10).apply(to: &state, on: surface(widthPoints: 393, heightPoints: 852, scale: 3))
        let ordered = destination(outcome)
        #expect(ordered != nil)
        #expect(state.autopilot.order?.destination == ordered)
        #expect(state.autopilot.phase != nil)
    }

    @Test("A request adds nothing beyond the order: flown exactly as setOrder(to:) (C10)")
    func flownLikeSetOrder() throws {
        var viaRequest = flyingState()
        var direct = viaRequest
        let outcome = request(50, 700).apply(to: &viaRequest, on: surface(widthPoints: 393, heightPoints: 852, scale: 3))
        let ordered = try #require(destination(outcome))
        direct.setOrder(to: ordered)
        #expect(viaRequest == direct)
        #expect(Simulation.advance(viaRequest, ticks: 1) == Simulation.advance(direct, ticks: 1))
        #expect(Simulation.advance(viaRequest, ticks: 600) == Simulation.advance(direct, ticks: 600))
    }

    // MARK: - User Story 2

    @Test("A request mid-flight replaces the order whole, exactly as setOrder(to:) (C8)")
    func replacesMidFlight() throws {
        let surface = surface(widthPoints: 393, heightPoints: 852, scale: 3)
        var viaRequest = flyingState()
        var direct = viaRequest
        let outcome = request(300, 800).apply(to: &viaRequest, on: surface)
        let b = try #require(destination(outcome))
        direct.setOrder(to: b)
        #expect(viaRequest.autopilot.order?.destination == b)
        #expect(viaRequest == direct)
    }

    @Test("Of two requests drained in one frame, the last is the order (C8)")
    func lastOfTwoWins() {
        let surface = surface(widthPoints: 393, heightPoints: 852, scale: 3)
        var both = flyingState()
        var onlyB = both
        _ = request(10, 10).apply(to: &both, on: surface)
        _ = request(380, 840).apply(to: &both, on: surface)
        _ = request(380, 840).apply(to: &onlyB, on: surface)
        #expect(both == onlyB)
        #expect(both.autopilot.order?.destination == Vector2(x: 183.5, y: -414))
    }

    @Test("A request at the ship's own position orders it there and it keeps station (C9)")
    func orderHere() throws {
        let surface = surface(widthPoints: 393, heightPoints: 852, scale: 3)
        let camera = try #require(Camera(surface: surface))
        var state = SimulationState()
        let here = camera.view(fromWorld: state.ship.position)
        let outcome = MoveOrderRequest(viewPoint: here).apply(to: &state, on: surface)
        #expect(outcome == .ordered(destination: .zero))
        let later = Simulation.advance(state, ticks: 60)
        #expect(later.autopilot.phase == .arrived)
        #expect(near(later.ship.position, .zero, within: ArrivalTolerances.default.position))
    }

}
