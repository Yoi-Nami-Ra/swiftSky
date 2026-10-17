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
}
