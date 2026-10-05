import Foundation
import SwiftSkySimulation
import Testing

@testable import SwiftSkyRendering

/// The order overlay's geometry (014 contract C2): when it shows, which planned-path points remain, and
/// where the line, marker and highlight are placed. Headless: `OrderOverlay` is a value, and nothing
/// here touches Metal (014 FR-017).
///
/// An 800 × 600 pt surface at 2×: the world origin is at view (400, 300) pt, pixel (800, 600).
@Suite("OrderOverlay")
struct OrderOverlayTests {
    static let surface = RenderSurface(widthPixels: 1_600, heightPixels: 1_200, backingScale: 2)

    /// World → surface pixels on `surface`, the way the camera and the overlay compute it.
    static func pixels(_ world: Vector2) -> Vector2 {
        let view = Camera(surface: surface)!.view(fromWorld: world)
        return Vector2(x: view.x * 2, y: view.y * 2)
    }

    /// A ship at rest at the origin, at `tick`, ordered to `destination`.
    static func ordered(to destination: Vector2, at tick: UInt64 = 100, ship: Ship = Ship()) -> SimulationState {
        var state = SimulationState(tickCount: tick, ship: ship)
        state.setOrder(to: destination)
        return state
    }

    static func overlay(
        _ state: SimulationState,
        pose: ShipPose? = nil,
        poseTick: UInt64? = nil,
        surface: RenderSurface = surface
    ) -> OrderOverlay? {
        OrderOverlay(
            state: state,
            shipPose: pose ?? ShipPose(state.ship),
            poseTick: poseTick ?? state.tickCount - 1,
            surface: surface
        )
    }

    static func line(_ overlay: OrderOverlay) -> [Vector2] {
        (0..<overlay.lineCount).map { overlay.linePoints[$0] }
    }

    // MARK: - When it shows (FR-001, FR-015)

    @Test("Nothing is drawn without an order")
    func noOrder() {
        #expect(Self.overlay(SimulationState(tickCount: 100, ship: Ship())) == nil)
    }

    @Test("Nothing is drawn once the order is complete")
    func arrived() {
        let state = Self.ordered(to: .zero)
        #expect(state.autopilot.phase == .arrived)
        #expect(Self.overlay(state) == nil)
    }

    @Test("Nothing is drawn after a real flight arrives, and something is drawn the tick before")
    func arrivesAfterFlight() throws {
        var state = Self.ordered(to: Vector2(x: 200, y: 0))
        let arrival = state.plannedPath.endTick
        state = Simulation.advance(state, ticks: Int(arrival - state.tickCount) - 1)
        #expect(state.autopilot.phase != .arrived)
        #expect(Self.overlay(state) != nil)
        state = Simulation.advance(state, ticks: 1)
        #expect(state.autopilot.phase == .arrived)
        #expect(Self.overlay(state) == nil)
    }

    @Test("Nothing is drawn on a surface without a camera")
    func noCamera() {
        let state = Self.ordered(to: Vector2(x: 300, y: 100))
        let empty = RenderSurface(widthPixels: 0, heightPixels: 0, backingScale: 2)
        #expect(Self.overlay(state, surface: empty) == nil)
    }

    // MARK: - Placement (FR-004–FR-006, FR-011, SC-001, SC-002)

    @Test("The marker is the destination exactly, and the line ends there")
    func markerIsTheDestination() throws {
        let overlay = try #require(Self.overlay(Self.ordered(to: Vector2(x: 300, y: 100))))
        #expect(overlay.markerCentre == Vector2(x: 1_400, y: 400))
        #expect(overlay.linePoints[overlay.lineCount - 1] == overlay.markerCentre)
    }

    @Test("The line starts at the drawn ship, unrounded; the highlight is the sprite's whole-pixel centre")
    func startAndHighlight() throws {
        let state = Self.ordered(to: Vector2(x: 300, y: 100))
        // A blended pose between pixels, as interpolation gives (013).
        let pose = ShipPose(position: Vector2(x: 0.3, y: -0.7), heading: 0.4)
        let overlay = try #require(Self.overlay(state, pose: pose))
        #expect(overlay.linePoints[0] == Self.pixels(pose.position))
        let sprite = try #require(ShipSpritePlacement(position: pose.position, heading: pose.heading, surface: Self.surface))
        #expect(overlay.highlightCentre == sprite.centrePixels)
        #expect(overlay.highlightCentre == Vector2(x: 801, y: 601))
    }

