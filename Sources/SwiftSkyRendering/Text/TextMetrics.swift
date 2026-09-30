import CoreGraphics
import CoreText

/// The text font's measurements, converted to whole physical pixels for one backing scale.
///
/// Everything the layout needs is an integer number of pixels, decided once per scale. That is what
/// makes FR-009 hold: every glyph cell starts on a whole pixel, so the atlas is never resampled and
/// text stays as sharp as the system's own. The cost is that a line can differ from the system's
/// width by up to half a pixel per character, because the advance is rounded (research.md R3).
///
/// Coordinates are y-down, like the surface: the pen sits on the baseline, and a cell's top-left is
/// the pen position plus `cellOriginOffsetX/Y`, which puts it up and usually a little to the left.
public struct TextMetrics: Sendable, Equatable {
    /// The backing scale these pixels were computed for.
    public let scale: Double

    /// Horizontal distance from one character to the next. The font is monospaced, so it is the same
    /// for every character.
    public let advancePixels: Int

    /// Vertical distance from one baseline to the next.
    public let lineHeightPixels: Int

    /// Distance from the top of a line to its baseline.
    public let ascentPixels: Int

    /// Size of one atlas cell, and so of one glyph quad: the union of every glyph's bounds, rounded
    /// out, plus padding so no glyph bleeds into its neighbour's cell.
    public let cellWidthPixels: Int
    public let cellHeightPixels: Int

    /// From the pen position (on the baseline) to the cell's top-left corner.
    public let cellOriginOffsetX: Int
    public let cellOriginOffsetY: Int

    /// The font's cap height in points. Not used for layout — logged so quickstart checks 5–7 have a
    /// value to measure the rendered capitals against (SC-001).
    public let capHeightPoints: Double

    /// Transparent pixels around every glyph inside its cell, on each side.
    static let cellPaddingPixels = 1

    init(
        scale: Double,
        advancePixels: Int,
        lineHeightPixels: Int,
        ascentPixels: Int,
        cellWidthPixels: Int,
        cellHeightPixels: Int,
        cellOriginOffsetX: Int,
        cellOriginOffsetY: Int,
        capHeightPoints: Double
    ) {
        self.scale = scale
        self.advancePixels = advancePixels
        self.lineHeightPixels = lineHeightPixels
        self.ascentPixels = ascentPixels
        self.cellWidthPixels = cellWidthPixels
        self.cellHeightPixels = cellHeightPixels
        self.cellOriginOffsetX = cellOriginOffsetX
        self.cellOriginOffsetY = cellOriginOffsetY
        self.capHeightPoints = capHeightPoints
    }

    /// Measures `font` and converts the result to pixels at `scale`.
    ///
    /// Setup-time only: it allocates the glyph arrays it needs. Called on the first frame and on each
    /// backing-scale change, never on an ordinary frame (FR-004, FR-010).
    public static func make(font: CTFont, scale: Double) -> TextMetrics {
        let glyphs = printableGlyphs(of: font)

        var advance = CGSize.zero
        var mGlyph = glyphs[Int(UInt8(ascii: "M") - GlyphAtlasBitmap.firstCode)]
        CTFontGetAdvancesForGlyphs(font, .horizontal, &mGlyph, &advance, 1)

        let bounds = CTFontGetBoundingRectsForGlyphs(font, .horizontal, glyphs, nil, glyphs.count)

        return make(
            advancePoints: Double(advance.width),
            ascentPoints: Double(CTFontGetAscent(font)),
            descentPoints: Double(CTFontGetDescent(font)),
            leadingPoints: Double(CTFontGetLeading(font)),
            capHeightPoints: Double(CTFontGetCapHeight(font)),
            glyphBoundsPoints: bounds,
            scale: scale
        )
    }

    /// The pure part of `make(font:scale:)`: font values in points in, whole pixels out. Split out so
    /// the rounding rules can be tested with exact synthetic values rather than a real font's.
    ///
    /// `glyphBoundsPoints` is in Core Text's y-up space, relative to the glyph's origin on the baseline.
    static func make(
        advancePoints: Double,
        ascentPoints: Double,
        descentPoints: Double,
        leadingPoints: Double,
        capHeightPoints: Double,
        glyphBoundsPoints: CGRect,
        scale: Double
    ) -> TextMetrics {
        let padding = cellPaddingPixels

        // Rounded OUT, so the cell covers every pixel a glyph can touch.
        let left = Int((Double(glyphBoundsPoints.minX) * scale).rounded(.down)) - padding
        let right = Int((Double(glyphBoundsPoints.maxX) * scale).rounded(.up)) + padding
        let bottom = Int((Double(glyphBoundsPoints.minY) * scale).rounded(.down)) - padding
        let top = Int((Double(glyphBoundsPoints.maxY) * scale).rounded(.up)) + padding

        return TextMetrics(
            scale: scale,
            advancePixels: max(1, pixels(advancePoints, scale: scale)),
            lineHeightPixels: max(1, pixels(ascentPoints + descentPoints + leadingPoints, scale: scale)),
            ascentPixels: pixels(ascentPoints, scale: scale),
            cellWidthPixels: right - left,
            cellHeightPixels: top - bottom,
            cellOriginOffsetX: left,
            // Core Text's y is up and the surface's is down, so the cell's top is `top` pixels ABOVE
            // the baseline.
            cellOriginOffsetY: -top,
            capHeightPoints: capHeightPoints
        )
    }

    /// Points to whole pixels, rounding to nearest (FR-009).
    static func pixels(_ points: Double, scale: Double) -> Int {
        Int((points * scale).rounded())
    }

    /// The glyphs for U+0020…U+007E, in code order. Setup-time only.
    static func printableGlyphs(of font: CTFont) -> [CGGlyph] {
        let characters: [UniChar] = (GlyphAtlasBitmap.firstCode...GlyphAtlasBitmap.lastCode).map { UniChar($0) }
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        // A missing glyph comes back as 0 and draws as the font's .notdef box — visible, not silent.
        _ = CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count)
        return glyphs
    }
}
