import CoreGraphics
import CoreText

/// The 95 printable ASCII glyphs, drawn once on the CPU into a 16 × 6 grid of equal cells.
///
/// Built separately from the GPU texture it is uploaded to, so it can be tested headlessly with Core
/// Text alone — that is what lets SC-007's "every character is its own distinct glyph" be checked
/// automatically rather than by eye (research.md R2, R7).
///
/// One byte per pixel, row-major, top row first: white glyph coverage on black. Layout matches the
/// texture and the surface — y down — so cell (col, row) starts at pixel
/// (col × cellWidth, row × cellHeight).
public struct GlyphAtlasBitmap: Sendable {
    public static let columns = 16
    public static let rows = 6

    /// First and last supported character codes: space and tilde (FR-003).
    public static let firstCode: UInt8 = 0x20
    public static let lastCode: UInt8 = 0x7E
    public static let glyphCount = Int(lastCode - firstCode) + 1

    /// The replacement glyph is `?` itself, reusing its cell rather than adding a 96th (FR-003).
    public static let replacementCell = UInt16(UInt8(ascii: "?") - firstCode)

    public let metrics: TextMetrics
    public let widthPixels: Int
    public let heightPixels: Int
    public let bytes: [UInt8]

    /// The atlas cell for a character code. Anything outside space…tilde is the replacement glyph.
    @inline(__always)
    public static func cell(for asciiCode: UInt8) -> UInt16 {
        guard asciiCode >= firstCode, asciiCode <= lastCode else { return replacementCell }
        return UInt16(asciiCode - firstCode)
    }

    /// Rasterises every printable glyph of `font` at `scale`.
    ///
    /// Setup-time only (FR-004): it allocates the bitmap and the glyph arrays. Called on the first frame
    /// and on each backing-scale change, never on an ordinary frame.
    public static func make(font: CTFont, scale: Double) throws(TextRenderingError) -> GlyphAtlasBitmap {
        let metrics = TextMetrics.make(font: font, scale: scale)
        let width = columns * metrics.cellWidthPixels
        let height = rows * metrics.cellHeightPixels

        guard
            width > 0, height > 0,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            throw .bitmapContextUnavailable
        }

        // Grayscale anti-aliasing only. Font smoothing would add weight the GPU blend does not expect,
        // and subpixel positioning would put glyph edges between pixels — both defeat FR-009.
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(false)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSubpixelPositioning(false)
        context.setShouldSubpixelPositionFonts(false)
        context.setAllowsFontSubpixelQuantization(false)
        context.setShouldSubpixelQuantizeFonts(false)

        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(gray: 1, alpha: 1)

        // Draw with a copy of the font at pixel size, so glyph positions are whole pixels with no
        // context scaling in between.
        let pixelFont = CTFontCreateCopyWithAttributes(font, CTFontGetSize(font) * CGFloat(scale), nil, nil)
        let glyphs = TextMetrics.printableGlyphs(of: pixelFont)

        var positions = [CGPoint](repeating: .zero, count: glyphs.count)
        for index in 0..<glyphs.count {
            let column = index % columns
            let row = index / columns
            // The pen sits `-cellOriginOffset` inside the cell's top-left. Core Graphics' y is up from
            // the bottom of the bitmap, while its memory is top row first, hence the flip.
            let penX = column * metrics.cellWidthPixels - metrics.cellOriginOffsetX
            let baselineFromTop = row * metrics.cellHeightPixels - metrics.cellOriginOffsetY
            positions[index] = CGPoint(x: penX, y: height - baselineFromTop)
        }
        CTFontDrawGlyphs(pixelFont, glyphs, positions, glyphs.count, context)

        guard let data = context.data else { throw .bitmapContextUnavailable }
        let bytes = [UInt8](UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height))

        return GlyphAtlasBitmap(metrics: metrics, widthPixels: width, heightPixels: height, bytes: bytes)
    }

    /// The pixels of one cell, row by row. For tests: checking that cells carry ink and differ.
    func cellPixels(_ cell: Int) -> [UInt8] {
        let originX = (cell % Self.columns) * metrics.cellWidthPixels
        let originY = (cell / Self.columns) * metrics.cellHeightPixels
        var out: [UInt8] = []
        out.reserveCapacity(metrics.cellWidthPixels * metrics.cellHeightPixels)
        for y in originY..<(originY + metrics.cellHeightPixels) {
            let rowStart = y * widthPixels + originX
            out.append(contentsOf: bytes[rowStart..<(rowStart + metrics.cellWidthPixels)])
        }
        return out
    }
}
