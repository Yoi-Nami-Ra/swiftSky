import Testing

@testable import SwiftSkyRendering

@Suite("Writing numbers")
struct NumberWritingTests {
    private func text(of value: UInt64, minimumDigits: Int = 1) -> String {
        let buffer = newTextBuffer()
        buffer.write(value, minimumDigits: minimumDigits)
        return String(buffer.cells.map { Character(Unicode.Scalar(UInt8($0) + GlyphAtlasBitmap.firstCode)) })
    }

    @Test("Zero is written as a single digit")
    func zero() {
        #expect(text(of: 0) == "0")
    }

    @Test("Values are zero-padded to the minimum width")
    func padding() {
        #expect(text(of: 123, minimumDigits: 6) == "000123")
    }

    @Test("A value wider than the padding is written in full, never cut short")
    func neverTruncated() {
        #expect(text(of: 1_234_567, minimumDigits: 6) == "1234567")
    }

    @Test("UInt64.max is written in full")
    func largest() {
        #expect(text(of: .max) == "18446744073709551615")
    }
}
