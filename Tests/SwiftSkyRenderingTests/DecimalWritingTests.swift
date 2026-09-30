import Testing

@testable import SwiftSkyRendering

@Suite("Writing decimals")
struct DecimalWritingTests {
    private func text(of buffer: TextBuffer) -> String {
        String(buffer.cells.map { Character(Unicode.Scalar(UInt8($0) + GlyphAtlasBitmap.firstCode)) })
    }

    private func hundredths(_ value: Double, width: Int = 0, limit: Int = .max) -> String {
        let buffer = newTextBuffer()
        buffer.writeHundredths(value, width: width, limit: limit)
        return text(of: buffer)
    }

    @Test(
        "Frame times are written with two decimals, right-aligned in six columns (contract table)",
        arguments: [
            (0.0, "  0.00"),
            (0.004, "  0.00"),
            (0.005, "  0.01"),
            (8.333, "  8.33"),
            (16.667, " 16.67"),
            (999.994, "999.99"),
            (1234.5, "1234.50"),
            (-1.0, "  0.00"),
            (Double.nan, "  0.00"),
        ]
    )
    func contractTable(value: Double, expected: String) {
        #expect(hundredths(value, width: 6) == expected)
    }

    @Test("Width 0 writes no padding")
    func noPadding() {
        #expect(hundredths(8.333) == "8.33")
    }

    @Test("A value wider than its width is written in full, never cut short (FR-007)")
    func neverTruncated() {
        #expect(hundredths(123_456.789, width: 6) == "123456.79")
    }

    @Test("Huge and infinite values are clamped rather than trapping or using exponent notation")
    func clamped() {
        let largest = "\(UInt64.max / 100).\(UInt64.max % 100)"
        #expect(hundredths(1e300) == largest)
        #expect(hundredths(.infinity) == largest)
    }

    @Test("The limit is respected in the middle of a number")
    func limit() {
        #expect(hundredths(16.667, width: 6, limit: 4) == " 16.")
        #expect(hundredths(16.667, width: 6, limit: 1) == " ")
        #expect(hundredths(16.667, limit: 2) == "16")
    }

    @Test("A literal is right-aligned in its width: the overlay's `--` placeholder")
    func padded() {
        let buffer = newTextBuffer()
        buffer.writePadded("--", width: 6)
        #expect(text(of: buffer) == "    --")

        let narrow = newTextBuffer()
        narrow.writePadded("--", width: 1)
        #expect(text(of: narrow) == "--")
    }

    @Test("Decimals stop cleanly at capacity instead of overflowing past it")
    func capacity() {
        let buffer = newTextBuffer()
        buffer.write(String(repeating: "x", count: TextBuffer.capacity - 3))
        buffer.writeHundredths(16.667, width: 6)
        #expect(buffer.count == TextBuffer.capacity)
        #expect(buffer.didOverflow)
    }
}
