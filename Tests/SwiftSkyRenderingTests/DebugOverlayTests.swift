import Foundation
import Testing

@testable import SwiftSkyRendering
@testable import SwiftSkySimulation

@Suite("Debug overlay")
struct DebugOverlayTests {
    private let surface = RenderSurface(
        widthPixels: 2560,
        heightPixels: 1440,
        backingScale: 2,
        safeAreaInsets: SurfaceInsets(top: 24, left: 44, bottom: 0, right: 0)
    )

    /// The stored characters, with a line break wherever the pen moved down.
    private func lines(in buffer: TextBuffer) -> [String] {
        var lines: [String] = []
        var current = ""
        var lastY: UInt16?
        for instance in buffer.instances {
            if let lastY, instance.y != lastY {
                lines.append(current)
                current = ""
            }
            current.append(Character(Unicode.Scalar(UInt8(instance.cell) + GlyphAtlasBitmap.firstCode)))
            lastY = instance.y
        }
        lines.append(current)
        return lines
    }

    private func written(_ statistics: DebugOverlayStatistics?, ship: DebugOverlayShip? = nil) -> TextBuffer {
        let overlay = DebugOverlay()
        overlay.statistics = statistics
        overlay.ship = ship
        let buffer = TextBuffer(metrics: syntheticMetrics(scale: 2))
        buffer.clear()
        overlay.write(into: buffer, surface: surface)
        return buffer
    }

    private let example = DebugOverlayStatistics(
        meanFrameSeconds: 0.000_41,
        worstFrameSeconds: 0.000_97,
        budgetSeconds: 1.0 / 120.0,
        droppedFrames: 0,
        skippedFrames: 0,
        tickCount: 61
    )

    @Test("Nothing is written before the first snapshot arrives")
    func nothingBeforeFirstSnapshot() {
        #expect(written(nil).count == 0)
    }

