// The logic layer's second import, for the same reason as `ShipMotion.swift`'s (004 research R3):
// `atan2`, `cos` and `sin` come from the C library, which brings no framework type and no target
// dependency. All are pure functions of their arguments, so every run gives the same bits (006 FR-012).
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension Autopilot {
    /// The profile assumes braking at this fraction of the ship's thrust; the ship itself brakes at up to
    /// all of it, so a ship on the profile always stops short of the destination (research R3, SC-003).
    static let brakingMargin = 0.9

    /// Close in, the desired speed is capped at this many units per second per unit of distance left:
    /// an exponential settle with a 0.1 s time constant instead of `√d`'s infinite slope (research R4).
    static let tailGain = 10.0

    /// The ship thrusts only when its heading is within this many radians of the burn direction
    /// (research R5).
    static let thrustCone = 0.1

    /// A ship already braking is not turned round to speed up unless it is short of the desired speed by
    /// at least this fraction of it (research R5, the hold rule).
    static let holdFraction = 0.5

    /// Below this velocity error, in units per second, the input is neutral: no thrust, and a turn input
    /// of zero, which stops any spin exactly (research R5, 006 FR-009).
    static let settleSpeed = 0.001

    /// This tick's input for `ship`, recording the phase it implies (006 FR-004, FR-005,
    /// contracts/autopilot.md). Neutral, with no phase, when there is no order.
    public mutating func control(for ship: Ship) -> ControlInput {
        guard order != nil else { return .neutral }
        let (input, phase) = evaluate(ship)
        self.phase = phase
        return input
    }

    /// The per-tick law, steps 1–8 of contracts/autopilot.md. Pure: a function of the ship, the order,
    /// the tolerances and the previous phase only. Constant work and no allocation (006 FR-015); every
    /// division is guarded, so a finite ship always gets a finite input (006 FR-013).
    func evaluate(_ ship: Ship) -> (input: ControlInput, phase: AutopilotPhase) {
        guard let order else { return (.neutral, .arrived) }
        let dt = FixedTimestep.tickDuration
        let limits = ship.limits
        let maxThrust = limits.maxThrustAcceleration
        let maxAngularSpeed = limits.maxAngularSpeed

        // Step 1: where the destination is, and which way the ship faces.
        let rx = order.destination.x - ship.position.x
        let ry = order.destination.y - ship.position.y
        let distance = (rx * rx + ry * ry).squareRoot()
        let ux = distance > 0 ? rx / distance : 0
        let uy = distance > 0 ? ry / distance : 0
        let vx = ship.velocity.x
        let vy = ship.velocity.y
        let speed = (vx * vx + vy * vy).squareRoot()
        let hx = cos(ship.heading)
        let hy = sin(ship.heading)

        // Step 2: arrival, latched while the ship stays within the position tolerance (006 FR-009).
        let arrived = distance <= tolerances.position && (speed < tolerances.speed || phase == .arrived)

        // Step 3: how long the ship needs to turn to the braking attitude, facing away from the
        // destination (research R2).
        var flipTime = 0.0
        if distance > 0 {
            let angle = abs(Ship.wrapped(atan2(-uy, -ux) - ship.heading))
            flipTime = Self.restToRestTurnTime(angle, limits: limits)
        }

        // Step 4: the desired speed, towards the destination — the fastest the ship can still coast
        // through its flip and brake from in the distance left, capped by the linear tail (R2, R4).
        let brakingAcceleration = Self.brakingMargin * maxThrust
        var desiredSpeed = 0.0
        if distance > 0, brakingAcceleration > 0, flipTime.isFinite {
            let stopping = 2 * distance
                / (flipTime + (flipTime * flipTime + 2 * distance / brakingAcceleration).squareRoot())
            desiredSpeed = min(stopping, Self.tailGain * distance)
        }

        // Step 5: the velocity error. Everything the ship does is aimed at removing it, which is what
        // cancels cross-track drift instead of carrying it into an orbit (006 FR-006).
        let ex = ux * desiredSpeed - vx
        let ey = uy * desiredSpeed - vy
        let error = (ex * ex + ey * ey).squareRoot()
        let facingAgainstMotion = hx * vx + hy * vy < 0
        if error <= Self.settleSpeed {
            return (.neutral, arrived ? .arrived : (facingAgainstMotion ? .braking : .burning))
        }

        // Step 6: the target heading — the error's direction, unless the hold rule applies: already
        // facing against the motion, still closing, and only slightly slower than desired, the ship
        // keeps its braking attitude and coasts rather than turning round (research R5).
        var holding = false
        if facingAgainstMotion, vx * ux + vy * uy > 0 {
            let forwardShortfall = (ex * vx + ey * vy) / speed
            holding = forwardShortfall > 0 && forwardShortfall < Self.holdFraction * desiredSpeed
        }
        let targetX = holding ? -vx : ex
        let targetY = holding ? -vy : ey
        let headingError = Ship.wrapped(atan2(targetY, targetX) - ship.heading)

        // Step 7: the input. The turn asks for the fastest rate that can still stop on the target heading,
        // landing the last tick exactly; an exact half-turn is +π, so it turns counter-clockwise
        // (006 FR-012). Thrust is deadbeat along the heading, inside the cone only.
        var turn = 0.0
        if maxAngularSpeed > 0 {
            let magnitude = min(
                maxAngularSpeed,
                (2 * limits.maxAngularAcceleration * abs(headingError)).squareRoot(),
                abs(headingError) / dt
            )
            turn = (headingError < 0 ? -magnitude : magnitude) / maxAngularSpeed
        }
        var thrust = 0.0
        if !holding, abs(headingError) <= Self.thrustCone, maxThrust > 0 {
            thrust = min(max((ex * hx + ey * hy) / (maxThrust * dt), 0), 1)
        }
        let input = ControlInput(thrust: thrust, turn: turn)

        // Step 8: the phase this tick implies (research R6).
        if arrived { return (input, .arrived) }
        if thrust > 0 { return (input, facingAgainstMotion ? .braking : .burning) }
        if abs(headingError) > Self.thrustCone {
            guard targetX * vx + targetY * vy < 0 else { return (input, .aligning) }
            // Turning to face against the motion: a flip, or, mid-brake, an attitude correction.
            return (input, phase == .braking ? .braking : .flipping)
        }
        return (input, facingAgainstMotion ? .braking : .burning)
    }

    /// The shortest time to turn through `angle` radians from not turning to not turning, within the
    /// ship's angular limits (research R2): accelerate, perhaps cruise at the maximum rate, decelerate.
    /// Infinite when the ship cannot turn at all.
    static func restToRestTurnTime(_ angle: Double, limits: ShipLimits) -> Double {
        guard angle > 0 else { return 0 }
        let maxSpeed = limits.maxAngularSpeed
        let maxAcceleration = limits.maxAngularAcceleration
        guard maxSpeed > 0, maxAcceleration > 0 else { return .infinity }
        if angle <= maxSpeed * maxSpeed / maxAcceleration {
            return 2 * (angle / maxAcceleration).squareRoot()
        }
        return angle / maxSpeed + maxSpeed / maxAcceleration
    }
}
