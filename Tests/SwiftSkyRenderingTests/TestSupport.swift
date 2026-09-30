import CoreText

@testable import SwiftSkyRendering

/// Round-number metrics, so expected pixel positions can be written down by hand: 10 px advance, 20 px
/// lines, baseline 15 px below a line's top, and a 12 × 22 px cell starting 1 px left of and 16 px above
/// the pen.
func syntheticMetrics(scale: Double = 1) -> TextMetrics {
    TextMetrics(
        scale: scale,
        advancePixels: 10,
        lineHeightPixels: 20,
        ascentPixels: 15,
        cellWidthPixels: 12,
        cellHeightPixels: 22,
        cellOriginOffsetX: -1,
        cellOriginOffsetY: -16,
        capHeightPoints: 9
    )
}

/// A buffer ready for writing at the surface's top-left, with synthetic metrics.
func newTextBuffer(scale: Double = 1) -> TextBuffer {
    let buffer = TextBuffer(metrics: syntheticMetrics(scale: scale))
    buffer.clear()
    buffer.begin(at: (x: 0, y: 0))
    return buffer
}

/// A real fixed-pitch system font. Creating it needs Core Text only — no GPU.
func systemFixedPitchFont() -> CTFont {
    CTFontCreateUIFontForLanguage(.userFixedPitch, 13, nil)!
}

/// The atlas cell for a printable ASCII character.
func cell(_ character: Character) -> UInt16 {
    GlyphAtlasBitmap.cell(for: character.asciiValue!)
}

extension TextBuffer {
    var cells: [UInt16] { instances.map(\.cell) }
    var positions: [[Int]] { instances.map { [Int($0.x), Int($0.y)] } }
}
