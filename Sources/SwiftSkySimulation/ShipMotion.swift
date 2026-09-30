// The logic layer's only import, and not a boundary break (004 research R3). The Swift standard
// library has no `cos` or `sin`; these come from the C library, which brings no Metal, UIKit, AppKit or
// SwiftUI type and no SwiftPM target dependency, so FR-010, FR-011 and FR-013 all still hold. Both are
// pure functions of their argument, so they give the same bits on every run (SC-013, 004 FR-012).
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension Ship {
    /// Advances the ship by one fixed tick under `input` — frictionless Newtonian motion, integrated
    /// with semi-implicit Euler (004 FR-008, FR-009, contracts/ship-motion.md):
    ///
    /// 1. The target rate of turn is `input.turn × maxAngularSpeed`.
    /// 2. The most the rate may change this tick is `maxAngularAcceleration × dt`.
    /// 3. The rate of turn moves toward the target by at most that much, stopping exactly on it.
    /// 4. The heading changes by the new rate of turn, and is wrapped into (−π, π].
    /// 5. Thrust, if any, changes the velocity along the new heading.
    /// 6. The position changes by the new velocity.
    ///
    /// Each rate is updated before the quantity it drives (steps 3→4 and 5→6), which is what makes it
    /// semi-implicit Euler, and rotation comes before translation, so a tick's thrust acts along the
    /// heading the ship ends that tick with (004 clarifications).
    ///
    /// Pure and allocation-free: stored `Double`s only, no clock, no shared state (004 FR-012, FR-013).
    public mutating func step(_ input: ControlInput) {
        let dt = FixedTimestep.tickDuration

        // Steps 1–3. Snapping to the target when it is within one step's reach is what makes the rate
        // arrive exactly — at the maximum, at a lowered target, at zero — with no overshoot and no
        // change of sign. It also means no separate clamp at maxAngularSpeed is needed: the target is
        // within it (turn is clamped to −1…1), and the rate never moves past the target (004 R4).
        let target = input.turn * limits.maxAngularSpeed
        let maxStep = limits.maxAngularAcceleration * dt
        let delta = target - angularVelocity
        if abs(delta) <= maxStep {
            angularVelocity = target
        } else {
            angularVelocity += delta > 0 ? maxStep : -maxStep
        }

        // Step 4. Skipped when not turning, so a still heading keeps its exact bits — even a `−0`, which
        // `−0 + 0` would turn into `+0` (SC-001).
        if angularVelocity != 0 {
            heading = Ship.wrapped(heading + angularVelocity * dt)
        }

        // Step 5. Skipped entirely when coasting, so an unthrusted ship's velocity keeps its exact bits — no
        // `v + 0 × cos θ` that could turn a `+0` into a `−0` (SC-001) — and coasting ticks cost no
        // trigonometry (004 research R4).
        if input.thrust > 0 {
            let acceleration = input.thrust * limits.maxThrustAcceleration
            velocity += Vector2(x: cos(heading), y: sin(heading)) * (acceleration * dt)
        }

        // Step 6. The new velocity drives the position: semi-implicit Euler (004 FR-009).
        position += velocity * dt
    }
}
