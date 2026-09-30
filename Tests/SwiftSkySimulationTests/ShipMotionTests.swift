import Foundation
import Testing

@testable import SwiftSkySimulation

/// The ship's motion rule (004). Like the rest of the logic layer's tests, these need no clock, no GPU
/// and no app: the ship is a value, advanced by a pure function (004 FR-015).
///
/// Exactness is asserted with `bits(_:)`, never `==`, wherever the spec says "bit-for-bit"
/// (004 research R8).
@Suite("ShipMotion")
struct ShipMotionTests {
    static let degree = Double.pi / 180
    static let dt = FixedTimestep.tickDuration
    static let fullThrust = ControlInput(thrust: 1, turn: 0)

    /// A ship mid-flight: moving, off-axis and turning, so identity cannot pass trivially.
    static let midFlight = Ship(
        position: Vector2(x: 12.5, y: -40),
        velocity: Vector2(x: 30, y: 7.25),
        heading: 1.1,
        angularVelocity: 0.4
    )

    static func speed(_ ship: Ship) -> Double {
        (ship.velocity.x * ship.velocity.x + ship.velocity.y * ship.velocity.y).squareRoot()
    }

    static func run(_ ship: Ship, ticks: Int, _ input: ControlInput) -> Ship {
        Simulation.advance(SimulationState(tickCount: 0, ship: ship), ticks: ticks, input: input).ship
    }

    // MARK: - Thrust and drift

    @Test("The launch ship is at the origin, at rest, facing heading zero, with the default limits")
    func launchShip() {
        let ship = SimulationState().ship
        #expect(ship.position == .zero)
        #expect(ship.velocity == .zero)
        #expect(ship.heading == 0)
        #expect(ship.angularVelocity == 0)
        #expect(ship.limits == .default)
        #expect(ShipLimits.default.maxThrustAcceleration == 200)
        #expect(ShipLimits.default.maxAngularSpeed == 180 * Self.degree)
        #expect(ShipLimits.default.maxAngularAcceleration == 360 * Self.degree)
    }

    @Test("A ship at rest with no input stays exactly where it is for 10,000 ticks")
    func atRestStaysPut() {
        let start = SimulationState()

        let oneCall = Simulation.advance(start, ticks: 10_000)
        #expect(bits(oneCall.ship) == bits(start.ship))

        var state = start
        for _ in 0..<10_000 {
            state = Simulation.advance(state, ticks: 1, input: .neutral)
        }
        #expect(bits(state.ship) == bits(start.ship))
        #expect(state.tickCount == 10_000)
    }

    @Test("One second of full thrust matches the constant-acceleration formulas")
    func fullThrustKinematics() {
        let ship = Self.run(Ship(), ticks: 60, Self.fullThrust)

        #expect(abs(Self.speed(ship) - 200) < 0.0001)
        // Semi-implicit Euler overshoots ½at² by one tick's travel at most (SC-002).
        #expect(abs(ship.position.x - 100) <= 3.34)
        #expect(ship.position.y == 0)
        #expect(ship.velocity.y == 0)
    }

    @Test("With the engine cut, the ship drifts at exactly its velocity")
    func coastAtConstantVelocity() {
        let thrusted = Self.run(Ship(), ticks: 60, Self.fullThrust)
        let velocity = thrusted.velocity

        var ship = thrusted
        for _ in 0..<60 {
            let before = ship.position
            ship = Self.run(ship, ticks: 1, .neutral)
            // The velocity keeps its exact bits on every coasting tick (US1-3)...
            #expect(ship.velocity.x.bitPattern == velocity.x.bitPattern)
            #expect(ship.velocity.y.bitPattern == velocity.y.bitPattern)
            // ...so each tick moves the ship by the same amount, up to the rounding of adding it to
            // a growing position.
            #expect(abs((ship.position.x - before.x) - velocity.x * Self.dt) < 1e-12)
        }

        #expect(abs((ship.position.x - thrusted.position.x) - 200) < 0.0001)
    }

    @Test("Thrust accelerates along the heading and nowhere else", arguments: [0.0, 90.0, -135.0, 180.0])
    func thrustFollowsHeading(headingDegrees: Double) {
        let heading = headingDegrees * Self.degree
        let start = Ship(position: .zero, velocity: .zero, heading: heading, angularVelocity: 0)
        let ship = Self.run(start, ticks: 1, Self.fullThrust)

        let expected = 200 * Self.dt
        #expect(abs(ship.velocity.x - cos(start.heading) * expected) < 1e-12)
        #expect(abs(ship.velocity.y - sin(start.heading) * expected) < 1e-12)
        #expect(abs(Self.speed(ship) - expected) < 1e-12)
    }

