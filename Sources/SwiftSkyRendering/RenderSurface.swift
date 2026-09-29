/// The drawable region the renderer presents into.
///
/// Supplied by the platform layer, consumed here. The renderer knows only the dimensions — never what
/// kind of window, view, or scene they came from (FR-014). That is what lets the same rendering code
/// serve a resizable Mac window and a full-screen iOS surface without branching.
///
/// A value type, so it crosses from the main thread into the frame loop's isolation domain by copy,
/// with no annotation required (FR-030, FR-012d).
public struct RenderSurface: Sendable, Equatable {
    /// Drawable width in device pixels.
    public var widthPixels: UInt32

    /// Drawable height in device pixels.
    public var heightPixels: UInt32

    /// Points-to-pixels factor of the hosting display. Changes when the surface moves between
    /// displays of differing density, which must update the drawable dimensions to match.
    public var backingScale: Double

    public init(widthPixels: UInt32, heightPixels: UInt32, backingScale: Double) {
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.backingScale = backingScale
    }

    /// Whether this surface can be drawn into at all.
    ///
    /// A zero-area surface is a real, routine state — it occurs mid-resize, when a window collapses,
    /// and during teardown. The loop must skip drawing rather than attempt to draw into it.
    public var isRenderable: Bool {
        widthPixels > 0 && heightPixels > 0
    }

    /// Aspect ratio is deliberately unconstrained. Any legal size must be filled, including
    /// portrait-shaped sizes handed to a landscape-only app under iPad multitasking (FR-006b).
    public var aspectRatio: Double? {
        guard isRenderable else { return nil }
        return Double(widthPixels) / Double(heightPixels)
    }
}
