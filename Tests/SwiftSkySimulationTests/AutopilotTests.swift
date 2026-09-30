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
