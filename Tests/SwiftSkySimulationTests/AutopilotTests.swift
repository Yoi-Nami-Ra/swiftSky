import Foundation
import Testing

@testable import SwiftSkySimulation

/// The autopilot (006). Like the rest of the logic layer's tests, these need no clock, no GPU and no app:
/// the autopilot is a value in the state, advanced by a pure function (006 FR-017).
///
/// Exactness is asserted with `bits(_:)`, never `==`, wherever the spec says "bit-for-bit".
@Suite("Autopilot")
struct AutopilotTests {
    static let dt = FixedTimestep.tickDuration

    /// A launch ship ordered to `destination`.
    static func ordered(to destination: Vector2, ship: Ship = Ship()) -> SimulationState {
        var state = SimulationState(tickCount: 0, ship: ship)
        state.setOrder(to: destination)
        return state
    }

    static func distance(_ state: SimulationState) -> Double {
        state.distanceRemaining ?? .nan
    }

    static let rank: [AutopilotPhase: Int] = [.aligning: 0, .burning: 1, .flipping: 2, .braking: 3, .arrived: 4]

    // MARK: - US1: from rest

    static let restDistances: [Double] = [0.5, 10, 100, 1_000, 10_000]

    @Test(
        "From rest, every order in the grid arrives within tolerance, on time, without overshoot (SC-001–SC-003)",
        arguments: restDistances, 0..<16
    )
    func arrivesFromRest(distance: Double, direction: Int) throws {
        let angle = Double(direction) * .pi / 8
        let destination = Vector2(x: distance * cos(angle), y: distance * sin(angle))
        let flight = fly(Self.ordered(to: destination), maxTicks: 3_600)

        // SC-001
        let ticks = try #require(flight.ticksToArrival)
        #expect(Self.distance(flight.final) <= 1)
        #expect(speed(flight.final.ship) < 1)

        // SC-002
        let reference = referenceTime(distance: distance, angle: abs(Ship.wrapped(angle)), limits: .default)
        #expect(Double(ticks) * Self.dt <= 1.1 * reference + 0.5, "took \(Double(ticks) * Self.dt) s, reference \(reference) s")

        // SC-003
        #expect(flight.maxOvershoot <= 1)

        // FR-007: the flip starts before halfway.
        if let flipStart = flight.flipStartDistance {
            #expect(flipStart < distance / 2)
        }

        // FR-005: from rest the phases only move forward, each at most once.
        let ranks = flight.phases.map { Self.rank[$0]! }
        #expect(ranks == ranks.sorted() && Set(ranks).count == ranks.count, "\(flight.phases)")
    }

    @Test("From rest facing the destination: burn, flip, brake, arrive; facing away it aligns first (FR-005)")
    func phaseSequenceFromRest() {
        let ahead = fly(Self.ordered(to: Vector2(x: 1_000, y: 0)), maxTicks: 3_600)
        #expect(ahead.phases == [.burning, .flipping, .braking, .arrived])

        let behind = fly(Self.ordered(to: Vector2(x: -1_000, y: 0)), maxTicks: 3_600)
        #expect(behind.phases == [.aligning, .burning, .flipping, .braking, .arrived])
    }

    @Test(
        "After arrival the ship keeps station for 10,000 ticks, stops spinning, and returns if pushed out (SC-008, FR-009)",
        arguments: [Vector2(x: 1_000, y: 0), Vector2(x: 10 * cos(Double.pi / 4), y: 10 * sin(Double.pi / 4))]
    )
    func keepsStation(destination: Vector2) throws {
        let flight = fly(Self.ordered(to: destination), maxTicks: 3_600)
        _ = try #require(flight.ticksToArrival)

        var state = flight.final
        for _ in 0..<10_000 {
            state = Simulation.advance(state, ticks: 1)
            #expect(state.autopilot.phase == .arrived)
            #expect(Self.distance(state) <= 1)
            if state.autopilot.phase != .arrived || Self.distance(state) > 1 { return }
        }
        #expect(speed(state.ship) < 0.01)
        #expect(state.ship.angularVelocity == 0)

        // Nudged out of the position tolerance, the manoeuvre resumes and completes again.
        state = Simulation.advance(state, ticks: 30, input: ControlInput(thrust: 1, turn: 0))
        #expect(Self.distance(state) > 1)
        state = Simulation.advance(state, ticks: 1)
        #expect(state.autopilot.phase != .arrived)
        let back = fly(state, maxTicks: 3_600)
        #expect(back.ticksToArrival != nil)
        #expect(Self.distance(back.final) <= 1)
    }

    // MARK: - US2: moving starts

    /// A ship at the origin facing heading 0 and moving at `velocity`, ordered to `destination`.
    static func moving(_ velocity: Vector2, to destination: Vector2) -> SimulationState {
        ordered(to: destination, ship: Ship(position: .zero, velocity: velocity, heading: 0, angularVelocity: 0))
    }