    @Test("Six labelled lines, in order, matching the contract's example")
    func contractExample() {
        #expect(lines(in: written(example)) == [
            "mean      0.41 ms",
            "worst     0.97 ms",
            "budget    8.33 ms",
            "dropped 0",
            "skipped 0",
            "ticks   61",
        ])
    }

    @Test("Mean and worst read `--`, aligned with the numbers, until a full second has been measured")
    func unknownMeanAndWorst() {
        var statistics = example
        statistics.meanFrameSeconds = nil
        statistics.worstFrameSeconds = nil
        let text = lines(in: written(statistics))
        #expect(text[0] == "mean        -- ms")
        #expect(text[1] == "worst       -- ms")
        #expect(text[2] == "budget    8.33 ms")
    }

    @Test("Every line fits in 33 characters at the normal-range maxima (FR-005)")
    func fitsNarrowestSurface() {
        let statistics = DebugOverlayStatistics(
            meanFrameSeconds: 0.999_99,
            worstFrameSeconds: 0.999_99,
            budgetSeconds: 0.999_99,
            droppedFrames: 9_999_999,
            skippedFrames: 9_999_999,
            tickCount: 9_999_999
        )
        let buffer = written(statistics)
        let text = lines(in: buffer)
        #expect(text.count == 6)
        #expect(text.allSatisfy { $0.count <= 33 })
        #expect(buffer.count < 128)
        #expect(!buffer.didOverflow)
    }

    @Test("Counts are written in full up to UInt64.max")
    func largestCounts() {
        let statistics = DebugOverlayStatistics(
            meanFrameSeconds: nil,
            worstFrameSeconds: nil,
            budgetSeconds: 1.0 / 60.0,
            droppedFrames: .max,
            skippedFrames: .max,
            tickCount: .max
        )
        let text = lines(in: written(statistics))
        #expect(text[3] == "dropped 18446744073709551615")
        #expect(text[4] == "skipped 18446744073709551615")
        #expect(text[5] == "ticks   18446744073709551615")
    }

    @Test("A slow frame is written in full, never cut short")
    func slowFrame() {
        var statistics = example
        statistics.worstFrameSeconds = 1.2345
        #expect(lines(in: written(statistics))[1] == "worst   1234.50 ms")
    }

    @Test("The overlay starts 8 points inside the safe area's top-left")
    func anchor() {
        let buffer = written(example)
        let metrics = buffer.metrics
        let first = buffer.instances[0]
        let expectedX = TextMetrics.pixels(44 + 8, scale: 2) + metrics.cellOriginOffsetX
        let expectedY = TextMetrics.pixels(24 + 8, scale: 2) + metrics.ascentPixels + metrics.cellOriginOffsetY
        #expect(Int(first.x) == expectedX)
        #expect(Int(first.y) == expectedY)
    }

    // MARK: Ship lines (015)

    private let atRest = DebugOverlayShip(
        position: .zero, velocity: .zero, heading: 0, angularVelocity: 0, order: nil
    )

    private let inFlight = DebugOverlayShip(
        position: Vector2(x: -12.5, y: 40),
        velocity: Vector2(x: 30, y: -40),
        heading: atan2(-40.0, 30.0),
        angularVelocity: 0,
        order: DebugOverlayShip.Order(
            phase: .burning,
            destination: Vector2(x: 300, y: -200),
            distance: (312.5 * 312.5 + 240.0 * 240.0).squareRoot()
        )
    )

    @Test("Without a ship snapshot only the six frame-statistic lines are written")
    func noShipSixLines() {
        #expect(lines(in: written(example)).count == 6)
    }

    @Test("A ship at rest reads zero on every ship line (contract C3, first example)")
    func shipAtRest() {
        let text = lines(in: written(example, ship: atRest))
        #expect(Array(text[6...10]) == [
            "pos     x     0.00 y     0.00",
            "vel     x     0.00 y     0.00",
            "speed        0.00 u/s",
            "heading      0.00 deg",
            "turn         0.00 deg/s",
        ])
    }

    @Test("A ship in flight: signed position and velocity, speed from the exact velocity, heading in degrees")
    func shipInFlight() {
        let text = lines(in: written(example, ship: inFlight))
        #expect(Array(text[6...10]) == [
            "pos     x   -12.50 y    40.00",
            "vel     x    30.00 y   -40.00",
            "speed       50.00 u/s",
            "heading    -53.13 deg",
            "turn         0.00 deg/s",
        ])
    }

    @Test("A turn of π rad/s reads 180.00 deg/s; clockwise turns are negative")
    func turnInDegrees() {
        var ship = atRest
        ship.angularVelocity = .pi
        #expect(lines(in: written(example, ship: ship))[10] == "turn       180.00 deg/s")
        ship.angularVelocity = -.pi / 2
        #expect(lines(in: written(example, ship: ship))[10] == "turn       -90.00 deg/s")
    }

    @Test(
        "Heading degrees, with −180.00 after rounding written as 180 (FR-002)",
        arguments: [
            (0.0, 0.0),
            (Double.pi, 180.0),
            (-Double.pi / 2, -90.0),
            (-Double.pi + 1e-9, 180.0),
            (-179.996 * Double.pi / 180, 180.0),
        ]
    )
    func headingDegrees(radians: Double, expected: Double) {
        #expect(abs(DebugOverlay.headingDegrees(radians) - expected) < 1e-9)
    }

    @Test("A heading just inside the seam keeps its sign; one at the seam reads 180.00")
    func headingSeamText() {
        var ship = atRest
        ship.heading = -179.994 * .pi / 180
        #expect(lines(in: written(example, ship: ship))[9] == "heading   -179.99 deg")
        ship.heading = -.pi + 1e-9
        #expect(lines(in: written(example, ship: ship))[9] == "heading    180.00 deg")
        ship.heading = .pi
        #expect(lines(in: written(example, ship: ship))[9] == "heading    180.00 deg")
    }

    // MARK: Order lines (015)

    @Test("Without an order the last line is `order   none`, with no destination or distance line")
    func noOrder() {
        let text = lines(in: written(example, ship: atRest))
        #expect(text.count == 12)
        #expect(text[11] == "order   none")
    }

    @Test("An order in flight: phase, destination and distance (contract C3, second example)")
    func orderInFlight() {
        let text = lines(in: written(example, ship: inFlight))
        #expect(text.count == 14)
        #expect(Array(text[11...13]) == [
            "order   burning",
            "dest    x   300.00 y  -200.00",
            "dist       394.03 u",
        ])
    }

    @Test(
        "Each phase is written in lower case, as named; arrived keeps the destination and distance",
        arguments: [
            (AutopilotPhase.aligning, "order   aligning"),
            (.burning, "order   burning"),
            (.flipping, "order   flipping"),
            (.braking, "order   braking"),
            (.arrived, "order   arrived"),
        ]
    )
    func phases(phase: AutopilotPhase, expected: String) {
        var ship = inFlight
        ship.order?.phase = phase
        let text = lines(in: written(example, ship: ship))
        #expect(text[11] == expected)
        #expect(text.count == 14)
    }

    @Test("The snapshot copies the ship from the state, with no order before one is given")
    func snapshotWithoutOrder() {
        let ship = Ship(
            position: Vector2(x: 3, y: -4), velocity: Vector2(x: 1, y: 2), heading: 1, angularVelocity: -0.5
        )
        let snapshot = DebugOverlayShip(SimulationState(tickCount: 7, ship: ship))
        #expect(snapshot == DebugOverlayShip(
            position: Vector2(x: 3, y: -4), velocity: Vector2(x: 1, y: 2), heading: 1, angularVelocity: -0.5,
            order: nil, cargo: DebugOverlayShip.Cargo(ship.hold)
        ))
    }

    @Test("The snapshot carries the order's phase, destination and the state's own distance remaining")
    func snapshotWithOrder() throws {
        var state = SimulationState()
        let ordered = state.setOrder(to: Vector2(x: 300, y: -400))
        #expect(ordered)
        state = Simulation.advance(state, ticks: 30)
        let snapshot = DebugOverlayShip(state)
        let order = try #require(snapshot.order)
        #expect(order.destination == Vector2(x: 300, y: -400))
        #expect(order.phase == state.autopilot.phase)
        #expect(order.distance == state.distanceRemaining)
        #expect(snapshot.position == state.ship.position)
        #expect(snapshot.velocity == state.ship.velocity)
    }

    @Test("An order without a phase, which the autopilot never produces, is treated as no order")
    func orderWithoutPhase() {
        var state = SimulationState()
        let ordered = state.setOrder(to: Vector2(x: 10, y: 10))
        #expect(ordered)
        state.autopilot.phase = nil
        #expect(DebugOverlayShip(state).order == nil)
    }

    // MARK: Width and capacity (015 FR-007)

    @Test("At the normal-range maxima with an order, every line fits in 33 characters and nothing overflows")
    func fitsNarrowestSurfaceWithShip() {
        let statistics = DebugOverlayStatistics(
            meanFrameSeconds: 0.999_99,
            worstFrameSeconds: 0.999_99,
            budgetSeconds: 0.999_99,
            droppedFrames: 9_999_999,
            skippedFrames: 9_999_999,
            tickCount: 9_999_999
        )
        let ship = DebugOverlayShip(
            position: Vector2(x: -99_999.99, y: -99_999.99),
            velocity: Vector2(x: -70_000, y: -70_000),
            heading: -.pi / 2 - 0.001,
            angularVelocity: -.pi,
            order: DebugOverlayShip.Order(
                phase: .aligning,
                destination: Vector2(x: -99_999.99, y: -99_999.99),
                distance: 99_999.99
            )
        )
        let buffer = written(statistics, ship: ship)
        let text = lines(in: buffer)
        #expect(text.count == 14)
        #expect(text.allSatisfy { $0.count <= 33 })
        #expect(buffer.count < 384)
        #expect(!buffer.didOverflow)
    }

    @Test("A value beyond the column is written in full, never cut short")
    func wideValueInFull() {
        var ship = atRest
        ship.position = Vector2(x: -1_234_567.891, y: 0)
        #expect(lines(in: written(example, ship: ship))[6] == "pos     x-1234567.89 y     0.00")
    }
}
