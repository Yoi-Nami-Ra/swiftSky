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

    // MARK: - US2: long and endless flights

    @Test("Every flight length from 0 to 3,700 ticks fits in 256 evenly spaced points, ending on the last (SC-003)")
    func thinningAtEveryLength() {
        // Each synthetic position encodes its own tick, so a point's value says which tick it kept.
        func position(_ tick: Int) -> Vector2 { Vector2(x: Double(tick), y: -Double(tick)) }
        var failures: [String] = []
        func check(_ condition: Bool, _ message: @autoclosure () -> String) {
            if !condition, failures.count < 20 { failures.append(message()) }
        }

        for ticks in 0...3_700 {
            var path = PlannedPath(start: position(0), tick: 1_000)
            for tick in stride(from: 1, through: ticks, by: 1) {
                path.append(position(tick))
            }
            path.finish(reachesArrival: true)

            let count = path.count
            let spacing = path.spacing
            check(count >= 1 && count <= PlannedPath.capacity, "\(ticks) ticks: \(count) points")
            check(path.startTick == 1_000 && path.endTick == 1_000 + UInt64(ticks), "\(ticks) ticks: ticks \(path.startTick)…\(path.endTick)")
            check(path.reachesArrival, "\(ticks) ticks: arrival flag lost")
            if ticks <= 255 {
                check(count == ticks + 1 && spacing == 1, "\(ticks) ticks: \(count) points at spacing \(spacing), expected every tick")
            } else {
                check(count >= 128, "\(ticks) ticks: only \(count) points")
            }
            check(spacing > 0 && spacing & (spacing - 1) == 0, "\(ticks) ticks: spacing \(spacing) is not a power of two")
            for index in 0..<(count - 1) where bits(path[index]) != bits(position(index * spacing)) {
                check(false, "\(ticks) ticks: point \(index) is \(path[index]), expected tick \(index * spacing)")
                break
            }
            check(path.last.map { bits($0) == bits(position(ticks)) } ?? false, "\(ticks) ticks: last point is not the final position")
            if count >= 2 {
                check(ticks > (count - 2) * spacing && ticks <= (count - 1) * spacing,
                      "\(ticks) ticks: last point's tick is not after point \(count - 2)'s and within one spacing")
            }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    @Test(
        "A flight that cannot complete stops at the cap, on the real position after 3,600 ticks (SC-004)",
        arguments: ["zero thrust", "zero angular acceleration, facing away"]
    )
    func cappedFlight(_ name: String) throws {
        let defaults = ShipLimits.default
        let ship = switch name {
        case "zero thrust":
            Ship(limits: ShipLimits(
                maxThrustAcceleration: 0,
                maxAngularSpeed: defaults.maxAngularSpeed,
                maxAngularAcceleration: defaults.maxAngularAcceleration
            ))
        default:
            Ship(
                position: .zero, velocity: .zero, heading: .pi, angularVelocity: 0,
                limits: ShipLimits(
                    maxThrustAcceleration: defaults.maxThrustAcceleration,
                    maxAngularSpeed: defaults.maxAngularSpeed,
                    maxAngularAcceleration: 0
                )
            )
        }
        let state = AutopilotTests.ordered(to: Vector2(x: 1_000, y: 0), ship: ship)
        let path = state.plannedPath
        let real = Simulation.advance(state, ticks: PlannedPath.maxFlightTicks)

        #expect(real.autopilot.phase != .arrived)
        #expect(!path.reachesArrival)
        #expect(path.endTick - path.startTick == UInt64(PlannedPath.maxFlightTicks))
        #expect(path.count == 226)
        #expect(path.spacing == 16)
        let last = try #require(path.last)
        #expect(bits(last) == bits(real.ship.position))
    }

    // MARK: - US3: planned once per order

    /// A ship part-way through an order from rest, so a re-order starts from a moving ship at a tick
    /// other than zero.
    static func midFlight() -> SimulationState {
        Simulation.advance(AutopilotTests.ordered(to: Vector2(x: 1_000, y: 0)), ticks: 120)
    }

    @Test("Advancing, with or without an explicit input, never changes the path (SC-005, FR-008)", arguments: [1, 7, 60, 333, 1_000])
    func advancingLeavesThePath(ticks: Int) {
        let state = Self.midFlight()
        let path = bits(state.plannedPath)
        #expect(bits(Simulation.advance(state, ticks: ticks).plannedPath) == path)
        #expect(bits(Simulation.advance(state, ticks: ticks, input: ControlInput(thrust: 1, turn: -0.5)).plannedPath) == path)
    }

    @Test("A new order replaces the path with its own prediction, from where the ship is now (SC-005, US3-2)")
    func reorderReplacesThePath() {
        var state = Self.midFlight()
        let old = bits(state.plannedPath)
        let destination = Vector2(x: -500, y: 300)
        state.setOrder(to: destination)
        let predicted = PlannedPath(predictingFrom: state.ship, autopilot: state.autopilot, tickCount: state.tickCount)
        #expect(bits(state.plannedPath) == bits(predicted))
        #expect(bits(state.plannedPath) != old)
        #expect(state.plannedPath.startTick == 120)
        #expect(bits(state.plannedPath[0]) == bits(state.ship.position))
        expectPathIsTheRealFlight(state, "re-ordered mid-flight")

        // The same destination again, later: predicted afresh from the ship as it is then.
        state = Simulation.advance(state, ticks: 60)
        state.setOrder(to: destination)
        #expect(state.plannedPath.startTick == 180)
        #expect(bits(state.plannedPath[0]) == bits(state.ship.position))
        expectPathIsTheRealFlight(state, "re-ordered to the same destination")
    }

    @Test("A refused order leaves the whole state, path included, unchanged (SC-005, US3-3)")
    func refusedOrderLeavesTheState() {
        var state = Self.midFlight()
        let before = bits(state)
        for destination in [Vector2(x: .nan, y: 0), Vector2(x: 0, y: .infinity), Vector2(x: -.infinity, y: .nan)] {
            let accepted = state.setOrder(to: destination)
            #expect(!accepted)
            #expect(bits(state) == before)
        }
    }

    @Test("Without an order there is no path (FR-001)")
    func noOrderNoPath() {
        let fresh = SimulationState()
        #expect(fresh.plannedPath.isEmpty)
        #expect(fresh.plannedPath.last == nil)
        #expect(bits(fresh.plannedPath) == bits(PlannedPath.empty))
        #expect(Simulation.advance(fresh, ticks: 600).plannedPath.isEmpty)
    }

    @Test("Predicting changes nothing else: ship, autopilot and tick count are as without it (FR-009)")
    func predictingChangesNothingElse() throws {
        let before = Self.midFlight()
        let destination = Vector2(x: -500, y: 300)
        var viaState = before
        viaState.setOrder(to: destination)
        var direct = before
        direct.autopilot.setOrder(try #require(MoveOrder(destination: destination)), for: direct.ship)

        #expect(bits(viaState.ship) == bits(direct.ship))
        #expect(bits(viaState.autopilot) == bits(direct.autopilot))
        #expect(viaState.tickCount == direct.tickCount)
    }

    @Test("006's ten-run determinism scenario ends with a path, so its byte-identical check covers paths (SC-006)")
    func determinismScenarioHasAPath() {
        #expect(!AutopilotTests.scenario().plannedPath.isEmpty)
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
    // The work bound (SC-004): no prediction flies more than the cap.
    #expect(path.endTick - path.startTick <= UInt64(PlannedPath.maxFlightTicks), "\(label): predicted past the cap")
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
