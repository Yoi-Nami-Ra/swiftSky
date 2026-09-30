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

    /// The window's safe-area insets, in points (002 FR-006a). Zero almost everywhere on macOS; on iOS
    /// they keep content clear of the camera cutout and rounded corners, which matter in landscape.
    ///
    /// Carried here rather than in a separate event so an insets-only change is simply a `.resized`
    /// surface: the loop replaces the whole value, and nothing can observe half an update.
    public var safeAreaInsets: SurfaceInsets

    public init(
        widthPixels: UInt32,
        heightPixels: UInt32,
        backingScale: Double,
        safeAreaInsets: SurfaceInsets = .zero
    ) {
        self.widthPixels = widthPixels
        self.heightPixels = heightPixels
        self.backingScale = backingScale
        self.safeAreaInsets = safeAreaInsets
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

/// Distances from each edge of the surface, in points, that content must stay inside to be clear of
/// cutouts and rounded corners (002 FR-006a).
///
/// Points rather than pixels because that is what the platform reports and what callers place text
/// in; the text layout converts to pixels once, with the backing scale (002 research.md R3).
public struct SurfaceInsets: Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public static let zero = SurfaceInsets(top: 0, left: 0, bottom: 0, right: 0)

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}
