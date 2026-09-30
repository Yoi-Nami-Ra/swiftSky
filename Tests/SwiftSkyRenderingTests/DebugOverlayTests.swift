import Testing

@testable import SwiftSkyRendering

@Suite("Debug overlay")
struct DebugOverlayTests {
    private let surface = RenderSurface(
        widthPixels: 2560,
        heightPixels: 1440,
        backingScale: 2,
        safeAreaInsets: SurfaceInsets(top: 24, left: 44, bottom: 0, right: 0)
    )

    /// The stored characters, with a line break wherever the pen moved down.
    private func lines(in buffer: TextBuffer) -> [String] {
        var lines: [String] = []
        var current = ""
        var lastY: UInt16?
        for instance in buffer.instances {
            if let lastY, instance.y != lastY {
                lines.append(current)
                current = ""
            }
            current.append(Character(Unicode.Scalar(UInt8(instance.cell) + GlyphAtlasBitmap.firstCode)))
            lastY = instance.y
        }
        lines.append(current)
        return lines
    }

    private func written(_ statistics: DebugOverlayStatistics?) -> TextBuffer {
        let overlay = DebugOverlay()
        overlay.statistics = statistics
        let buffer = TextBuffer(metrics: syntheticMetrics(scale: 2))
        buffer.clear()
        overlay.write(into: buffer, surface: surface)
        return buffer
    }

    private let example = DebugOverlayStatistics(
        meanFrameSeconds: 0.000_41,
        worstFrameSeconds: 0.000_97,
        budgetSeconds: 1.0 / 120.0,
        droppedFrames: 0,
        skippedFrames: 0,
        tickCount: 61
    )

    @Test("Nothing is written before the first snapshot arrives")
    func nothingBeforeFirstSnapshot() {
        #expect(written(nil).count == 0)
    }

    @Test("Six labelled lines, in order, matching the contract's example")
    func contractExample() {
        #expect(lines(in: written(example)) == [
            "mean      0.41 ms",
            "worst     0.97 ms",
            "budget    8.33 ms",
            "dropped 0",
            "skipped 0",
            "ticks   61",
        ])
    }

    @Test("Mean and worst read `--`, aligned with the numbers, until a full second has been measured")
    func unknownMeanAndWorst() {
        var statistics = example
        statistics.meanFrameSeconds = nil
        statistics.worstFrameSeconds = nil
        let text = lines(in: written(statistics))
        #expect(text[0] == "mean        -- ms")
        #expect(text[1] == "worst       -- ms")
        #expect(text[2] == "budget    8.33 ms")
    }

    @Test("Every line fits in 33 characters at the normal-range maxima (FR-005)")
    func fitsNarrowestSurface() {
        let statistics = DebugOverlayStatistics(
            meanFrameSeconds: 0.999_99,
            worstFrameSeconds: 0.999_99,
            budgetSeconds: 0.999_99,
            droppedFrames: 9_999_999,
            skippedFrames: 9_999_999,
            tickCount: 9_999_999
        )
        let buffer = written(statistics)
        let text = lines(in: buffer)
        #expect(text.count == 6)
        #expect(text.allSatisfy { $0.count <= 33 })
        #expect(buffer.count < 128)
        #expect(!buffer.didOverflow)
    }

    @Test("Counts are written in full up to UInt64.max")
    func largestCounts() {
        let statistics = DebugOverlayStatistics(
            meanFrameSeconds: nil,
            worstFrameSeconds: nil,
            budgetSeconds: 1.0 / 60.0,
            droppedFrames: .max,
            skippedFrames: .max,
            tickCount: .max
        )
        let text = lines(in: written(statistics))
        #expect(text[3] == "dropped 18446744073709551615")
        #expect(text[4] == "skipped 18446744073709551615")
        #expect(text[5] == "ticks   18446744073709551615")
    }

    @Test("A slow frame is written in full, never cut short")
    func slowFrame() {
        var statistics = example
        statistics.worstFrameSeconds = 1.2345
        #expect(lines(in: written(statistics))[1] == "worst   1234.50 ms")
    }

    @Test("The overlay starts 8 points inside the safe area's top-left")
    func anchor() {
        let buffer = written(example)
        let metrics = buffer.metrics
        let first = buffer.instances[0]
        let expectedX = TextMetrics.pixels(44 + 8, scale: 2) + metrics.cellOriginOffsetX
        let expectedY = TextMetrics.pixels(24 + 8, scale: 2) + metrics.ascentPixels + metrics.cellOriginOffsetY
        #expect(Int(first.x) == expectedX)
        #expect(Int(first.y) == expectedY)
    }
}
