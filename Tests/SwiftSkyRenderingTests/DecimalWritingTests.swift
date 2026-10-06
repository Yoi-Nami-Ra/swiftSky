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

    // MARK: Signed (015 contract C1)

    private func signed(_ value: Double, width: Int = 0, limit: Int = .max) -> String {
        let buffer = newTextBuffer()
        buffer.writeSignedHundredths(value, width: width, limit: limit)
        return text(of: buffer)
    }

    @Test(
        "Signed values are written with two decimals, right-aligned in nine columns (contract C1 table)",
        arguments: [
            (0.0, "     0.00"),
            (-0.004, "     0.00"),
            (-0.005, "    -0.01"),
            (12.345, "    12.35"),
            (-1234.5, " -1234.50"),
            (99_999.99, " 99999.99"),
            (-99_999.99, "-99999.99"),
            (-123_456.789, "-123456.79"),
            (Double.nan, "     0.00"),
        ]
    )
    func signedContractTable(value: Double, expected: String) {
        #expect(signed(value, width: 9) == expected)
    }

    @Test("A value that rounds to zero has no sign, even from below")
    func noNegativeZero() {
        #expect(signed(-0.0) == "0.00")
        #expect(signed(-0.000_1) == "0.00")
        #expect(signed(-0.0049) == "0.00")
    }

    @Test("Width 0 writes no padding, sign included")
    func signedNoPadding() {
        #expect(signed(-8.333) == "-8.33")
        #expect(signed(8.333) == "8.33")
    }

    @Test("Negative infinity is clamped with its sign rather than trapping")
    func signedClamped() {
        let largest = "\(UInt64.max / 100).\(UInt64.max % 100)"
        #expect(signed(-.infinity) == "-" + largest)
        #expect(signed(.infinity) == largest)
    }

    @Test("The limit is respected around the sign and in the middle of a number")
    func signedLimit() {
        #expect(signed(-16.667, width: 9, limit: 3) == "   ")
        #expect(signed(-16.667, width: 9, limit: 4) == "   -")
        #expect(signed(-16.667, width: 9, limit: 6) == "   -16")
        #expect(signed(-16.667, limit: 1) == "-")
    }

    @Test("The unsigned writer is unchanged: negative values still write as 0.00")
    func unsignedUnchanged() {
        #expect(hundredths(-12.5, width: 6) == "  0.00")
    }
}
