import Testing

@testable import SwiftSkySimulation

/// Every test here runs synchronously with no isolation context and no graphics device — which is the
/// whole point of FR-011 and FR-012d. Elapsed time is always injected, never read from a clock.
@Suite("TimeAccumulator")
struct TimeAccumulatorTests {
    /// One tick's worth of seconds, for readability.
    static let tick = FixedTimestep.tickDuration

    @Test("A fresh accumulator has consumed nothing")
    func startsEmpty() {
        let accumulator = TimeAccumulator()
        #expect(accumulator.unconsumed == 0)
    }

    @Test("Less than one tick of elapsed time advances no ticks")
    func subTickReturnsZero() {
        var accumulator = TimeAccumulator()
        #expect(accumulator.consume(elapsed: Self.tick * 0.4) == 0)
        #expect(accumulator.unconsumed > 0)
    }

    @Test("Exactly one tick advances one tick")
    func singleTick() {
        var accumulator = TimeAccumulator()
        #expect(accumulator.consume(elapsed: Self.tick) == 1)
    }

    /// The simulation is 60 Hz while the display may be faster or slower, so a frame legitimately
    /// advances 0, 1, or several ticks.
    @Test("Whole multiples advance that many ticks", arguments: [1, 2, 3, 4])
    func wholeMultiples(count: Int) {
        var accumulator = TimeAccumulator()
        #expect(accumulator.consume(elapsed: Self.tick * Double(count)) == count)
    }

    @Test("A sub-tick remainder carries into the next frame")
    func remainderCarries() {
        var accumulator = TimeAccumulator()
        // 1.5 ticks: one tick now, half a tick carried.
        #expect(accumulator.consume(elapsed: Self.tick * 1.5) == 1)
        // Another 0.6 ticks brings the carried 0.5 over the line.
        #expect(accumulator.consume(elapsed: Self.tick * 0.6) == 1)
    }

    @Test("Accumulating in fragments eventually advances a tick")
    func fragmentsAccumulate() {
        var accumulator = TimeAccumulator()
        var advanced = 0
        // Ten tenths of a tick must produce exactly one tick, not zero and not two.
        for _ in 0..<10 {
            advanced += accumulator.consume(elapsed: Self.tick * 0.1)
        }
        #expect(advanced == 1)
    }

    // MARK: - The FR-021b catch-up clamp

    @Test("Exactly the clamp limit is not clamped")
    func atClampBoundary() {
        var accumulator = TimeAccumulator()
        let atLimit = Self.tick * Double(FixedTimestep.catchUpClamp)
        #expect(accumulator.consume(elapsed: atLimit) == FixedTimestep.catchUpClamp)
    }

    @Test("One tick beyond the clamp is clamped")
    func justOverClamp() {
        var accumulator = TimeAccumulator()
        let overLimit = Self.tick * Double(FixedTimestep.catchUpClamp + 1)
        #expect(accumulator.consume(elapsed: overLimit) == FixedTimestep.catchUpClamp)
    }

    /// SC-013's named case: a 10-second stall advances 4 ticks, not 600. The simulation loses time
    /// rather than stalling the frame budget trying to reclaim it.
    @Test("A ten-second stall advances exactly four ticks, not six hundred")
    func tenSecondStall() {
        var accumulator = TimeAccumulator()
        #expect(accumulator.consume(elapsed: 10.0) == 4)
    }

    @Test("A clamped frame leaves less than one tick unconsumed, so the next frame starts clean")
    func clampDiscardsOvershoot() {
        var accumulator = TimeAccumulator()
        _ = accumulator.consume(elapsed: 10.0)
        #expect(accumulator.unconsumed < FixedTimestep.tickDuration)
        // The next frame must not immediately clamp again — the backlog is gone, not deferred.
        #expect(accumulator.consume(elapsed: Self.tick) <= 2)
    }

    @Test("Repeated long stalls each clamp independently rather than compounding")
    func repeatedStalls() {
        var accumulator = TimeAccumulator()
        for _ in 0..<5 {
            #expect(accumulator.consume(elapsed: 30.0) == FixedTimestep.catchUpClamp)
        }
    }

    // MARK: - Defensive input

    @Test("Non-positive and non-finite elapsed times are ignored", arguments: [0.0, -1.0, -0.001])
    func nonPositiveIgnored(elapsed: Double) {
        var accumulator = TimeAccumulator()
        #expect(accumulator.consume(elapsed: elapsed) == 0)
        #expect(accumulator.unconsumed == 0)
    }

    @Test("Infinity and NaN cannot corrupt the accumulator")
    func nonFiniteIgnored() {
        var accumulator = TimeAccumulator()
        #expect(accumulator.consume(elapsed: .infinity) == 0)
        #expect(accumulator.consume(elapsed: .nan) == 0)
        #expect(accumulator.unconsumed == 0)
    }

    // MARK: - Determinism (SC-013)

    @Test("An identical sequence of elapsed spans produces an identical tick sequence")
    func deterministicAcrossRuns() {
        let spans = [0.004, 0.017, 0.033, 0.008, 0.100, 0.016, 2.5, 0.016]

        func run() -> [Int] {
            var accumulator = TimeAccumulator()
            return spans.map { accumulator.consume(elapsed: $0) }
        }

        let reference = run()
        for _ in 0..<10 {
            #expect(run() == reference)
        }
    }
}
