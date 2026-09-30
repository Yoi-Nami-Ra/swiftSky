@testable import SwiftSkySimulation

/// A state's exact bits, for "bit-for-bit" assertions (004 SC-001, SC-004, research R8).
///
/// `==` on `Double` is not enough: it treats `+0` and `−0` as equal and `NaN` as unequal to itself, so
/// it would pass two states whose bits differ and fail two whose bits are identical. Test-only code,
/// so the array is fine.
func bits(_ state: SimulationState) -> [UInt64] {
    [state.tickCount] + bits(state.ship) + bits(state.autopilot)
}

/// The autopilot's exact bits (006): the two tolerances, an order-present flag and the destination
/// (zeros when there is no order), then a phase code — 0 for none, 1…5 for aligning…arrived.
func bits(_ autopilot: Autopilot) -> [UInt64] {
    let destination = autopilot.order?.destination
    let phaseCode: UInt64 = switch autopilot.phase {
    case nil: 0
    case .aligning: 1
    case .burning: 2
    case .flipping: 3
    case .braking: 4
    case .arrived: 5
    }
    return [
        autopilot.tolerances.position.bitPattern,
        autopilot.tolerances.speed.bitPattern,
        destination == nil ? 0 : 1,
        destination?.x.bitPattern ?? 0,
        destination?.y.bitPattern ?? 0,
        phaseCode,
    ]
}

/// The ship's exact bits: position, velocity, heading, angular velocity, then the three limits.
func bits(_ ship: Ship) -> [UInt64] {
    [
        ship.position.x, ship.position.y,
        ship.velocity.x, ship.velocity.y,
        ship.heading, ship.angularVelocity,
        ship.limits.maxThrustAcceleration, ship.limits.maxAngularSpeed, ship.limits.maxAngularAcceleration,
    ].map(\.bitPattern)
}
