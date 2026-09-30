import Testing

@testable import SwiftSkyRendering

@Suite("Text buffer capacity")
struct TextBufferCapacityTests {
    private func write(_ count: Int, into buffer: TextBuffer) {
        for _ in 0..<count { buffer.write("x" as StaticString) }
    }

    @Test("More than 1,024 characters store exactly 1,024 and report the overflow")
    func overflow() {
        let buffer = newTextBuffer()
        write(1_100, into: buffer)
        #expect(buffer.count == TextBuffer.capacity)
        #expect(buffer.remainingCapacity == 0)
        #expect(buffer.didOverflow)
    }

    @Test("Exactly 1,024 characters do not report an overflow")
    func exactlyFull() {
        let buffer = newTextBuffer()
        write(1_024, into: buffer)
        #expect(buffer.count == 1_024)
        #expect(!buffer.didOverflow)
    }

    @Test("Line feeds do not count toward capacity")
    func lineFeedsAreFree() {
        let buffer = newTextBuffer()
        for _ in 0..<2_000 { buffer.write("\n" as StaticString) }
        #expect(buffer.count == 0)
        #expect(!buffer.didOverflow)
    }

    @Test("limit caps how many characters one write stores")
    func limit() {
        let buffer = newTextBuffer()
        buffer.write("abcdef" as StaticString, limit: 3)
        buffer.write("abcdef", limit: 2)
        buffer.write(123_456, limit: 4)
        #expect(buffer.count == 9)
        #expect(!buffer.didOverflow)
    }

    @Test("clear() empties the buffer and resets the overflow flag")
    func clearResets() {
        let buffer = newTextBuffer()
        write(1_100, into: buffer)
        buffer.clear()
        #expect(buffer.count == 0)
        #expect(!buffer.didOverflow)
        #expect(buffer.remainingCapacity == TextBuffer.capacity)
    }
}