    @Test("A capped prediction still ends the line at the destination")
    func cappedEndsAtTheDestination() throws {
        let limits = ShipLimits(
            maxThrustAcceleration: 0,
            maxAngularSpeed: ShipLimits.default.maxAngularSpeed,
            maxAngularAcceleration: ShipLimits.default.maxAngularAcceleration
        )
        let state = Self.ordered(to: Vector2(x: 300, y: 100), ship: Ship(limits: limits))
        #expect(!state.plannedPath.reachesArrival)
        let overlay = try #require(Self.overlay(state))
        #expect(overlay.lineCount == state.plannedPath.count + 2)
        #expect(overlay.markerCentre == Vector2(x: 1_400, y: 400))
        // The last predicted point is not the destination; the line runs on to it.
        #expect(overlay.linePoints[overlay.lineCount - 2] == Self.pixels(state.plannedPath.last!))
        #expect(overlay.linePoints[overlay.lineCount - 2] != overlay.markerCentre)
    }

    @Test("A new order moves the marker to the new destination")
    func newOrder() throws {
        var state = Self.ordered(to: Vector2(x: 300, y: 100))
        state = Simulation.advance(state, ticks: 30)
        state.setOrder(to: Vector2(x: -200, y: -50))
        let overlay = try #require(Self.overlay(state))
        #expect(overlay.markerCentre == Self.pixels(Vector2(x: -200, y: -50)))
        #expect(Array(Self.line(overlay).dropFirst().dropLast()) == state.plannedPath.points.map(Self.pixels))
    }

    // MARK: - Reached points (FR-007, research R2)

    @Test("Before the order's first tick, every path point is drawn, in order")
    func allPointsAhead() throws {
        let state = Self.ordered(to: Vector2(x: 300, y: 100))
        let path = state.plannedPath
        let overlay = try #require(Self.overlay(state, poseTick: path.startTick - 1))
        #expect(overlay.lineCount == path.count + 2)
        #expect(Array(Self.line(overlay)[1...path.count]) == path.points.map(Self.pixels))
    }

    @Test(
        "Partway, exactly the points after the pose tick remain, in order",
        arguments: [0, 1, 10, 50]
    )
    func pointsAfterThePoseTick(reached index: Int) throws {
        let state = Self.ordered(to: Vector2(x: 300, y: 100))
        let path = state.plannedPath
        try #require(index < path.count - 1)
        let overlay = try #require(Self.overlay(state, poseTick: path.tick(ofPoint: index)))
        let remaining = Array(path.points.map(Self.pixels)[(index + 1)...])
        #expect(overlay.lineCount == remaining.count + 2)
        #expect(Array(Self.line(overlay)[1..<(overlay.lineCount - 1)]) == remaining)
    }

    @Test("Past the last point, only the ship and the destination remain")
    func nothingAhead() throws {
        let state = Self.ordered(to: Vector2(x: 300, y: 100))
        let overlay = try #require(Self.overlay(state, poseTick: state.plannedPath.endTick))
        #expect(overlay.lineCount == 2)
    }

    // MARK: - Capacity (FR-013)

    @Test("The line has room for the ship, a full planned path and the destination")
    func capacity() {
        #expect(OrderOverlay.lineCapacity == PlannedPath.capacity + 2)
    }

    @Test("A full 256-point path gives a full 258-point line")
    func fullPath() throws {
        // Find an order whose prediction fills every slot: lengths with 255 × spacing ticks or just under.
        var distance = 100.0
        var found: SimulationState?
        while distance < 5_000, found == nil {
            let state = Self.ordered(to: Vector2(x: distance, y: 0))
            if state.plannedPath.count == PlannedPath.capacity { found = state }
            distance += 1
        }
        let state = try #require(found, "no order up to 5,000 units fills the path")
        let overlay = try #require(Self.overlay(state, poseTick: state.plannedPath.startTick - 1))
        #expect(overlay.lineCount == OrderOverlay.lineCapacity)
        #expect(overlay.markerCentre == Self.pixels(state.autopilot.order!.destination))
    }
}

extension PlannedPath {
    /// The points as an array, for comparisons.
    var points: [Vector2] { (0..<count).map { self[$0] } }
}
