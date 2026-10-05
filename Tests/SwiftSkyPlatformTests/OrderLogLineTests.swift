import SwiftSkySimulation
import Testing

@testable import SwiftSkyPlatform

@Suite("Order log line")
struct OrderLogLineTests {
    @Test("An applied order's line carries the planned path's end, tick, points and arrival")
    func orderedCarriesThePath() {
        var state = SimulationState()
        let destination = Vector2(x: 300, y: -200)
        let accepted = state.setOrder(to: destination)
        #expect(accepted)
        let path = state.plannedPath

        let line = OrderLogLine(.ordered(destination: destination), viewPoint: Vector2(x: 12, y: 34), path: path)

        #expect(line.outcome == .ordered(destination: destination))
        #expect(line.viewPoint == Vector2(x: 12, y: 34))
        #expect(line.predictedEnd == path.last)
        #expect(line.predictedTicks == path.endTick)
        #expect(line.points == path.count)
        #expect(line.arrives == path.reachesArrival)
        #expect(line.arrives)
    }

    @Test("A dropped request keeps its outcome and view point")
    func droppedKeepsOutcome() {
        let state = SimulationState()
        let line = OrderLogLine(.noCamera, viewPoint: Vector2(x: 5, y: 6), path: state.plannedPath)

        #expect(line.outcome == .noCamera)
        #expect(line.viewPoint == Vector2(x: 5, y: 6))
    }

    @Test("A line is a few words, never a copy of the planned path")
    func lineIsSmall() {
        #expect(MemoryLayout<OrderLogLine>.size <= 128)
        #expect(MemoryLayout<OrderLogLine>.size * 16 < MemoryLayout<PlannedPath>.size)
    }
}
