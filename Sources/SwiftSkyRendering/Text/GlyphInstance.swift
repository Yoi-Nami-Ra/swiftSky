/// One character to draw: where its quad goes and which atlas cell it shows.
///
/// Exactly 8 bytes, and its layout is mirrored by `swiftsky::GlyphInstance` in `Shaders.metal`. The two
/// must stay byte-for-byte identical — the renderer copies an array of these straight into a GPU buffer
/// and the vertex shader indexes it by instance. A test pins the size and stride
/// (002 data-model.md).
///
/// Coordinates are already in surface pixels and already snapped to whole pixels (002 FR-009), so the
/// shader does no rounding and every glyph texel lands on exactly one surface pixel.
@frozen
public struct GlyphInstance: Equatable, Sendable {
    /// Left edge of the glyph quad, in surface pixels.
    public var x: UInt16

    /// Top edge of the glyph quad, in surface pixels, measured downwards from the top of the surface.
    public var y: UInt16

    /// Atlas cell, 0–94: the character code minus 0x20.
    public var cell: UInt16

    /// Keeps the struct at 8 bytes with natural alignment. Always zero.
    public var padding: UInt16

    public init(x: UInt16, y: UInt16, cell: UInt16) {
        self.x = x
        self.y = y
        self.cell = cell
        self.padding = 0
    }
}
