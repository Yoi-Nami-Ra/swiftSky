@testable import SwiftSkySimulation

/// A state's exact bits, for "bit-for-bit" assertions (004 SC-001, SC-004, research R8).
///
/// `==` on `Double` is not enough: it treats `+0` and `−0` as equal and `NaN` as unequal to itself, so
/// it would pass two states whose bits differ and fail two whose bits are identical. Test-only code,
/// so the array is fine.
func bits(_ state: SimulationState) -> [UInt64] {
    [state.tickCount] + bits(state.ship)
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
