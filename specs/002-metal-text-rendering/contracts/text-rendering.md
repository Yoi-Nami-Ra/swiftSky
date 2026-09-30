# Contract: Text Rendering Interfaces

**Feature**: `002-metal-text-rendering` | **Date**: 2026-09-30

These are the new and changed seams between layers. Shapes are given as signatures; bodies belong
to implementation. Everything that 001's [layer-interfaces.md](../../001-metal-app-shell/contracts/layer-interfaces.md)
does not mention here is unchanged. That includes the dependency direction, which stays
`Platform → Rendering → Simulation`, with nothing new imported.

---

## Rendering layer: surface description (changed)

```swift
// RenderSurface.swift
public struct SurfaceInsets: Sendable, Equatable {
    public var top: Double, left: Double, bottom: Double, right: Double   // points
    public static let zero: SurfaceInsets
    public init(top: Double, left: Double, bottom: Double, right: Double)
}

public struct RenderSurface: Sendable, Equatable {
    public var widthPixels: UInt32
    public var heightPixels: UInt32
    public var backingScale: Double
    public var safeAreaInsets: SurfaceInsets          // NEW (FR-006a)
    public init(widthPixels: UInt32, heightPixels: UInt32, backingScale: Double,
                safeAreaInsets: SurfaceInsets = .zero)
    // isRenderable, aspectRatio: unchanged
}
```

**Platform obligation**: every `RenderSurface` the platform layer sends carries the window's current
safe-area insets. Any change to them is sent as `.resized(surface)` (research R8).

## Rendering layer: renderer (changed)

```swift
public final class Renderer {
    /// `textFont` is the 13-pt system monospaced font, resolved by the platform layer (research R1).
    /// Builds the text pipeline and buffers. The atlas waits for the first frame, where the backing
    /// scale is known (research R8). Text setup failures do NOT throw (FR-018): they are logged, and
    /// the renderer runs without text.
    public init(device: any MTLDevice, pixelFormat: MTLPixelFormat, textFont: CTFont) throws

    /// True when text setup succeeded. False after a logged FR-018 failure.
    public var isTextAvailable: Bool { get }

    #if SWIFTSKY_INSTRUMENTATION
    /// Set once, before the loop starts. `nil` means no debug text, the default.
    public var debugTextPattern: DebugTextPattern?
    #endif

    /// Unchanged signature and semantics, with these additions:
    /// - it builds the atlas and `TextBuffer` on the first renderable frame, and rebuilds the atlas when
    ///   `surface.backingScale` differs from the atlas scale, handing the buffer the new metrics (FR-004, FR-010);
    /// - when a debug pattern is set, it writes the pattern and then draws the text on top of the quad;
    /// - it returns `false` when no instance-ring slot is free (research R5), and never blocks;
    /// - with no characters to draw, it takes no slot at all, so text-free frames are unaffected.
    @discardableResult
    /// `timestamp` is the frame's `targetTimestamp`, already read once per frame by the loop (001 FR-033),
    /// passed in so the debug FPS needs no second clock read (FR-014). CHANGED from 001's signature.
    public func render(state: SimulationState, surface: RenderSurface,
                       drawable: any CAMetalDrawable, timestamp: Double) -> Bool
}
```

`RendererError` is unchanged. No text failure maps to it.

## Rendering layer: text API (new)

Public, because it is the capability this feature ships (FR-016) and the surface SKY-29 will write
through. It is pure and Metal-free, so it is testable headlessly (FR-019).

