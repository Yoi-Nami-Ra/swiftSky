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
