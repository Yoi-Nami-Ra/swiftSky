import Foundation
import Testing

@testable import SwiftSkySimulation

/// The planned path (010). Every prediction is checked against the real flight: the same state advanced
/// one tick at a time by `Simulation.advance`, the public way the frame loop flies the ship. Like the
/// rest of the logic layer's tests, these need no clock, no GPU and no app (010 FR-013).
///
/// Exactness is asserted with `bits(_:)`, never `==`, wherever the spec says "bit for bit".
@Suite("Planned path")
struct PlannedPathTests {
    // MARK: - US1: the path is the real flight

    @Test(
        "From rest, every order's path is the real flight, ending where it first reports arrival (SC-001, SC-002)",
        arguments: AutopilotTests.restDistances, 0..<16
    )
    func matchesTheRealFlightFromRest(distance: Double, direction: Int) {
        let angle = Double(direction) * .pi / 8
        let state = AutopilotTests.ordered(to: Vector2(x: distance * cos(angle), y: distance * sin(angle)))
        expectPathIsTheRealFlight(state, "distance \(distance), direction \(direction)")
    }

    @Test(
        "From moving starts, every order's path is the real flight (SC-001, SC-002)",
        arguments: [100.0, 400, 1_000], [0.0, 50, 1_000, 5_000]
    )
    func matchesTheRealFlightFromMovingStarts(speed initialSpeed: Double, distance: Double) {
        for direction in 0..<8 {
            let angle = Double(direction) * .pi / 4
            let velocity = Vector2(x: initialSpeed * cos(angle), y: initialSpeed * sin(angle))
            let state = AutopilotTests.moving(velocity, to: Vector2(x: distance, y: 0))
            expectPathIsTheRealFlight(state, "speed \(initialSpeed), direction \(direction), distance \(distance)")
        }
    }

    @Test("Passes, turn-backs and sideways corrections are in the path too (US1-2)")
    func namedMovingStarts() {
        // 006's named cases (a local list in `AutopilotTests.namedMovingStarts`, so copied here).
        let cases: [(String, Vector2, Vector2)] = [
            ("too close to stop", Vector2(x: 400, y: 0), Vector2(x: 20, y: 0)),
            ("moving away", Vector2(x: -300, y: 0), Vector2(x: 500, y: 0)),
            ("ordered to its own position", Vector2(x: 0, y: 200), .zero),
            ("moving across", Vector2(x: 0, y: 300), Vector2(x: 1_000, y: 0)),
        ]
        for (name, velocity, destination) in cases {
            expectPathIsTheRealFlight(AutopilotTests.moving(velocity, to: destination), name)
        }
    }

    @Test("An order that is already arrived when given is a one-point path (US1-4)")
    func alreadyThere() {
        let state = AutopilotTests.ordered(to: .zero)
        #expect(state.autopilot.phase == .arrived)
        let path = state.plannedPath
        #expect(path.count == 1)
        #expect(path.startTick == path.endTick)
        #expect(path.reachesArrival)
        #expect(bits(path[0]) == bits(state.ship.position))
        expectPathIsTheRealFlight(state, "already there")
    }
}

// MARK: - The real flight

/// What the real simulation does with an ordered state, flown one tick at a time.
struct RealFlight {
    /// The ship's position `k` ticks after the order, for `k = 0, 1, …` up to the last tick flown.
    var positions: [Vector2]
    /// The tick count of the first state that reports arrived; `nil` if none did within the cap.
    var arrivalTick: UInt64?
}

/// Flies `start` with `Simulation.advance(_:ticks: 1)` until the state reports arrived or
/// `PlannedPath.maxFlightTicks` ticks pass, recording the ship's position after every tick.
func realFlight(_ start: SimulationState) -> RealFlight {
    var state = start
    var flight = RealFlight(positions: [state.ship.position])
    if state.autopilot.phase == .arrived {
        flight.arrivalTick = state.tickCount
        return flight
    }
    flight.positions.reserveCapacity(PlannedPath.maxFlightTicks + 1)
    for _ in 0..<PlannedPath.maxFlightTicks {
        state = Simulation.advance(state, ticks: 1)
        flight.positions.append(state.ship.position)
        if state.autopilot.phase == .arrived {
            flight.arrivalTick = state.tickCount
            return flight
        }
    }
    return flight
}

/// Checks `state.plannedPath` against `state`'s real flight: point 0 is the ship's position at the
/// order's tick; every point but the last is, bit for bit, the real position at the tick the path
/// assigns to it; the last point and `endTick` are the first arrived state's (SC-001, SC-002).
func expectPathIsTheRealFlight(_ state: SimulationState, _ label: String) {
    let path = state.plannedPath
    let flight = realFlight(state)

    #expect(path.count >= 1 && path.count <= PlannedPath.capacity, "\(label): \(path.count) points")
    #expect(path.startTick == state.tickCount, "\(label)")
    #expect(bits(path[0]) == bits(state.ship.position), "\(label): first point")

    guard let arrivalTick = flight.arrivalTick else {
        Issue.record("\(label): the real flight did not arrive within the cap")
        return
    }
    #expect(path.reachesArrival, "\(label)")
    #expect(path.endTick == arrivalTick, "\(label): path ends at \(path.endTick), real arrival at \(arrivalTick)")

    let mismatch = (0..<(path.count - 1)).first { index in
        let ticks = index * path.spacing
        return ticks >= flight.positions.count || bits(path[index]) != bits(flight.positions[ticks])
    }
    #expect(mismatch == nil, "\(label): point \(mismatch ?? -1) at spacing \(path.spacing) is not the real flight's")
    if let last = path.last, let arrival = flight.positions.last {
        #expect(bits(last) == bits(arrival), "\(label): last point is not the arrival position")
    }
}

/// A vector's exact bits.
func bits(_ vector: Vector2) -> [UInt64] {
    [vector.x.bitPattern, vector.y.bitPattern]
}