    @Test("Partial thrust gives that fraction of the maximum acceleration", arguments: [0.25, 0.5, 0.75])
    func partialThrust(thrust: Double) {
        let ship = Self.run(Ship(), ticks: 60, ControlInput(thrust: thrust, turn: 0))
        #expect(abs(Self.speed(ship) - thrust * 200) < 0.0001)
    }

    @Test("Zero and negative tick counts leave the whole state untouched", arguments: [0, -3])
    func nonPositiveTicksIsIdentity(ticks: Int) {
        let state = SimulationState(tickCount: 42, ship: Self.midFlight)
        let advanced = Simulation.advance(state, ticks: ticks, input: ControlInput(thrust: 1, turn: 1))
        #expect(bits(advanced) == bits(state))
    }
}

// MARK: - Turning

extension ShipMotionTests {
    static let fullTurn = ControlInput(thrust: 0, turn: 1)
    static let maxRate = ShipLimits.default.maxAngularSpeed

    @Test("Under a full turn the rate builds by one tick of angular acceleration, up to exactly the maximum")
    func spinUp() {
        var ship = Ship()
        var reachedAt: Int?
        for tick in 1...600 {
            let before = ship.angularVelocity
            ship = Self.run(ship, ticks: 1, Self.fullTurn)
            #expect(ship.angularVelocity <= Self.maxRate)
            if reachedAt == nil {
                if ship.angularVelocity == Self.maxRate {
                    reachedAt = tick
                } else {
                    // 360 °/s² for one tick is 6 °/s (SC-003).
                    #expect(abs((ship.angularVelocity - before) - 6 * Self.degree) < 1e-6 * Self.degree)
                }
            }
        }
        #expect(reachedAt == 30 || reachedAt == 31)
    }

    @Test("Released from full spin, the rate falls to exactly zero without changing sign, and stays there")
    func spinDown() {
        var ship = Ship(position: .zero, velocity: .zero, heading: 0, angularVelocity: Self.maxRate)
        var stoppedAt: Int?
        for tick in 1...120 {
            ship = Self.run(ship, ticks: 1, .neutral)
            #expect(ship.angularVelocity >= 0)
            if stoppedAt == nil, ship.angularVelocity == 0 { stoppedAt = tick }
            if stoppedAt != nil { #expect(ship.angularVelocity.bitPattern == 0) }
        }
        #expect(stoppedAt.map { $0 <= 31 } == true)
    }

    @Test("A turn of −1 mirrors a turn of +1 exactly")
    func mirroredTurn() {
        var left = Ship()
        var right = Ship()
        for _ in 0..<60 {
            left = Self.run(left, ticks: 1, Self.fullTurn)
            right = Self.run(right, ticks: 1, ControlInput(thrust: 0, turn: -1))
            #expect(right.angularVelocity == -left.angularVelocity)
            #expect(right.heading == -left.heading)
        }
    }

    @Test("A held partial turn settles at exactly that fraction of the maximum rate")
    func partialTurn() {
        let ship = Self.run(Ship(), ticks: 60, ControlInput(thrust: 0, turn: 0.5))
        #expect(ship.angularVelocity == 0.5 * Self.maxRate)
    }

    @Test("Lowering the turn from full brings the rate down to exactly the new target, never below")
    func loweredTarget() {
        var ship = Ship(position: .zero, velocity: .zero, heading: 0, angularVelocity: Self.maxRate)
        let target = 0.25 * Self.maxRate
        for _ in 0..<60 {
            ship = Self.run(ship, ticks: 1, ControlInput(thrust: 0, turn: 0.25))
            #expect(ship.angularVelocity >= target)
        }
        #expect(ship.angularVelocity == target)
    }

    @Test("The heading stays within (−180°, 180°] however long the ship turns", arguments: [1.0, -1.0])
    func headingStaysInRange(turn: Double) {
        var ship = Ship()
        for _ in 0..<6_000 {
            ship = Self.run(ship, ticks: 1, ControlInput(thrust: 0, turn: turn))
            #expect(ship.heading > -.pi && ship.heading <= .pi)
        }
    }

    @Test("Wrapping maps any heading into (−π, π], −π to π, and non-finite to zero")
    func wrapping() {
        let values: [Double] = [.pi, -.pi, 3 * .pi, -3 * .pi + 0.1, 100, -100, 1e9]
        for value in values {
            let wrapped = Ship.wrapped(value)
            #expect(wrapped > -.pi && wrapped <= .pi)
            // Same direction: the wrap removes whole turns only.
            #expect(abs(cos(wrapped) - cos(value)) < 1e-6)
            #expect(abs(sin(wrapped) - sin(value)) < 1e-6)
        }
        #expect(Ship.wrapped(-.pi) == .pi)
        #expect(Ship.wrapped(0.5).bitPattern == 0.5.bitPattern)
        #expect(Ship.wrapped(.nan) == 0)
        #expect(Ship.wrapped(.infinity) == 0)
    }

    @Test("A tick's thrust acts along the heading after that tick's rotation")
    func thrustAfterRotation() {
        let ship = Self.run(Ship(), ticks: 1, ControlInput(thrust: 1, turn: 1))
        #expect(ship.heading > 0)
        #expect(abs(atan2(ship.velocity.y, ship.velocity.x) - ship.heading) < 1e-12)
    }
}

// MARK: - Determinism (SC-004)

extension ShipMotionTests {
    /// Thrusts, turns both ways, holds a partial turn, coasts and brakes, in advances of one to four
    /// ticks — the frame loop's catch-up range. 640 ticks in all.
    static let script: [(ticks: Int, input: ControlInput)] = {
        let moves: [(Int, ControlInput)] = [
            (1, ControlInput(thrust: 1, turn: 0)),
            (4, ControlInput(thrust: 1, turn: 1)),
            (2, ControlInput(thrust: 0.5, turn: -1)),
            (3, .neutral),
            (4, ControlInput(thrust: 0, turn: 0.3)),
            (1, ControlInput(thrust: 0.75, turn: -0.6)),
            (2, ControlInput(thrust: 1, turn: 0)),
            (3, ControlInput(thrust: 0.2, turn: 1)),
        ]
        // The eight moves are twenty ticks; twenty passes of them, then 240 ticks of coasting in a
        // full clockwise turn.
        var script = (0..<20).flatMap { _ in moves }.map { (ticks: $0.0, input: $0.1) }
        script.append((ticks: 240, input: ControlInput(thrust: 0, turn: -1)))
        return script
    }()

