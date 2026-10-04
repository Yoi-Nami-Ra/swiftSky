import Testing

@testable import SwiftSkySimulation

/// `Simulation.advance` is a pure function, so these tests need no setup, no teardown, no clock, and
/// no GPU. That is the property SC-013 and SC-007 both depend on.
@Suite("Simulation")
struct SimulationTests {
    @Test("A fresh state has advanced no ticks")
    func startsAtZero() {
        #expect(SimulationState().tickCount == 0)
    }

    @Test("Advancing zero ticks leaves the state untouched")
    func zeroTicksIsIdentity() {
        let state = SimulationState(tickCount: 42)
        #expect(Simulation.advance(state, ticks: 0) == state)
    }

    @Test("Negative tick counts are treated as zero rather than rewinding time")
    func negativeTicksIsIdentity() {
        let state = SimulationState(tickCount: 42)
        #expect(Simulation.advance(state, ticks: -3) == state)
    }

    @Test("Advancing n ticks increases the count by exactly n", arguments: [1, 2, 4, 60, 1000])
    func advancesByExactly(count: Int) {
        let advanced = Simulation.advance(SimulationState(), ticks: count)
        #expect(advanced.tickCount == UInt64(count))
    }

    @Test("The tick count never decreases across a run")
    func monotonic() {
        var state = SimulationState()
        var previous = state.tickCount
        for ticks in [1, 0, 3, 0, 0, 2, 4] {
            state = Simulation.advance(state, ticks: ticks)
            #expect(state.tickCount >= previous)
            previous = state.tickCount
        }
    }

    // MARK: - Determinism (SC-013)

    @Test("An identical tick sequence produces byte-identical state across ten runs")
    func byteIdenticalAcrossRuns() {
        let sequence = [1, 0, 2, 4, 0, 1, 3, 0, 0, 2]

        func run() -> SimulationState {
            sequence.reduce(SimulationState()) { Simulation.advance($0, ticks: $1) }
        }

        let reference = run()
        for _ in 0..<10 {
            #expect(run() == reference)
        }
        // Sanity: the sequence actually did something, so identity isn't passing trivially.
        #expect(reference.tickCount == 13)
    }

    @Test("Advancing in one step equals advancing in many, for the same total")
    func associativeOverTicks() {
        let oneStep = Simulation.advance(SimulationState(), ticks: 10)
        let manySteps = (0..<10).reduce(SimulationState()) { state, _ in
            Simulation.advance(state, ticks: 1)
        }
        #expect(oneStep == manySteps)
    }

    // MARK: - Accumulator and simulation together

    /// SC-013's second clause: one long elapsed span and many short ones agree on tick count *while
    /// within the clamp*, and differ by the discarded excess beyond it. Both halves are asserted so
    /// the clamp's cost is pinned down rather than left implicit.
    @Test("Within the clamp, one long span and many short spans agree")
    func longVersusShortWithinClamp() {
        let total = FixedTimestep.tickDuration * 3

        var single = TimeAccumulator()
        let singleTicks = single.consume(elapsed: total)

        var fragmented = TimeAccumulator()
        var fragmentedTicks = 0
        for _ in 0..<3 {
            fragmentedTicks += fragmented.consume(elapsed: FixedTimestep.tickDuration)
        }

        #expect(singleTicks == 3)
        #expect(fragmentedTicks == 3)
        #expect(Simulation.advance(SimulationState(), ticks: singleTicks)
            == Simulation.advance(SimulationState(), ticks: fragmentedTicks))
    }

    @Test("Beyond the clamp, one long span deliberately loses time that many short spans keep")
    func longVersusShortBeyondClamp() {
        var single = TimeAccumulator()
        let singleTicks = single.consume(elapsed: 1.0)

        var fragmented = TimeAccumulator()
        var fragmentedTicks = 0
        for _ in 0..<60 {
            fragmentedTicks += fragmented.consume(elapsed: FixedTimestep.tickDuration)
        }

        #expect(singleTicks == FixedTimestep.catchUpClamp)
        #expect(fragmentedTicks == 60)
        // Documented behaviour, not a defect: the clamp trades simulation time for frame stability.
        #expect(fragmentedTicks > singleTicks)
    }

    // MARK: - The previous pose (013 FR-005, SC-003)

    /// A moving, turning ship flying an order, so consecutive ticks differ in position and heading.
    static func flyingState() -> SimulationState {
        let ship = Ship(position: Vector2(x: 30, y: -12), velocity: Vector2(x: 80, y: 25), heading: 2.9, angularVelocity: 0.8)
        var state = SimulationState(tickCount: 7, ship: ship)
        state.setOrder(to: Vector2(x: -400, y: 300))
        return Simulation.advance(state, ticks: 5)
    }

    static let sentinel = ShipPose(position: Vector2(x: 123, y: 456), heading: -1)

    @Test("With the autopilot, the previous pose is the one before the frame's last tick", arguments: [0, 1, 2, 4])
    func previousPoseFlown(ticks: Int) {
        let state = Self.flyingState()
        var previous = Self.sentinel
        let next = Simulation.advance(state, ticks: ticks, previousPose: &previous)

        #expect(bits(next) == bits(Simulation.advance(state, ticks: ticks)))
        if ticks == 0 {
            #expect(bits(previous) == bits(Self.sentinel))
        } else {
            #expect(bits(previous) == bits(ShipPose(Simulation.advance(state, ticks: ticks - 1).ship)))
        }
    }

    @Test("With an explicit input, the previous pose is the one before the frame's last tick", arguments: [0, 1, 2, 4])
    func previousPoseWithInput(ticks: Int) {
        let state = Self.flyingState()
        let input = ControlInput(thrust: 1, turn: -1)
        var previous = Self.sentinel
        let next = Simulation.advance(state, ticks: ticks, input: input, previousPose: &previous)

        #expect(bits(next) == bits(Simulation.advance(state, ticks: ticks, input: input)))
        if ticks == 0 {
            #expect(bits(previous) == bits(Self.sentinel))
        } else {
            #expect(bits(previous) == bits(ShipPose(Simulation.advance(state, ticks: ticks - 1, input: input).ship)))
        }
    }

    @Test("Frame by frame, the previous pose always trails the state by exactly one tick")
    func previousPoseTrailsOneTick() {
        var state = Self.flyingState()
        var previous = ShipPose(state.ship)
        for ticks in [1, 0, 0, 2, 1, 4, 0, 3, 1] {
            let before = state
            state = Simulation.advance(state, ticks: ticks, previousPose: &previous)
            if ticks > 0 {
                #expect(bits(previous) == bits(ShipPose(Simulation.advance(before, ticks: ticks - 1).ship)))
                #expect(bits(ShipPose(Simulation.advance(before, ticks: ticks).ship)) == bits(ShipPose(state.ship)))
            }
        }
    }
}
