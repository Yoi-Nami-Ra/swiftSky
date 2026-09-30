import Testing

@testable import SwiftSkyRendering

@Suite("Glyph atlas bitmap")
struct GlyphAtlasBitmapTests {
    @Test("The bitmap is a 16 × 6 grid of cells", arguments: [1.0, 2.0, 3.0])
    func dimensions(scale: Double) throws {
        let bitmap = try GlyphAtlasBitmap.make(font: systemFixedPitchFont(), scale: scale)
        #expect(bitmap.widthPixels == 16 * bitmap.metrics.cellWidthPixels)
        #expect(bitmap.heightPixels == 6 * bitmap.metrics.cellHeightPixels)
        #expect(bitmap.bytes.count == bitmap.widthPixels * bitmap.heightPixels)
        #expect(bitmap.metrics.scale == scale)
    }

    @Test("Every printable glyph except space leaves ink; space leaves none", arguments: [1.0, 2.0, 3.0])
    func ink(scale: Double) throws {
        let bitmap = try GlyphAtlasBitmap.make(font: systemFixedPitchFont(), scale: scale)
        #expect(bitmap.cellPixels(0).allSatisfy { $0 == 0 })
        for cell in 1..<GlyphAtlasBitmap.glyphCount {
            #expect(bitmap.cellPixels(cell).contains { $0 > 0 }, "cell \(cell) is empty")
        }
    }

    @Test("All 95 glyphs are distinct images (SC-007)", arguments: [1.0, 2.0, 3.0])
    func distinct(scale: Double) throws {
        let bitmap = try GlyphAtlasBitmap.make(font: systemFixedPitchFont(), scale: scale)
        let images = (0..<GlyphAtlasBitmap.glyphCount).map { bitmap.cellPixels($0) }
        #expect(Set(images).count == GlyphAtlasBitmap.glyphCount)
    }

    @Test("Character codes map to cells; anything unprintable maps to the replacement glyph")
    func cellMapping() {
        #expect(GlyphAtlasBitmap.cell(for: 0x20) == 0)
        #expect(GlyphAtlasBitmap.cell(for: 0x7E) == 94)
        for code: UInt8 in [0x0A, 0x1F, 0x7F, 0xC3, 0xFF] {
            #expect(GlyphAtlasBitmap.cell(for: code) == 31)
        }
    }
}