```swift
public struct TextMetrics: Sendable, Equatable {
    public let scale: Double
    public let advancePixels: Int
    public let lineHeightPixels: Int
    public let cellWidthPixels: Int
    public let cellHeightPixels: Int
    public let cellOriginOffsetX: Int
    public let cellOriginOffsetY: Int
    public let capHeightPoints: Double
    public static func make(font: CTFont, scale: Double) -> TextMetrics
}

@frozen public struct GlyphInstance: Equatable {   // 8 bytes, mirrored in Shaders.metal
    public var x: UInt16, y: UInt16, cell: UInt16, padding: UInt16
}

public final class TextBuffer {
    public static let capacity = 1_024
    public init(metrics: TextMetrics)                // created once, on the first frame drawn

    public var metrics: TextMetrics                  // replaced by the renderer on a scale change
    public var count: Int { get }
    public var remainingCapacity: Int { get }
    public var didOverflow: Bool { get }
    public var instances: UnsafeBufferPointer<GlyphInstance> { get }   // first `count` only

    public func clear()
    /// Pen to `point` (in points, from the surface's top-left), snapped to whole pixels (FR-009).
    public func begin(at point: (x: Double, y: Double))
    public func newline()

    // All of the following allocate nothing (FR-012, FR-013). `limit` caps how many characters are
    // written, for exact fills (FR-015a).
    public func write(_ text: StaticString, limit: Int = .max)
    public func write(_ value: UInt64, minimumDigits: Int = 1, limit: Int = .max)
    /// Grapheme-exact FR-003 handling. Intended for tests and non-ASCII input, not the hot path.
    public func write(_ text: String, limit: Int = .max)
}

public struct GlyphAtlasBitmap {                     // CPU only. The texture upload is internal.
    public static let columns = 16, rows = 6
    public let metrics: TextMetrics
    public let widthPixels: Int, heightPixels: Int
    public let bytes: [UInt8]                        // row-major, one byte per pixel
    public static func make(font: CTFont, scale: Double) throws -> GlyphAtlasBitmap
    public static func cell(for asciiCode: UInt8) -> UInt16   // non-printable → '?' cell
}

public enum TextRenderingError: Error, Sendable, Equatable {
    case bitmapContextUnavailable
    case atlasTextureUnavailable
    case pipelineUnavailable(underlying: String)
    case bufferUnavailable
}
```

## Rendering layer: debug pattern (new, `SWIFTSKY_INSTRUMENTATION` only)

```swift
#if SWIFTSKY_INSTRUMENTATION
public final class DebugTextPattern {
    public enum Mode: Sendable { case testString, fill }
    public init(mode: Mode)
    /// Frames drawn in the past second, updated once a second; `nil` before the first full second.
    public private(set) var framesPerSecond: UInt64?
    /// Counts the frame for FPS, then writes one frame's text, 8 pt in from the safe-area top-left
    /// (FR-006b). `.fill` stops at exactly `TextBuffer.capacity` and never sets `didOverflow` (FR-015a).
    public func write(into buffer: TextBuffer, surface: RenderSurface, timestamp: Double)
}
#endif
```

## Platform layer (changed)

| Where | Change |
|-------|--------|
| `MetalSurfaceView.currentSurface` | includes `safeAreaInsets`: `window?.safeAreaInsets` on iOS, the view's `safeAreaInsets` on macOS |
| `MetalSurfaceView` (iOS) | overrides `safeAreaInsetsDidChange()` to report the new geometry |
| `GameSurfaceView.buildSetup()` | resolves the `CTFont` (research R1). Under `SWIFTSKY_INSTRUMENTATION` it also parses the launch arguments into `DebugTextMode` and sets `renderer.debugTextPattern` before the loop starts. |
| `FrameLoop` | passes the frame's `targetTimestamp` (`now`) to `Renderer.render` |

## Launch arguments (new, Debug and Profiling builds only)

| Argument | Effect |
|----------|--------|
| *(none)* | no text. The surface stays uniformly black, as in 001. |
| `--debug-text` | the test string (FR-014, FR-015) |
| `--debug-text-fill` | exactly 1,024 changing characters (FR-015a). It wins over `--debug-text`. |

In Release, the code that reads these arguments is not compiled, so they have no effect
(FR-015, FR-015a, SC-006).

## Shaders (added to `Shaders.metal`)

| Function | Inputs | Output |
|----------|--------|--------|
| `text_vertex` | `vertex_id` 0–3, `instance_id`; `GlyphInstance` buffer at index 0; uniforms (viewport pixels, cell pixels, atlas grid) through `setVertexBytes` at index 1 | clip-space position and atlas texel coordinates |
| `text_fragment` | `r8Unorm` atlas, **nearest** sampler | premultiplied `(a, a, a, a)`, where `a = srgbToLinear(coverage)` (research R4) |

The pipeline blends with `one` / `oneMinusSourceAlpha`. It is created once at startup, alongside the
001 quad pipeline, and is never rebuilt, even on a scale change: only the atlas texture is.
