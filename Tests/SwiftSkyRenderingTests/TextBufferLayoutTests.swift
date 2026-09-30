import Testing

@testable import SwiftSkyRendering

@Suite("Text buffer layout")
struct TextBufferLayoutTests {
    @Test("Consecutive characters advance one cell each")
    func consecutiveCells() {
        let buffer = newTextBuffer()
        buffer.write("AB C" as StaticString)
        #expect(buffer.cells == [cell("A"), cell("B"), cell(" "), cell("C")])
        // Pen starts at x 0, baseline 15; the cell is at pen + (-1, -16), clamped at 0.
        #expect(buffer.positions == [[0, 0], [9, 0], [19, 0], [29, 0]])
    }

    @Test("A line feed returns to the left edge one line lower", arguments: ["A\nB", "A\r\nB"])
    func lineFeed(text: String) {
        let buffer = TextBuffer(metrics: syntheticMetrics())
        buffer.clear()
        buffer.begin(at: (x: 5, y: 5))
        buffer.write(text)
        #expect(buffer.count == 2)
        #expect(buffer.positions == [[4, 4], [4, 24]])
    }

    @Test("StaticString treats CRLF as one line feed")
    func staticCRLF() {
        let buffer = TextBuffer(metrics: syntheticMetrics())
        buffer.clear()
        buffer.begin(at: (x: 0, y: 10))  // away from the top edge, so no clamping
        buffer.write("A\r\nB" as StaticString)
        #expect(buffer.cells == [cell("A"), cell("B")])
        #expect(buffer.positions[1][1] - buffer.positions[0][1] == 20)
    }

    @Test("Consecutive line feeds each advance a line; a trailing one draws nothing")
    func consecutiveAndTrailingLineFeeds() {
        let buffer = TextBuffer(metrics: syntheticMetrics())
        buffer.clear()
        buffer.begin(at: (x: 0, y: 10))
        buffer.write("A\n\nB\n" as StaticString)
        #expect(buffer.count == 2)
        #expect(buffer.positions[1][1] - buffer.positions[0][1] == 40)
    }

    @Test("Non-ASCII characters each become exactly one replacement glyph", arguments: ["é", "👍🏽", "\u{7}", "e\u{301}"])
    func replacement(text: String) {
        let buffer = newTextBuffer()
        buffer.write(text)
        #expect(buffer.cells == [GlyphAtlasBitmap.replacementCell])
    }

    @Test("A UTF-8 lead byte in a literal becomes one replacement glyph")
    func staticNonASCII() {
        let buffer = newTextBuffer()
        buffer.write("aéb" as StaticString)
        #expect(buffer.cells == [cell("a"), GlyphAtlasBitmap.replacementCell, cell("b")])
    }

    @Test("The replacement glyph is the question mark's cell")
    func replacementIsQuestionMark() {
        #expect(GlyphAtlasBitmap.replacementCell == cell("?"))
    }

    @Test("An empty string stores nothing")
    func empty() {
        let buffer = newTextBuffer()
        buffer.write("" as StaticString)
        buffer.write("")
        #expect(buffer.count == 0)
        #expect(!buffer.didOverflow)
    }

    @Test("Coordinates outside 0…65535 are clamped rather than wrapping")
    func clamping() {
        let buffer = TextBuffer(metrics: syntheticMetrics())
        buffer.clear()
        buffer.begin(at: (x: 70_000, y: 70_000))
        buffer.write("A" as StaticString)
        #expect(buffer.positions == [[65_535, 65_535]])
    }
}