    @Test(
        "From moving starts, every order arrives within 60 s without orbiting or ringing (SC-004)",
        arguments: [100.0, 400, 1_000], [0.0, 50, 1_000, 5_000]
    )
    func arrivesFromMovingStarts(speed initialSpeed: Double, distance: Double) {
        for direction in 0..<8 {
            let angle = Double(direction) * .pi / 4
            let velocity = Vector2(x: initialSpeed * cos(angle), y: initialSpeed * sin(angle))
            let flight = fly(Self.moving(velocity, to: Vector2(x: distance, y: 0)), maxTicks: 3_600)
            let label = "speed \(initialSpeed), direction \(direction), distance \(distance)"

            #expect(flight.ticksToArrival != nil, "\(label): did not arrive")
            #expect(Self.distance(flight.final) <= 1, "\(label)")
            #expect(speed(flight.final.ship) < 1, "\(label)")
            #expect(abs(flight.bearingSweep) < 2 * .pi, "\(label): swept \(flight.bearingSweep)")
            #expect(flight.passes <= 2, "\(label): \(flight.passes) passes")
        }
    }

    @Test("Named moving starts: too close to stop, moving away, ordered to its own position, moving across (US2)")
    func namedMovingStarts() {
        let cases: [(String, Vector2, Vector2)] = [
            ("too close to stop", Vector2(x: 400, y: 0), Vector2(x: 20, y: 0)),
            ("moving away", Vector2(x: -300, y: 0), Vector2(x: 500, y: 0)),
            ("ordered to its own position", Vector2(x: 0, y: 200), .zero),
            ("moving across", Vector2(x: 0, y: 300), Vector2(x: 1_000, y: 0)),
        ]
        for (name, velocity, destination) in cases {
            let flight = fly(Self.moving(velocity, to: destination), maxTicks: 3_600)
            #expect(flight.ticksToArrival != nil, "\(name)")
            #expect(Self.distance(flight.final) <= 1, "\(name)")
            #expect(speed(flight.final.ship) < 1, "\(name)")
        }
        // Too close to stop: it passes the destination, then comes back — at most once more.
        let tooClose = fly(Self.moving(Vector2(x: 400, y: 0), to: Vector2(x: 20, y: 0)), maxTicks: 3_600)
        #expect(tooClose.passes >= 1 && tooClose.passes <= 2)
    }

    // MARK: - US3: re-orders

    /// Flies `state` one tick at a time until its phase is `phase`, or `nil` within `maxTicks`.
    static func advance(_ state: SimulationState, until phase: AutopilotPhase, maxTicks: Int = 3_600) -> SimulationState? {
        var state = state
        for _ in 0..<maxTicks {
            if state.autopilot.phase == phase { return state }
            state = Simulation.advance(state, ticks: 1)
        }
        return state.autopilot.phase == phase ? state : nil
    }

    @Test(
        "A new order in any phase replaces the old at once, and the ship arrives at the new one (SC-006)",
        arguments: [AutopilotPhase.aligning, .burning, .flipping, .braking, .arrived]
    )
    func reorderInAnyPhase(phase: AutopilotPhase) throws {
        // Facing away from the first destination, so the flight starts by aligning.
        let first = Self.ordered(to: Vector2(x: -1_000, y: 0))
        var state = try #require(Self.advance(first, until: phase))
        let second = Vector2(x: state.ship.position.x, y: state.ship.position.y + 2_000)
        let accepted = state.setOrder(to: second)
        #expect(accepted)
        #expect(state.autopilot.order?.destination == second)

        // No dependence on the old destination: the same ship given only the new order ticks identically.
        var fresh = SimulationState(tickCount: state.tickCount, ship: state.ship)
        fresh.setOrder(to: second)
        #expect(bits(Simulation.advance(state, ticks: 1)) == bits(Simulation.advance(fresh, ticks: 1)))

        let flight = fly(state, maxTicks: 3_600)
        #expect(flight.ticksToArrival != nil)
        #expect(Self.distance(flight.final) <= 1)
        #expect(speed(flight.final.ship) < 1)
    }

    @Test("Re-ordering to the same destination carries on; a non-finite order is refused (US3-3, FR-002)")
    func sameDestinationAndRefusal() throws {
        let destination = Vector2(x: 800, y: 300)
        var state = try #require(Self.advance(Self.ordered(to: destination), until: .flipping))
        let accepted = state.setOrder(to: destination)
        #expect(accepted)
        let flight = fly(state, maxTicks: 3_600)
        #expect(flight.ticksToArrival != nil)
        #expect(Self.distance(flight.final) <= 1)

        for bad in [Vector2(x: .nan, y: 0), Vector2(x: 0, y: .infinity), Vector2(x: -.infinity, y: .nan)] {
            let before = bits(state)
            let refused = !state.setOrder(to: bad)
            #expect(refused)
            #expect(bits(state) == before)
        }
        #expect(MoveOrder(destination: Vector2(x: .nan, y: 1)) == nil)
    }

