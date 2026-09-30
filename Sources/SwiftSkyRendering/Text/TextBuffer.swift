/// A fixed-capacity, reusable store of laid-out text: up to 1,024 characters, each already placed in
/// surface pixels (FR-011).
///
/// Text is laid out as it is written — there is no separate "characters, then layout" pass — so what
/// the renderer reads is exactly what it copies to the GPU. The store is allocated once and never
/// grows, and none of the per-frame write paths (`StaticString` and `UInt64`) allocate, so text can
/// change every frame for free (FR-012, FR-013). Pure Swift with no Metal, which is what lets FR-019's
/// tests run without a GPU.
///
/// A frame's text is written as `clear()` → `begin(at:)` → `write(…)` / `newline()` → read.
public final class TextBuffer {
    public static let capacity = 1_024

    /// Pixel metrics for the current backing scale. The renderer replaces them on a scale change;
    /// already-written instances are not re-laid-out, which is fine because every frame rewrites them.
    public var metrics: TextMetrics

    /// Characters stored. Line feeds are never stored, so they never count (FR-011).
    public private(set) var count = 0

    /// True once any character has been dropped for want of capacity, until the next `clear()`.
    public private(set) var didOverflow = false

    public var remainingCapacity: Int { Self.capacity - count }

    /// The stored characters, in write order.
    public var instances: UnsafeBufferPointer<GlyphInstance> {
        UnsafeBufferPointer(rebasing: storage[0..<count])
    }

    private let storage: UnsafeMutableBufferPointer<GlyphInstance>

    /// Pen position in surface pixels: `penY` is the baseline, `lineLeft` the edge a line feed
    /// returns to.
    private var penX = 0
    private var penY = 0
    private var lineLeft = 0

    public init(metrics: TextMetrics) {
        self.metrics = metrics
        storage = .allocate(capacity: Self.capacity)
        storage.initialize(repeating: GlyphInstance(x: 0, y: 0, cell: 0))
    }

    deinit {
        storage.deallocate()
    }

    /// Empties the store and clears `didOverflow`. Keeps the allocation.
    public func clear() {
        count = 0
        didOverflow = false
        penX = 0
        penY = metrics.ascentPixels
        lineLeft = 0
    }

    /// Starts a block of text with its first line's top-left at `point`, given in points from the
    /// surface's top-left. Snapped to whole pixels (FR-009).
    public func begin(at point: (x: Double, y: Double)) {
        lineLeft = TextMetrics.pixels(point.x, scale: metrics.scale)
        penX = lineLeft
        penY = TextMetrics.pixels(point.y, scale: metrics.scale) + metrics.ascentPixels
    }

    /// Moves the pen back to the block's left edge, one line down (FR-005).
    public func newline() {
        penX = lineLeft
        penY += metrics.lineHeightPixels
    }

    /// Writes an ASCII literal. The per-frame path: iterates UTF-8 bytes and allocates nothing.
    ///
    /// Non-ASCII in a literal is handled per scalar rather than per grapheme — a UTF-8 lead byte becomes
    /// one `?` and its continuation bytes are skipped (research.md R6). Use `write(_: String)` when
    /// grapheme-exact FR-003 behaviour matters.
    ///
    /// - Parameter limit: the most characters to write. Line feeds do not count.
    public func write(_ text: StaticString, limit: Int = .max) {
        text.withUTF8Buffer { bytes in
            var written = 0
            var index = 0
            while index < bytes.count, written < limit {
                let byte = bytes[index]
                index += 1
                switch byte {
                case 0x0A:
                    newline()
                case 0x0D where index < bytes.count && bytes[index] == 0x0A:
                    // CRLF is one line feed, as it is for `String`.
                    newline()
                    index += 1
                case 0x80..<0xC0:
                    continue
                default:
                    let cell = byte >= 0xC0 ? GlyphAtlasBitmap.replacementCell : GlyphAtlasBitmap.cell(for: byte)
                    guard place(cell) else { return }
                    written += 1
                }
            }
        }
    }

    /// Writes a whole number in decimal, zero-padded to `minimumDigits`. Never truncates digits:
    /// a number wider than the padding is written in full (FR-013). Allocates nothing.
    public func write(_ value: UInt64, minimumDigits: Int = 1, limit: Int = .max) {
        // UInt64.max has 20 digits. Digits are produced least-significant first into a stack tuple.
        var digits: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                     UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        withUnsafeMutableBytes(of: &digits) { buffer in
            var remaining = value
            var digitCount = 0
            repeat {
                buffer[digitCount] = UInt8(remaining % 10)
                remaining /= 10
                digitCount += 1
            } while remaining > 0

            var written = 0
            var padding = minimumDigits - digitCount
            while padding > 0, written < limit {
                guard place(GlyphAtlasBitmap.cell(for: UInt8(ascii: "0"))) else { return }
                padding -= 1
                written += 1
            }
            var position = digitCount
            while position > 0, written < limit {
                position -= 1
                guard place(GlyphAtlasBitmap.cell(for: UInt8(ascii: "0") + buffer[position])) else { return }
                written += 1
            }
        }
    }

