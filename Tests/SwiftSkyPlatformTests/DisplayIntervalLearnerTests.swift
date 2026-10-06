import Testing

@testable import SwiftSkyPlatform

/// Contract C3 of specs/016-frame-budget-learner: gap series in milliseconds and the budget they end on.
@Suite("Display interval learner")
struct DisplayIntervalLearnerTests {
    private static let hz120 = 1000.0 / 120.0
    private static let hz60 = 1000.0 / 60.0

    /// A learner whose floor is set to `framesPerSecond`.
    private func learner(maximumFramesPerSecond framesPerSecond: Int) -> DisplayIntervalLearner {
        var learner = DisplayIntervalLearner()
        _ = learner.setMaximumFramesPerSecond(framesPerSecond)
        return learner
    }

    /// Feeds gaps given in milliseconds; returns every budget the learner reported, in seconds.
    @discardableResult
    private func feed(_ learner: inout DisplayIntervalLearner, _ gapsMilliseconds: [Double]) -> [Double] {
        var reported: [Double] = []
        for gap in gapsMilliseconds {
            if let budget = learner.observe(gap: gap / 1000) { reported.append(budget) }
        }
        return reported
    }

    private func repeated(_ gap: Double, _ count: Int) -> [Double] {
        Array(repeating: gap, count: count)
    }

    private func isClose(_ seconds: Double, _ milliseconds: Double) -> Bool {
        abs(seconds - milliseconds / 1000) < 1e-9
    }

    // MARK: - US1: consecutive confirmation

    @Test("1: a steady 120 Hz series settles on 8.33 ms")
    func steady120() {
        var learner = learner(maximumFramesPerSecond: 120)
        feed(&learner, repeated(Self.hz120, 20))
        #expect(learner.interval == 1.0 / 120.0)
    }

    @Test("2: a 60 Hz series with one doubled gap stays at 16.67 ms")
    func doubledGap() {
        var learner = learner(maximumFramesPerSecond: 60)
        feed(&learner, repeated(Self.hz60, 10) + [2 * Self.hz60] + repeated(Self.hz60, 10))
        #expect(isClose(learner.interval, Self.hz60))
    }

    @Test("3: two matching short gaps separated by normal ones are not adopted")
    func separatedShortGaps() {
        var learner = learner(maximumFramesPerSecond: 120)
        let series = repeated(Self.hz60, 5) + [14.84] + repeated(Self.hz60, 5) + [14.84] + repeated(Self.hz60, 5)
        feed(&learner, series)
        #expect(isClose(learner.interval, Self.hz60))
    }

    @Test("4: simulator-like jitter (a late gap, then a catch-up gap) does not lower the budget")
    func simulatorJitter() {
        var learner = learner(maximumFramesPerSecond: 120)
        var series = repeated(Self.hz60, 10)
        for _ in 0..<25 { series += [Self.hz60, Self.hz60, 22.0, 11.3] }
        feed(&learner, series)
        #expect(isClose(learner.interval, Self.hz60))
    }

    @Test("5: a single startup outlier is ignored")
    func startupOutlier() {
        var learner = learner(maximumFramesPerSecond: 120)
        feed(&learner, [5.0] + repeated(Self.hz60, 20))
        #expect(isClose(learner.interval, Self.hz60))
    }

    @Test("Implausible gaps neither confirm nor clear a candidate")
    func implausibleGapsSkipped() {
        var learner = learner(maximumFramesPerSecond: 120)
        feed(&learner, repeated(Self.hz60, 4))
        // 12 ms waits; 3 ms (above 250 Hz) and 60 ms (below 20 Hz) are skipped; the next 12 ms confirms.
        let reported = feed(&learner, [12.0, 3.0, 60.0, 12.0])
        #expect(reported.count == 1)
        #expect(isClose(learner.interval, 12.0))
    }

    @Test("A confirmation that does not change the budget reports nothing")
    func unchangedReportsNil() {
        var learner = learner(maximumFramesPerSecond: 120)
        #expect(feed(&learner, repeated(Self.hz120, 2)) == [1.0 / 120.0])
        #expect(feed(&learner, repeated(Self.hz120, 20)).isEmpty)
    }

    @Test("A disagreeing shorter gap replaces the candidate")
    func candidateReplaced() {
        var learner = learner(maximumFramesPerSecond: 120)
        feed(&learner, repeated(Self.hz60, 4))
        feed(&learner, [14.0, 10.0, 10.0])
        #expect(isClose(learner.interval, 10.0))
    }

    @Test("A gap a hair under the learned budget does not nudge it down")
    func roundingDoesNotNudge() {
        var learner = learner(maximumFramesPerSecond: 120)
        feed(&learner, repeated(Self.hz60, 4))
        let before = learner.interval
        #expect(feed(&learner, repeated(Self.hz60 - 0.0001, 10)).isEmpty)
        #expect(learner.interval == before)
    }
}