    @Test("Ten runs of the same varied script end in byte-identical states")
    func tenRunsAreByteIdentical() {
        func run() -> SimulationState {
            Self.script.reduce(SimulationState()) { Simulation.advance($0, ticks: $1.ticks, input: $1.input) }
        }

        let reference = run()
        for _ in 0..<10 {
            #expect(bits(run()) == bits(reference))
        }

        // Sanity: the script really moved and turned the ship, so identity cannot pass trivially.
        #expect(reference.tickCount == 640)
        #expect(Self.speed(reference.ship) > 1)
        #expect(reference.ship.position != .zero)
        #expect(reference.ship.heading != 0)
        #expect(reference.ship.angularVelocity == -Self.maxRate)
    }

    @Test("Advancing n ticks at once is byte-identical to n single ticks", arguments: [1, 2, 4, 60])
    func batchingIsInvisible(ticks: Int) {
        let start = SimulationState(tickCount: 7, ship: Self.midFlight)
        let input = ControlInput(thrust: 0.8, turn: -0.4)

        let atOnce = Simulation.advance(start, ticks: ticks, input: input)
        let oneByOne = (0..<ticks).reduce(start) { state, _ in
            Simulation.advance(state, ticks: 1, input: input)
        }
        #expect(bits(atOnce) == bits(oneByOne))
    }
}

// MARK: - Sanitisation

extension ShipMotionTests {
    @Test("Out-of-range input is clamped to the nearest end of its range")
    func inputIsClamped() {
        let input = ControlInput(thrust: -0.5, turn: 2)
        #expect(input.thrust == 0)
        #expect(input.turn == 1)
        #expect(ControlInput(thrust: 3, turn: -7) == ControlInput(thrust: 1, turn: -1))
    }

    @Test("Non-finite input is treated as zero")
    func nonFiniteInputIsZero() {
        let input = ControlInput(thrust: .nan, turn: -.infinity)
        #expect(input.thrust.bitPattern == 0)
        #expect(input.turn.bitPattern == 0)
    }

    @Test("Negative and non-finite limits are treated as zero")
    func limitsAreSanitised() {
        let limits = ShipLimits(maxThrustAcceleration: -1, maxAngularSpeed: .infinity, maxAngularAcceleration: 5)
        #expect(limits.maxThrustAcceleration == 0)
        #expect(limits.maxAngularSpeed == 0)
        #expect(limits.maxAngularAcceleration == 5)
        #expect(ShipLimits(maxThrustAcceleration: .nan, maxAngularSpeed: 1, maxAngularAcceleration: 1)
            .maxThrustAcceleration == 0)
    }

    @Test("A ship with zero limits cannot accelerate or turn, and that is not an error")
    func zeroLimitsHoldStill() {
        let limits = ShipLimits(maxThrustAcceleration: 0, maxAngularSpeed: 0, maxAngularAcceleration: 0)
        let start = Ship(limits: limits)
        let ship = Self.run(start, ticks: 60, ControlInput(thrust: 1, turn: 1))
        #expect(bits(ship) == bits(start))
    }
}