    /// Writes `value` rounded half away from zero to exactly two decimal places — `8.33`, `1234.50` —
    /// right-aligned in `width` columns with leading spaces. A number wider than `width` is written in
    /// full, never cut short, and never in exponent notation (003 FR-007). Allocates nothing.
    ///
    /// Frame times are never negative or NaN, but a formatter must not trap on them: both write as
    /// `0.00`. Values too large for a `UInt64` count of hundredths are clamped to the largest one.
    public func writeHundredths(_ value: Double, width: Int = 0, limit: Int = .max) {
        let hundredths: UInt64
        if !(value > 0) {
            hundredths = 0
        } else if value * 100 >= Self.largestHundredths {
            hundredths = .max
        } else {
            hundredths = UInt64((value * 100).rounded(.toNearestOrAwayFromZero))
        }
        let whole = hundredths / 100

        // Digits of the whole part, plus "." and two decimals.
        var digits = 1
        var remaining = whole / 10
        while remaining > 0 {
            digits += 1
            remaining /= 10
        }

        var written = writeSpaces(width - (digits + 3), limit: limit)
        guard written < limit else { return }
        write(whole, limit: limit - written)
        written += digits
        guard written < limit else { return }
        write(".", limit: limit - written)
        written += 1
        guard written < limit else { return }
        write(hundredths % 100, minimumDigits: 2, limit: limit - written)
    }

    /// Writes an ASCII literal right-aligned in `width` columns with leading spaces — the overlay's
    /// `--` placeholder, which has to line up with the numbers it stands in for. Allocates nothing.
    public func writePadded(_ text: StaticString, width: Int, limit: Int = .max) {
        let written = writeSpaces(width - text.utf8CodeUnitCount, limit: limit)
        guard written < limit else { return }
        write(text, limit: limit - written)
    }

    /// `Double(UInt64.max)`, the first hundredths count that no longer fits. Anything at or above it
    /// is clamped rather than trapping in the conversion.
    private static let largestHundredths = Double(UInt64.max)

    /// Writes `count` spaces, at most `limit`, and returns how many were written.
    private func writeSpaces(_ count: Int, limit: Int) -> Int {
        var written = 0
        while written < count, written < limit {
            guard place(GlyphAtlasBitmap.cell(for: UInt8(ascii: " "))) else { return written }
            written += 1
        }
        return written
    }

    /// Writes any string with grapheme-exact FR-003 handling: `"\n"` and `"\r\n"` are line feeds, a
    /// single printable ASCII scalar is itself, and every other character is one `?`.
    ///
    /// Not for the per-frame path — iterating `Character`s is not guaranteed allocation-free. Intended
    /// for tests and non-ASCII input.
    public func write(_ text: String, limit: Int = .max) {
        var written = 0
        for character in text {
            guard written < limit else { return }
            if character == "\n" || character == "\r\n" {
                newline()
                continue
            }
            let cell: UInt16
            if character.unicodeScalars.count == 1, let ascii = character.asciiValue {
                cell = GlyphAtlasBitmap.cell(for: ascii)
            } else {
                cell = GlyphAtlasBitmap.replacementCell
            }
            guard place(cell) else { return }
            written += 1
        }
    }

    /// Stores one character at the pen and advances it. Returns `false`, and records the overflow, when
    /// the store is full.
    @inline(__always)
    private func place(_ cell: UInt16) -> Bool {
        guard count < Self.capacity else {
            didOverflow = true
            return false
        }
        storage[count] = GlyphInstance(
            x: Self.clamped(penX + metrics.cellOriginOffsetX),
            y: Self.clamped(penY + metrics.cellOriginOffsetY),
            cell: cell
        )
        count += 1
        penX += metrics.advancePixels
        return true
    }

    /// Instances store unsigned 16-bit pixels. Anything outside is clamped; such a glyph is off the
    /// surface's visible area in practice, and the GPU clips it (FR-005, data-model.md).
    @inline(__always)
    static func clamped(_ value: Int) -> UInt16 {
        UInt16(clamping: value)
    }
}
