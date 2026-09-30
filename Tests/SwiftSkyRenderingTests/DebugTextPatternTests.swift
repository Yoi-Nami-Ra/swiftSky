import Testing

@testable import SwiftSkyRendering

@Suite("Debug text pattern")
struct DebugTextPatternTests {
    private let surface = RenderSurface(widthPixels: 2560, heightPixels: 1440, backingScale: 2)

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

    @Test("The test string holds all 95 printable characters in code order, in lines of 33, 32 and 30")
    func testStringContent() {
        let buffer = TextBuffer(metrics: syntheticMetrics(scale: 2))
        buffer.clear()
        DebugTextPattern(mode: .testString).write(into: buffer, surface: surface, timestamp: 0)

        let written = lines(in: buffer)
        #expect(written.count == 4)
        #expect(written[0].count == 33)
        #expect(written[1].count == 32)
        #expect(written[2].count == 30)

        let expected = String((0x20...0x7E).map { Character(Unicode.Scalar(UInt8($0))) })
        #expect(written[0] + written[1] + written[2] == expected)
        #expect(!buffer.didOverflow)
    }

    @Test("The FPS line reads `fps --` until a full second has been measured")
    func fpsUnknownAtFirst() {
        let pattern = DebugTextPattern(mode: .testString)
        let buffer = TextBuffer(metrics: syntheticMetrics(scale: 2))
        for frame in 0..<60 {
            buffer.clear()
            pattern.write(into: buffer, surface: surface, timestamp: Double(frame) / 120)
        }
        #expect(lines(in: buffer)[3] == "fps --")
        #expect(pattern.framesPerSecond == nil)
    }

    @Test("FPS is the whole number of frames drawn in the past second", arguments: [60, 120, 30])
    func fpsMatchesRate(rate: Int) {
        let pattern = DebugTextPattern(mode: .testString)
        let buffer = TextBuffer(metrics: syntheticMetrics(scale: 2))
        for frame in 0...(rate + 1) {
            buffer.clear()
            pattern.write(into: buffer, surface: surface, timestamp: 100 + Double(frame) / Double(rate))
        }
        #expect(pattern.framesPerSecond == UInt64(rate))
        #expect(lines(in: buffer)[3] == "fps \(rate)")
    }

    @Test("A pause restarts the measurement instead of dragging the value down")
    func pauseRestarts() {
        let pattern = DebugTextPattern(mode: .testString)
        for frame in 0...121 { pattern.recordFrame(at: Double(frame) / 120) }
        #expect(pattern.framesPerSecond == 120)

        // Hidden for 5 seconds, then 120 Hz again: the 5 s gap must not count as one very long frame.
        let resume = 1.0 + 5.0
        for frame in 0...121 { pattern.recordFrame(at: resume + Double(frame) / 120) }
        #expect(pattern.framesPerSecond == 120)
    }

    @Test("The test string starts 8 points inside the safe area's top-left")
    func anchor() {
        let insetSurface = RenderSurface(
            widthPixels: 2556, heightPixels: 1179, backingScale: 3,
            safeAreaInsets: SurfaceInsets(top: 0, left: 59, bottom: 21, right: 59)
        )
        let buffer = TextBuffer(metrics: syntheticMetrics(scale: 3))
        buffer.clear()
        DebugTextPattern(mode: .testString).write(into: buffer, surface: insetSurface, timestamp: 0)

        let first = buffer.instances[0]
        // Pen at ((59 + 8) × 3, 8 × 3 + ascent 15); cell offset (-1, -16).
        #expect(first.x == UInt16((59 + 8) * 3 - 1))
        #expect(first.y == UInt16(8 * 3 + 15 - 16))
    }

    @Test("Fill stores exactly 1,024 characters and never reports an overflow", arguments: [
        RenderSurface(widthPixels: 2560, heightPixels: 1440, backingScale: 2),
        RenderSurface(widthPixels: 640, heightPixels: 480, backingScale: 1),
    ])
    func fill(surface: RenderSurface) {
        let pattern = DebugTextPattern(mode: .fill)
        let buffer = TextBuffer(metrics: syntheticMetrics(scale: surface.backingScale))
        for _ in 0..<3 {
            buffer.clear()
            pattern.write(into: buffer, surface: surface, timestamp: 0)
            #expect(buffer.count == TextBuffer.capacity)
            #expect(!buffer.didOverflow)
        }
    }
}
