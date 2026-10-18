import Foundation
import Testing

@testable import SwiftSkySimulation

/// A re-order from rest or station keeping (SKY-46, spec 020). The law's flight is pinned bit for bit before
/// the fix, and the phase the re-order starts in is asserted after it.
///
/// Exactness is asserted with `bits(_:)` and `bitPattern`, never `==`, wherever the spec says "bit-for-bit".
@Suite("Autopilot from rest (020)")
struct AutopilotRestPhaseTests {
    /// A ship that has flown to (1,000, 0), arrived, and then kept station for 600 more ticks (research R4).
    static func stationKept() -> SimulationState {
        var state = SimulationState(tickCount: 0, ship: Ship())
        state.setOrder(to: Vector2(x: 1_000, y: 0))
        state = fly(state, maxTicks: 3_600).final
        var tick = 0
        while tick < 600 {
            state = Simulation.advance(state, ticks: 1)
            tick += 1
        }
        return state
    }

    /// `state` with a new order to the point 1,000 units from the ship, in the direction of its velocity
    /// turned by `offset` radians. `.pi` is straight behind; `2 * .pi / 3` is 120 degrees off.
    static func reorder(_ state: SimulationState, turnedBy offset: Double) -> SimulationState {
        let velocity = state.ship.velocity
        let angle = atan2(velocity.y, velocity.x) + offset
        var ordered = state
        ordered.setOrder(
            to: Vector2(
                x: state.ship.position.x + 1_000 * cos(angle),
                y: state.ship.position.y + 1_000 * sin(angle)))
        return ordered
    }