    // MARK: - US4: read-out and edges

    @Test("With no order the state reports nothing and the ship gets the neutral input (US4-1, FR-011)")
    func noOrder() {
        let state = SimulationState()
        #expect(state.autopilot.order == nil)
        #expect(state.autopilot.phase == nil)
        #expect(state.distanceRemaining == nil)
        let moving = SimulationState(
            tickCount: 0,
            ship: Ship(position: Vector2(x: 3, y: 4), velocity: Vector2(x: -20, y: 7), heading: 1, angularVelocity: 0.5)
        )
        for start in [state, moving] {
            #expect(bits(Simulation.advance(start, ticks: 600)) == bits(Simulation.advance(start, ticks: 600, input: .neutral)))
        }
    }

    @Test("An order is readable at once, and order and phase appear and vanish together (US4-3, FR-003)")
    func readOut() {
        var state = SimulationState()
        state.setOrder(to: Vector2(x: 300, y: 400))
        #expect(state.autopilot.phase != nil)
        #expect(state.distanceRemaining == 500)
        for _ in 0..<600 {
            state = Simulation.advance(state, ticks: 1)
            #expect((state.autopilot.order == nil) == (state.autopilot.phase == nil))
        }
    }

    @Test("Already there: an order within both tolerances is arrived at once, and the ship does not move")
    func alreadyThere() {
        var state = Self.ordered(to: Vector2(x: 0.5, y: -0.25))
        #expect(state.autopilot.phase == .arrived)
        let before = bits(state.ship)
        state = Simulation.advance(state, ticks: 60)
        #expect(bits(state.ship) == before)
        #expect(state.autopilot.phase == .arrived)
    }

    @Test(
        "Zero limits keep every value finite and the order in progress (FR-013)",
        arguments: [
            ShipLimits(maxThrustAcceleration: 0, maxAngularSpeed: .pi, maxAngularAcceleration: 2 * .pi),
            ShipLimits(maxThrustAcceleration: 200, maxAngularSpeed: 0, maxAngularAcceleration: 0),
            ShipLimits(maxThrustAcceleration: 0, maxAngularSpeed: 0, maxAngularAcceleration: 0),
        ]
    )
    func zeroLimits(limits: ShipLimits) {
        let ship = Ship(position: .zero, velocity: Vector2(x: 0, y: 50), heading: 2, angularVelocity: 0, limits: limits)
        var state = Self.ordered(to: Vector2(x: 1_000, y: 0), ship: ship)
        for _ in 0..<3_600 {
            state = Simulation.advance(state, ticks: 1)
        }
        let values = [
            state.ship.position.x, state.ship.position.y, state.ship.velocity.x, state.ship.velocity.y,
            state.ship.heading, state.ship.angularVelocity,
        ]
        let allFinite = values.allSatisfy(\.isFinite)
        #expect(allFinite)
        #expect(state.autopilot.phase != .arrived)
    }

    @Test("A destination a million units away is reached within tolerance")
    func farDestination() {
        let flight = fly(Self.ordered(to: Vector2(x: 1_000_000, y: -1_000_000)), maxTicks: 30_000)
        #expect(flight.ticksToArrival != nil)
        #expect(Self.distance(flight.final) <= 1)
        #expect(speed(flight.final.ship) < 1)
    }

    @Test("Exactly behind, the ship turns counter-clockwise (FR-012)")
    func exactlyBehindTurnsCounterClockwise() {
        let state = Simulation.advance(Self.ordered(to: Vector2(x: -1_000, y: 0)), ticks: 1)
        #expect(state.ship.angularVelocity > 0)
    }

    @Test("Tolerances are sanitised, default to 1 and 1, and looser ones arrive looser and no later (FR-010)")
    func tolerances() {
        #expect(ArrivalTolerances(position: -1, speed: .nan) == ArrivalTolerances(position: 0, speed: 0))
        #expect(ArrivalTolerances.default == ArrivalTolerances(position: 1, speed: 1))
        #expect(Autopilot().tolerances == .default)

        let destination = Vector2(x: 600, y: 250)
        let tight = fly(Self.ordered(to: destination), maxTicks: 3_600)
        var loose = SimulationState()
        loose.autopilot = Autopilot(tolerances: ArrivalTolerances(position: 5, speed: 5))
        loose.setOrder(to: destination)
        let looseFlight = fly(loose, maxTicks: 3_600)

        #expect(looseFlight.ticksToArrival != nil)
        #expect(Self.distance(looseFlight.final) <= 5)
        #expect(speed(looseFlight.final.ship) < 5)
        #expect((looseFlight.ticksToArrival ?? .max) <= (tight.ticksToArrival ?? 0))
    }
}

