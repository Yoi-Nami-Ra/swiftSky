import CoreGraphics
import Testing

@testable import SwiftSkyRendering

@Suite("Text metrics")
struct TextMetricsTests {
    @Test("GlyphInstance is exactly 8 bytes, matching the shader's struct")
    func glyphInstanceLayout() {
        #expect(MemoryLayout<GlyphInstance>.size == 8)
        #expect(MemoryLayout<GlyphInstance>.stride == 8)
    }

    @Test("Advance and line height round to whole pixels at each scale", arguments: [
        (1.0, 8, 16),   // 7.8 → 8, 15.6 → 16
        (2.0, 16, 31),  // 15.6 → 16, 31.2 → 31
        (3.0, 23, 47),  // 23.4 → 23, 46.8 → 47
    ])
    func rounding(scale: Double, advance: Int, lineHeight: Int) {
        let metrics = TextMetrics.make(
            advancePoints: 7.8,
            ascentPoints: 12.0,
            descentPoints: 3.2,
            leadingPoints: 0.4,
            capHeightPoints: 9.2,
            glyphBoundsPoints: CGRect(x: 0.3, y: -3.1, width: 7.2, height: 15.0),
            scale: scale
        )
        #expect(metrics.advancePixels == advance)
        #expect(metrics.lineHeightPixels == lineHeight)
        #expect(metrics.ascentPixels == Int((12.0 * scale).rounded()))
    }

    @Test("The cell covers the glyph bounds rounded out, plus 1 px padding per side")
    func cellRoundsOut() {
        // Bounds x 0.3…7.5, y -3.1…11.9 points; at 2×: x 0.6…15.0, y -6.2…23.8 pixels.
        let metrics = TextMetrics.make(
            advancePoints: 7.8, ascentPoints: 12, descentPoints: 3.2, leadingPoints: 0,
            capHeightPoints: 9.2,
            glyphBoundsPoints: CGRect(x: 0.3, y: -3.1, width: 7.2, height: 15.0),
            scale: 2
        )
        // left = floor(0.6) - 1 = -1, right = ceil(15.0) + 1 = 16 → width 17
        // bottom = floor(-6.2) - 1 = -8, top = ceil(23.8) + 1 = 25 → height 33
        #expect(metrics.cellOriginOffsetX == -1)
        #expect(metrics.cellWidthPixels == 17)
        #expect(metrics.cellOriginOffsetY == -25)
        #expect(metrics.cellHeightPixels == 33)
    }

    @Test("begin(at:) snaps fractional points to whole pixels", arguments: [1.0, 2.0, 3.0])
    func beginSnaps(scale: Double) {
        let buffer = TextBuffer(metrics: syntheticMetrics(scale: scale))
        buffer.clear()
        buffer.begin(at: (x: 8.4, y: 8.4))
        buffer.write("A" as StaticString)
        let expectedX = Int((8.4 * scale).rounded()) - 1
        let expectedY = Int((8.4 * scale).rounded()) + 15 - 16
        #expect(buffer.positions == [[expectedX, expectedY]])
    }

    @Test("A real fixed-pitch font yields positive metrics at 1×, 2× and 3×", arguments: [1.0, 2.0, 3.0])
    func realFont(scale: Double) {
        let metrics = TextMetrics.make(font: systemFixedPitchFont(), scale: scale)
        #expect(metrics.advancePixels > 0)
        #expect(metrics.lineHeightPixels > 0)
        #expect(metrics.cellWidthPixels >= metrics.advancePixels)
        #expect(metrics.cellHeightPixels > 0)
        #expect(metrics.capHeightPoints > 0)
        #expect(metrics.scale == scale)
    }
}