    @Test("Station keeping leaves a leftover velocity below the settle speed (FR-005 setup)")
    func stationKeepingLeftover() {
        let state = Self.stationKept()
        #expect(state.autopilot.phase == .arrived)
        let current = speed(state.ship)
        #expect(current > 0 && current <= Autopilot.settleSpeed, "speed \(current)")
        #expect(
            state.ship.velocity.x.bitPattern == 0x3f50_578f_7e85_aca9
                && state.ship.velocity.y.bitPattern == 0xbf04_3c4d_bd8f_d4fa)
    }

    /// FNV-1a 64 over every tick's control input and resulting ship bits, until the first tick whose phase is
    /// `.arrived` (research R3). The phase itself is never hashed: it is the one thing the fix may change.
    static func fingerprint(_ start: SimulationState, maxTicks: Int) -> (fingerprint: UInt64, ticks: Int) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func fold(_ value: UInt64) { hash = (hash ^ value) &* 0x100_0000_01b3 }
        var state = start
        var ticks = 0
        while ticks < maxTicks {
            var probe = state.autopilot
            let input = probe.control(for: state.ship)
            state = Simulation.advance(state, ticks: 1)
            ticks += 1
            fold(input.thrust.bitPattern)
            fold(input.turn.bitPattern)
            for word in bits(state.ship) { fold(word) }
            if state.autopilot.phase == .arrived { break }
        }
        return (hash, ticks)
    }

    // Recorded from the law as it was BEFORE the 020 fix. They must never be edited to make the test pass
    // (spec FR-004): a failure here means the fix changed the inputs, and the fix is wrong.
    static let reorderFingerprints: [Double: (fingerprint: UInt64, ticks: Int)] = [
        .pi: (0x4e5a_c65f_1bad_fcc0, 341),
        2 * .pi / 3: (0x60fc_6859_ea22_29a8, 369),
    ]

    @Test(
        "A re-order from station keeping flies bit-identical inputs and states (FR-007, SC-002)",
        arguments: [Double.pi, 2 * Double.pi / 3])
    func reorderFlightIsBitIdentical(offset: Double) {
        let ordered = Self.reorder(Self.stationKept(), turnedBy: offset)
        let result = Self.fingerprint(ordered, maxTicks: 3_600)
        let expected = Self.reorderFingerprints[offset]!
        #expect(
            result.fingerprint == expected.fingerprint && result.ticks == expected.ticks,
            "fingerprint 0x\(String(result.fingerprint, radix: 16)) ticks \(result.ticks)")
    }

    private func expectForwardOnly(_ phases: [AutopilotPhase]) {
        let ranks = phases.map { AutopilotTests.rank[$0]! }
        #expect(ranks == ranks.sorted() && Set(ranks).count == ranks.count, "\(phases)")
    }

    @Test("A re-order at 120° from the leftover velocity starts aligning and only moves forward (FR-005, FR-006)")
    func reorderAt120DegreesStartsAligning() {
        let flight = fly(Self.reorder(Self.stationKept(), turnedBy: 2 * .pi / 3), maxTicks: 3_600)
        #expect(flight.phases == [.aligning, .burning, .flipping, .braking, .arrived], "\(flight.phases)")
        expectForwardOnly(flight.phases)
    }

    @Test("A re-order straight behind the leftover velocity starts burning (scenario 3, FR-006)")
    func reorderStraightBehindStartsBurning() {
        let flight = fly(Self.reorder(Self.stationKept(), turnedBy: .pi), maxTicks: 3_600)
        #expect(flight.phases == [.burning, .flipping, .braking, .arrived], "\(flight.phases)")
        expectForwardOnly(flight.phases)
    }

    /// One evaluation of a ship at rest: the order is set, the previous phase replaced by `previous`, and the
    /// law run once. Reaching the settled, coasting and hold rules at rest needs tolerances tighter than the
    /// defaults; the states were found by sampling rest states (review of PR 3).
    static func evaluate(
        velocity: Vector2, heading: Double, angularVelocity: Double, destination: Vector2,
        tolerances: ArrivalTolerances, previous: AutopilotPhase? = nil
    ) -> (input: ControlInput, phase: AutopilotPhase?) {
        let ship = Ship(position: .zero, velocity: velocity, heading: heading, angularVelocity: angularVelocity)
        var autopilot = Autopilot(tolerances: tolerances)
        autopilot.setOrder(MoveOrder(destination: destination)!, for: ship)
        if let previous { autopilot.phase = previous }
        let input = autopilot.control(for: ship)
        return (input, autopilot.phase)
    }

    static func polar(_ length: Double, _ angle: Double) -> Vector2 {
        Vector2(x: length * cos(angle), y: length * sin(angle))
    }

    @Test("The settled return names a ship at rest burning, not braking (FR-003)")
    func settledReturnAtRestIsBurning() {
        // Facing against a velocity of half the settle speed, ordered to where it is: the error is within the
        // settle speed, so the input is neutral, and with zero tolerances it has not arrived.
        let result = Self.evaluate(
            velocity: Vector2(x: -0.0005, y: 0), heading: 0, angularVelocity: 0, destination: .zero,
            tolerances: ArrivalTolerances(position: 0, speed: 0))
        #expect(result.input.thrust.bitPattern == 0 && result.input.turn.bitPattern == 0)
        #expect(result.phase == .burning)
    }

    @Test("The coasting rule names a ship at rest burning, even after braking (FR-002, FR-003)")
    func coastingAtRestIsBurning() {
        let result = Self.evaluate(
            velocity: Self.polar(0.0009490693130516976, 4.069874449992827), heading: 0.8508375501921908,
            angularVelocity: -0.7692800063991303,
            destination: Self.polar(0.0013037368578249688, 4.429180250849325),
            tolerances: ArrivalTolerances(position: 0, speed: 0), previous: .braking)
        #expect(result.input.thrust.bitPattern == 0)
        #expect(result.phase == .burning)
    }

    @Test("The hold rule still reads the raw velocity direction at rest (FR-004, contract step 6)")
    func holdRuleReadsRawDirection() {
        // Facing against its motion at rest and closing on a destination inside the hold rule's reach: the
        // raw test commits it to braking, so it holds and turns to face against the velocity (+1). Read
        // through the rest rule, it would turn the other way (−1).
        let result = Self.evaluate(
            velocity: Self.polar(0.0009206945536779856, 1.3930853137224208), heading: -3.092044748158288,
            angularVelocity: -0.04705009884062106,
            destination: Self.polar(0.0014877396441076868, 1.0055581949092154),
            tolerances: ArrivalTolerances(position: 1e-4, speed: 1e-4), previous: .aligning)
        #expect(result.input.thrust.bitPattern == 0)
        #expect(result.input.turn == 1)
    }

    @Test("After explicit-input ticks, a phase named from rest can change a later input (FR-004 exception)")
    func explicitInputInterludeKeepsBurning() {
        // An order given at rest facing against a slight drift used to be named braking. Thrust given
        // explicitly then carries the ship to 200 u/s towards the destination with the phase unchanged, and
        // the stale braking engaged the hold rule: thrust 0, turn +1. Named burning, it flies on at full thrust.
        var state = SimulationState(
            tickCount: 0,
            ship: Ship(position: .zero, velocity: Vector2(x: -0.0005, y: 0), heading: 0, angularVelocity: 0))
        state.setOrder(to: Vector2(x: 1_000, y: 0))
        #expect(state.autopilot.phase == .burning)
        state = Simulation.advance(state, ticks: 60, input: ControlInput(thrust: 1, turn: 0))
        var autopilot = state.autopilot
        let input = autopilot.control(for: state.ship)
        #expect(input.thrust == 1 && input.turn.bitPattern == 0)
        #expect(autopilot.phase == .burning)
    }

    @Test("The rest boundary is the settle speed, inclusive (FR-005a)")
    func restBoundaryIsSettleSpeed() {
        func firstPhase(speed s: Double) -> AutopilotPhase? {
            var state = SimulationState(
                tickCount: 0,
                ship: Ship(position: .zero, velocity: Vector2(x: s, y: 0), heading: .pi, angularVelocity: 0))
            let angle = 2 * Double.pi / 3
            state.setOrder(to: Vector2(x: 1_000 * cos(angle), y: 1_000 * sin(angle)))
            _ = state.autopilot.control(for: state.ship)
            return state.autopilot.phase
        }
        #expect(firstPhase(speed: Autopilot.settleSpeed) == .aligning)
        #expect(firstPhase(speed: Autopilot.settleSpeed.nextUp) == .flipping)
    }
}