// MARK: - Flight recording

/// What happened on one flight, for the arrival, overshoot and orbit criteria (SC-001–SC-004).
struct Flight {
    /// Ticks until the phase first became `.arrived`; `nil` if it never did within the cap.
    var ticksToArrival: Int?
    /// The phase of every tick, consecutive duplicates collapsed.
    var phases: [AutopilotPhase] = []
    /// Straight-line distance from the start when the first flip began; `nil` if there was none.
    var flipStartDistance: Double?
    /// The furthest the ship got beyond the destination along the reference direction (SC-003).
    var maxOvershoot = -Double.infinity
    /// Accumulated signed bearing of the ship around the destination, in radians (SC-004).
    var bearingSweep = 0.0
    /// How many times the ship crossed the destination along the reference direction (SC-004).
    var passes = 0
    /// The state when the flight stopped.
    var final: SimulationState
}

/// Flies `start` one tick at a time with the autopilot until it arrives or `maxTicks` pass.
///
/// Overshoot and passes are measured along the unit vector from the start to the destination, or, when
/// they coincide, along the initial velocity; with neither, they are not measured. The bearing sweep only
/// counts ticks on which the ship is more than 5 units from the destination at both ends, so a pass
/// straight through the destination (a π jump in bearing over one tick) does not read as half an orbit.
func fly(_ start: SimulationState, maxTicks: Int) -> Flight {
    guard let destination = start.autopilot.order?.destination else {
        return Flight(final: start)
    }
    var flight = Flight(final: start)
    let origin = start.ship.position
    var ux = destination.x - origin.x
    var uy = destination.y - origin.y
    var length = (ux * ux + uy * uy).squareRoot()
    if length == 0 {
        ux = start.ship.velocity.x
        uy = start.ship.velocity.y
        length = (ux * ux + uy * uy).squareRoot()
    }
    let measured = length > 0
    if measured {
        ux /= length
        uy /= length
    }

    func along(_ state: SimulationState) -> Double {
        (state.ship.position.x - destination.x) * ux + (state.ship.position.y - destination.y) * uy
    }
    func offset(_ state: SimulationState) -> (distance: Double, bearing: Double) {
        let dx = state.ship.position.x - destination.x
        let dy = state.ship.position.y - destination.y
        return ((dx * dx + dy * dy).squareRoot(), atan2(dy, dx))
    }

    var state = start
    var lastSign = measured ? along(state).sign : .plus
    var signKnown = measured && along(state) != 0
    if let phase = state.autopilot.phase { flight.phases.append(phase) }

    for tick in 1...maxTicks {
        let before = offset(state)
        state = Simulation.advance(state, ticks: 1)
        let after = offset(state)
        guard let phase = state.autopilot.phase else { break }

        if flight.phases.last != phase { flight.phases.append(phase) }
        if phase == .flipping, flight.flipStartDistance == nil {
            let dx = state.ship.position.x - origin.x
            let dy = state.ship.position.y - origin.y
            flight.flipStartDistance = (dx * dx + dy * dy).squareRoot()
        }
        if measured {
            let s = along(state)
            flight.maxOvershoot = max(flight.maxOvershoot, s)
            if s != 0 {
                if signKnown, s.sign != lastSign { flight.passes += 1 }
                lastSign = s.sign
                signKnown = true
            }
        }
        if before.distance > 5, after.distance > 5 {
            var delta = after.bearing - before.bearing
            if delta > .pi { delta -= 2 * .pi }
            if delta <= -.pi { delta += 2 * .pi }
            flight.bearingSweep += delta
        }
        if phase == .arrived {
            flight.ticksToArrival = tick
            break
        }
    }
    flight.final = state
    return flight
}

/// SC-002's ideal pilot: turn in place through `angle` to face the destination, burn at full thrust,
/// flip 180° while coasting, brake at full thrust to stop exactly on the destination. All turns
/// rest-to-rest at the ship's angular limits.
func referenceTime(distance: Double, angle: Double, limits: ShipLimits) -> Double {
    let a = limits.maxThrustAcceleration
    let flip = Autopilot.restToRestTurnTime(.pi, limits: limits)
    // Burn t1, coast `flip`, brake t1: distance = a·t1² + a·t1·flip.
    let t1 = (-flip + (flip * flip + 4 * distance / a).squareRoot()) / 2
    return Autopilot.restToRestTurnTime(angle, limits: limits) + 2 * t1 + flip
}

func speed(_ ship: Ship) -> Double {
    (ship.velocity.x * ship.velocity.x + ship.velocity.y * ship.velocity.y).squareRoot()
}
