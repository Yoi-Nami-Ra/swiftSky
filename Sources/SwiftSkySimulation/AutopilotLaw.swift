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

    /// The hold rule applies only while the ship is closing roughly straight at the destination: its
    /// velocity's component towards the destination is at least this fraction of its speed (about 25°).
    /// Drifting sideways, it always aims at the acceleration it needs (research R11).
    static let holdAlignment = 0.9

    /// Under the hold rule, the ship keeps its braking attitude unless the acceleration calls for braking
    /// harder than this fraction of its thrust (research R5).
    static let holdAcceleration = 0.05

    /// The velocity error is removed with this time constant, in seconds — about four ticks (research R5).
    static let responseTime = 1.0 / 15

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
        // destination, given how it is already turning (research R2).
        var flipTime = 0.0
        if distance > 0 {
            let angle = Ship.wrapped(atan2(-uy, -ux) - ship.heading)
            flipTime = Self.turnTime(angle, rate: ship.angularVelocity, limits: limits)
        }

        // Step 4: the desired speed, towards the destination — the fastest the ship can still coast
        // through its flip and brake from in the distance left, capped by the linear tail (R2, R4) — and
        // how fast that speed changes per unit of distance, for the feedforward below.
        let brakingAcceleration = Self.brakingMargin * maxThrust
        var desiredSpeed = 0.0
        var desiredSpeedSlope = 0.0
        // While arrived, the desired velocity is zero: station-keeping cancels whatever motion is left,
        // and a ship already at rest within the tolerance does not move (006 FR-009, Edge Cases).
        if !arrived, distance > 0, brakingAcceleration > 0, flipTime.isFinite {
            let stopping = 2 * distance
                / (flipTime + (flipTime * flipTime + 2 * distance / brakingAcceleration).squareRoot())
            if stopping < Self.tailGain * distance {
                desiredSpeed = stopping
                // From s·T + s²/(2a′) = d: ds/dd = 1 / (T + s/a′).
                desiredSpeedSlope = 1 / (flipTime + stopping / brakingAcceleration)
            } else {
                desiredSpeed = Self.tailGain * distance
                desiredSpeedSlope = Self.tailGain
            }
        }

        // Step 5: the velocity error, and the acceleration that removes it. Aiming at the error cancels
        // cross-track drift instead of carrying it into an orbit (006 FR-006). The feedforward term is
        // the profile's own rate of change as the ship closes; it keeps the burn direction steady while
        // the ship tracks the profile, where the error alone is tiny and its direction meaningless.
        let ex = ux * desiredSpeed - vx
        let ey = uy * desiredSpeed - vy
        let error = (ex * ex + ey * ey).squareRoot()
        let facingAgainstMotion = hx * vx + hy * vy < 0
        // At a speed of at most the settle speed the velocity has no direction, so the ship is not facing
        // against its motion: station keeping leaves up to that much velocity behind, and a re-order must
        // not start in .braking or .flipping because of it. This names the phase only; step 6's hold rule
        // still reads `facingAgainstMotion` (020, SKY-46).
        let atRest = speed <= Self.settleSpeed
        let namedAgainstMotion = facingAgainstMotion && !atRest
        if error <= Self.settleSpeed {
            return (.neutral, arrived ? .arrived : (namedAgainstMotion ? .braking : .burning))
        }
        let closingSpeed = vx * ux + vy * uy
        let feedforward = -closingSpeed * desiredSpeedSlope
        let ax = ex / Self.responseTime + ux * feedforward
        let ay = ey / Self.responseTime + uy * feedforward

        // Step 6: the target heading — the acceleration's direction, unless the hold rule applies: committed
        // to braking (facing against the motion, or already flipping or braking), closing roughly straight
        // at the destination, with no decisive call to brake and at most
        // slightly slower than desired, the ship keeps its braking attitude and coasts rather than
        // turning round or sideways (research R5). Near zero, the acceleration's direction means nothing.
        var holding = false
        let committedToBraking = facingAgainstMotion || phase == .flipping || phase == .braking
        if committedToBraking, closingSpeed > Self.holdAlignment * speed, speed > 0 {
            let forwardShortfall = (ex * vx + ey * vy) / speed
            let braking = -(ax * vx + ay * vy) / speed
            holding = forwardShortfall < Self.holdFraction * desiredSpeed
                && braking < Self.holdAcceleration * maxThrust
        }
        let targetX = holding ? -vx : ax
        let targetY = holding ? -vy : ay
        let headingError = Ship.wrapped(atan2(targetY, targetX) - ship.heading)

        // Step 7: the input. The turn asks for the fastest rate that can still stop on the target heading,
        // landing the last tick exactly; an exact half-turn is +π, so it turns counter-clockwise
        // (006 FR-012). Thrust delivers the acceleration's component along the heading, inside the cone
        // only.
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
            thrust = min(max((ax * hx + ay * hy) / maxThrust, 0), 1)
        }
        let input = ControlInput(thrust: thrust, turn: turn)

        // Step 8: the phase this tick implies (research R6).
        if arrived { return (input, .arrived) }
        if thrust > 0 { return (input, namedAgainstMotion ? .braking : .burning) }
        if abs(headingError) > Self.thrustCone {
            // Mid-burn or mid-brake, a turn is an attitude correction and keeps its phase; otherwise it is
            // a flip when it turns to face against the motion, and aligning when it does not. At rest the
            // velocity has no direction, so nothing is faced against and it is never a flip.
            guard !atRest, targetX * vx + targetY * vy < 0 else { return (input, phase == .burning ? .burning : .aligning) }
            return (input, phase == .braking ? .braking : .flipping)
        }
        return (input, namedAgainstMotion ? .braking : .burning)
    }

    /// The shortest time to turn through `angle` radians (signed, positive counter-clockwise) and end
    /// not turning, starting at `rate`, within the ship's angular limits (research R2). A ship turning
    /// away first stops; one turning towards the target so fast it cannot stop in time is credited with
    /// the time to stop. Infinite when the ship cannot turn at all and has somewhere to turn to.
    static func turnTime(_ angle: Double, rate: Double, limits: ShipLimits) -> Double {
        let maxSpeed = limits.maxAngularSpeed
        let maxAcceleration = limits.maxAngularAcceleration
        guard maxSpeed > 0, maxAcceleration > 0 else { return angle == 0 ? 0 : .infinity }
        let theta = abs(angle)
        let omega = angle < 0 ? -rate : rate
        if omega < 0 {
            let stop = -omega / maxAcceleration
            return stop + turnTime(theta + omega * omega / (2 * maxAcceleration), rate: 0, limits: limits)
        }
        if omega * omega / (2 * maxAcceleration) >= theta { return omega / maxAcceleration }
        let peak = (maxAcceleration * theta + omega * omega / 2).squareRoot()
        if peak <= maxSpeed { return (2 * peak - omega) / maxAcceleration }
        let accelerating = (maxSpeed * maxSpeed - omega * omega) / (2 * maxAcceleration)
        let decelerating = maxSpeed * maxSpeed / (2 * maxAcceleration)
        return (maxSpeed - omega) / maxAcceleration
            + (theta - accelerating - decelerating) / maxSpeed
            + maxSpeed / maxAcceleration
    }

    /// The shortest time to turn through `angle` radians from not turning to not turning (research R2,
    /// and SC-002's reference pilot).
    static func restToRestTurnTime(_ angle: Double, limits: ShipLimits) -> Double {
        turnTime(angle, rate: 0, limits: limits)
    }
}
