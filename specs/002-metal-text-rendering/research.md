# Phase 0 Research: Metal Text Rendering

**Feature**: `002-metal-text-rendering` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

This resolves the API-level choices the spec leaves to planning. Each entry gives the decision, why,
and what was rejected. API claims were checked against the macOS 27 SDK headers shipped with
Xcode 27 (`CoreText.framework/Headers/CTFont.h`, `AppKit.framework/Headers/NSFont.h`) rather than
from memory. Where a claim could only be settled by running code, it is marked **verify during
implementation** and has a named check in [quickstart.md](./quickstart.md).

---

## R1. Where the monospaced system font comes from (FR-002)

**Decision**: The **platform layer** resolves the font, using `NSFont.monospacedSystemFont(ofSize: 13,
weight: .regular)` on macOS and `UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)` on iOS.
Both are toll-free bridged to `CTFont`, which is passed to the renderer at construction time. The
rendering layer uses only Core Text and Core Graphics, never AppKit or UIKit.

**Rationale**: Core Text has no public call for the system *monospaced design* font. The SDK's
`CTFontUIFontType` offers `kCTFontUIFontUserFixedPitch`, but that is the user's chosen fixed-pitch
font. It can be changed in system settings, and it is historically Menlo or Courier rather than the
system monospaced design. The AppKit and UIKit calls are the supported way to get the system
monospaced font, and those frameworks belong in the platform layer (Principle I). Passing a `CTFont`
keeps the renderer free of them.

**Alternatives considered**:
- **`CTFontCreateUIFontForLanguage(.userFixedPitch, …)` in the renderer**: rejected. It depends on
  user settings, so the look is not deterministic, and it is not the system monospaced design.
- **Renderer imports AppKit/UIKit behind `#if os(...)`**: rejected. That puts UI frameworks inside
  the rendering layer, against Principle I and 001's layer contract.
- **Bundled font file**: forbidden by FR-002.

## R2. Rasterising the glyph images (FR-003, FR-004, FR-009)

**Decision**: Draw the 95 printable ASCII glyphs once, on the CPU, into one 8-bit grayscale Core
Graphics bitmap laid out as a 16 × 6 grid of equal cells, then upload it to an `r8Unorm` texture:
- **Drawing**: white on black, with `CTFontDrawGlyphs`. Anti-aliasing is on; font smoothing,
  subpixel positioning and subpixel quantisation are off, so each glyph is drawn at a whole-pixel
  position.
- **Cell size**: the union of all 95 glyph bounding boxes at the current scale, rounded out to whole
  pixels, plus 1 px of padding on each side, so no glyph bleeds into its neighbour's cell.
- **Replacement glyph**: `?` (FR-003) reuses the `?` cell rather than taking a separate one.
- **Texture storage**: the platform default storage mode, managed on macOS and shared on iOS. The
  texture is filled with `replace(region:mipmapLevel:withBytes:bytesPerRow:)`, which works in both
  modes with no `#if`.

**Rationale**: 95 glyphs at 13 pt make a tiny image. At 3× a cell is about 26 × 50 px, so the atlas is
about 416 × 300 px, roughly 125 KB (see R11). Building the bitmap on the CPU separately from the
texture upload means bitmap construction can be tested headlessly with Core Text alone, with no GPU
(R7). That is what makes SC-007's "distinct glyph" claim testable automatically.

**Alternatives considered**:
- **A signed distance field atlas**: rejected (Principle V). It pays off only across many sizes, and
  this feature has one.
- **Rasterising on demand per character**: rejected. That would rebuild glyph images per frame
  (FR-004).
- **Shared-mode textures on macOS**: rejected. They are not available on the Intel, discrete-GPU
  baseline Mac (001 R2), and the default storage mode needs no branching.

## R3. Pixel-grid alignment (FR-009, SC-001)

**Decision**: Every metric is converted to whole physical pixels once per backing scale:
- **Rounding**: the advance width becomes `round(advance × scale)` and the line height becomes
  `round((ascent + descent + leading) × scale)`. The baseline offset within a cell is rounded to a
  whole pixel.
- **Origins**: a string's origin in points is converted as `round(point × scale)`.
- **Drawing**: each glyph quad is exactly one atlas cell in pixels, sampled with **nearest**
  filtering. One atlas texel therefore lands on exactly one surface pixel, and nothing is resampled.

**Consequence**: a line's total width may differ from the system's own text by up to half a pixel per
character, because the advance is rounded. SC-001 compares glyph shapes and stroke weight, not string
width, so this is acceptable. It is noted here so a reviewer is not surprised.

**Alternatives considered**: fractional advances with linear filtering. Rejected, because that is
exactly the resampling FR-009 forbids and the blur SC-001 checks for.

## R4. Coverage and blending on an sRGB surface (FR-007, SC-001)

**Decision**: The text pipeline blends premultiplied white with blend factors `one` and
`oneMinusSourceAlpha`. The fragment shader converts the atlas coverage `c` to `a = srgbToLinear(c)`
and outputs `(a, a, a, a)`.

**Rationale**: 001's surface is `bgra8Unorm_srgb` (001 R10), so the GPU blends in linear space.
Core Graphics wrote the coverage values as if blending in encoded space. Used unconverted, anti-aliased
edges would come out visibly brighter than the system's own text, which makes glyphs look bolder and
would fail SC-001's stroke-weight comparison. Over black, which is the only background in this
feature, the conversion reproduces Core Graphics' result exactly. Over other colours, which later
features may draw, it is a close approximation. This is one line of shader code.

**Alternatives considered**: using coverage as alpha directly. That is simpler, but text looks too
bold on this surface, so it was rejected.

## R5. The per-frame data path (FR-011, FR-012, SC-003)

**Decision**: One pipeline state, one instanced draw:
- **Draw**: one instance per character, with `drawPrimitives(type: .triangleStrip, vertexStart: 0,
  vertexCount: 4, instanceCount: n)`. Nothing is drawn when `n == 0`.
- **Instance data**: a `GlyphInstance` of 8 bytes, holding the pixel origin (two `UInt16`), the atlas
  cell index (`UInt16`) and padding. The vertex shader expands the unit quad from the instance and a
  small uniform struct of viewport and cell size in pixels, passed with `setVertexBytes`.
- **Storage**: a ring of **3** instance buffers, each `.storageModeShared` with room for 1,024
  instances (8 KB each), all created at startup.
- **Frames in flight**: a `DispatchSemaphore(value: 3)` limits them. It is taken with a **zero
  timeout** and signalled from a completion handler stored once on the renderer as a
  `@convention(block)` value, so no closure is created per frame.
- **Buffer unavailable**: if no ring slot is free, the frame is **skipped** (`render` returns `false`).
  This matches 001 FR-027a's handling of a missing drawable, and it is counted by the existing
  skipped-frame instrumentation. With the layer's default of three drawables, a free drawable already
  implies that a slot is free, so this never happens in practice. Any occurrence shows up in SC-003's
  skipped-frame count rather than hiding.
- **No text**: when the buffer holds no characters, no slot is taken. Frames without text, which
  includes every Release frame, never touch the semaphore.
- **As built**: the slot is taken by `TextRenderer.acquireSlot()` in `Renderer.render` **before**
  the command buffer is created, so running out of slots skips the frame before any GPU work.
  `releaseUnusedSlot()` returns the slot if command-buffer creation then fails. `encode(_:slot:…)`
  only copies and draws. This replaces the single `encode(…) -> Bool` sketched earlier.
- **Per-frame work**: a `memcpy` of `count × 8` bytes from the CPU-side `TextBuffer` (R6) into the
  slot's buffer, then one draw.

**Rationale**: the CPU writes new text every frame while the GPU may still be reading the previous
frames. A single buffer would race. A ring bounded by an explicit semaphore is the standard remedy,
and a zero-timeout wait keeps 001's rule that the loop never blocks.

**Alternatives considered**:
- **`setVertexBytes` for the instance data**: rejected. At full capacity the data is 8 KB, which is
  over Metal's 4 KB guidance. Packing each instance to 4 bytes would land exactly on the limit and
  cap pixel coordinates at 13 bits.
- **One buffer with no synchronisation**: rejected. It is a data race, even though the symptom would
  only be flickering debug text.
- **A blocking semaphore wait**: rejected. 001 FR-027a says the loop never blocks.
- **Relying on the drawable count alone**: rejected. It works, but it depends on a layer setting that
  the platform layer owns and could change. The explicit semaphore makes the invariant the renderer's
  own.
- **Six vertices per character, no instancing**: rejected. It needs 12 times more per-frame data for
  no benefit.

**Verify during implementation**: that passing the stored block to `addCompletedHandler` allocates
nothing on our side. SC-003's Allocations run is the check. If it does allocate, fall back to relying
on the drawable count, and record that in Complexity Tracking.

## R6. Where layout lives, and its API (FR-005, FR-013, FR-019)

**Decision**: Text layout lives in the **rendering layer**, because glyph placement is a presentation
concern and not simulation state (001 FR-012b). It is written as pure Swift that does not use Metal.
- **`TextBuffer`**: a `final class` holding a fixed-capacity `GlyphInstance` store, allocated once in
  `init` with `UnsafeMutableBufferPointer` and freed in `deinit`. It also holds a cursor and the
  current `TextMetrics`.
- **Writes**: `begin(at:)`, `write(_: StaticString)`, `write(_: String)`,
  `write(_: UInt64, minimumDigits:)` and `newline()` lay characters out immediately, as instances in
  pixel space.
- **`remainingCapacity`** lets a writer fill the buffer exactly.
- **`didOverflow`** is set when a write drops characters.

**Character handling (FR-003)**:
- **`write(String)`** iterates `Character`s. A Character that is a single scalar from U+0020 to
  U+007E becomes that glyph. `"\n"` and `"\r\n"` become a line feed. Anything else becomes `?`.
- **`write(StaticString)`** iterates UTF-8 bytes and is the path used every frame. Printable ASCII
  bytes map to glyphs. A UTF-8 lead byte (`0xC0` and above) becomes one `?`, and continuation bytes
  are skipped. This is per scalar rather than per grapheme, which only matters for non-ASCII
  literals. Non-ASCII input in this feature arrives through `String`, which follows FR-003 exactly.
- **`write(UInt64, minimumDigits:)`** extracts digits into a fixed 20-byte tuple on the stack, and
  never uses `String(describing:)` (FR-013).

**Rationale**: keeping layout Metal-free and CPU-only is what makes FR-019 hold. Laying out on write,
rather than storing characters and laying them out later, means one pass and one store.

**Alternatives considered**:
- **A fifth, Metal-free `SwiftSkyText` package target**: rejected (Principle V). A test target on
  `SwiftSkyRendering` gets the same headless testability without adding a layer.
- **Layout in the logic layer**: rejected. It would put presentation into `SwiftSkySimulation`
  (Principle I).

## R7. Headless tests for the rendering layer (FR-019, SC-007, SC-008)

**Decision**: Add a `SwiftSkyRenderingTests` Swift Testing target that depends on `SwiftSkyRendering`
only. It covers `TextBuffer` layout, metric rounding at 1×, 2× and 3×, the test pattern's content and
line lengths, exact-capacity fill without overflow, and the CPU atlas bitmap. The bitmap tests use a
system fixed-pitch `CTFont` created in the test (`CTFontCreateUIFontForLanguage(.userFixedPitch, 13,
nil)`) and check that every printable glyph other than space leaves ink, and that no two glyphs'
images are identical.

**Headless guarantee**: the tests never create an `MTLDevice`. `Scripts/verify.sh` gains one guard
stage, which fails if `MTLCreateSystemDefaultDevice` or `makeTexture`/`makeBuffer` appears under
`Tests/`. The existing `swift test` stage already runs every test target, so no other change to the
script is needed.

**Rationale**: Principle II exempts purely visual code, but layout and atlas packing are logic with
real edge cases. Linking Metal is not a GPU dependency. Creating a device would be, and the guard
keeps that from slipping in.

## R8. Safe-area insets and backing-scale changes (FR-006a, FR-010)

**Decision**:
- **`RenderSurface`** gains `safeAreaInsets: SurfaceInsets`, a value type holding top, left, bottom
  and right in **points**. It keeps `Sendable, Equatable`, so 001 FR-030's transfer-by-value still
  holds. No new `SurfaceEvent` case is needed, because an insets-only change is sent as
  `.resized(surface)`.
- **iOS**: `MetalSurfaceView` reads `window?.safeAreaInsets` when it builds `currentSurface`, and
  reports it from `layoutSubviews` and an added `safeAreaInsetsDidChange` override. It reads the
  **window's** insets because the SwiftUI host applies `.ignoresSafeArea()` (001 FR-003), which can
  zero the view's own insets while the window's stay correct.
- **macOS**: the view's `safeAreaInsets`, which is non-zero only in full screen on a display with a
  camera housing, is read in the same place. It is refreshed by the existing `setFrameSize`, which
  fires on entering and leaving full screen.
- **First frame**: the renderer is built on the main thread before any surface exists (001
  contracts/frame-loop.md), so the backing scale is unknown in `init`. The pipeline, ring buffers and
  semaphore are therefore created in `init`. The atlas, the metrics and the `TextBuffer` are built on
  the **first renderable frame**, at that frame's scale. That is a one-off allocation, like a scale
  change.
- **Scale change**: the renderer compares `surface.backingScale` with the atlas's scale once per frame
  (one `Double` comparison). It has no atlas before the first frame, so the first frame always takes
  this path. On a mismatch it rebuilds the atlas and metrics synchronously on the loop thread, and
  gives the existing `TextBuffer` the new metrics. The rebuild happens on the loop thread, which takes a few milliseconds for 95 glyphs and so easily meets FR-010's one second. This
  one-off rebuild allocates, which FR-010 allows. If it fails, text is disabled and logged (FR-018).
  In-flight frames keep the old texture alive through the command buffer's own retain.

**Verify during implementation**: that `window.safeAreaInsets` is non-zero in landscape on a device
with a camera cutout, even with the SwiftUI host ignoring the safe area (quickstart check 8).

## R9. Launch opt-ins (FR-015, FR-015a, FR-016)

**Decision**: Two launch arguments, read **once** in the platform layer while building the renderer:
- **`--debug-text`**: draws the test string.
- **`--debug-text-fill`**: fills the full capacity. It wins if both are given.

Both the parsing, in the platform layer, and the `DebugTextPattern` type, in the rendering layer,
are compiled only under the existing `SWIFTSKY_INSTRUMENTATION` condition. In Release the arguments
are not ignored by a runtime check: the code that could read them does not exist. The text capability
itself (`TextBuffer`, the atlas and the pipeline) is compiled unconditionally (FR-016).

**How to pass them**:
- **Xcode**: Scheme → Run → Arguments.
- **macOS command line**: `open swiftSky.app --args --debug-text`.
- **iOS device**: `xcrun devicectl device process launch --device <id> <bundle-id> --debug-text`.
- **Simulator**: `xcrun simctl launch booted <bundle-id> --debug-text`.

**Alternatives considered**:
- **Environment variables**: rejected. They are harder to set on a physical iOS device.
- **`UserDefaults`**: rejected. The setting would persist, so a debug mode could silently stay on
  across launches.
- **A single `-SwiftSkyDebugText test|fill` default**: rejected. It is read through the persistent
  defaults domain, with the same risk.

Double-dash arguments are not interpreted by AppKit's argument domain, so they cannot collide with it.

## R10. Verifying 1× on macOS (SC-001)

**Decision**: The preferred setup is a standard-resolution external display. The fallback is Finder →
Get Info → **Open in Low Resolution** on the built app, which gives the window a backing scale of 1.
Every atlas build logs one `notice` line at Debug and Profiling level, reading `text atlas scale=<s>
cell=<w>×<h>px capHeight=<pt>`. The cap height is the value that quickstart checks 5 to 7 measure
against. That lets the tester confirm that the scale really is 1 before taking the capture.
Captures use `screencapture -l <windowID> -o`.

**Verify during implementation**: whether a window capture of a low-resolution app is saved at 1×
backing resolution or upscaled. If it is upscaled, only the external-display route is valid for
SC-001's pixel measurement, and the quickstart says so.

## R11. Memory and cost budget (SC-004, SC-005, Principle III)

| Item | Size |
|------|------|
| Atlas texture at 3× (about 416 × 300 × 1 B) | ≈ 125 KB |
| Atlas texture at 2× (about 272 × 204 × 1 B) | ≈ 55 KB |
| Instance ring (3 × 1,024 × 8 B) | 24 KB |
| CPU `TextBuffer` (1,024 × 8 B) | 8 KB |
| Temporary CPU bitmap at build time (freed after upload) | ≤ 125 KB |
| **Steady-state total** | **< 200 KB**, against SC-005's 2 MB ceiling |

Per frame: one `memcpy` of at most 8 KB, one extra encoder state change, and one instanced draw of at
most 1,024 quads. That is negligible against a 16.6 ms or 8.3 ms budget, even on the Intel baseline.

**On SC-005's measurement**: 001's idle-memory baseline has still not been recorded, because the
baseline devices are pending (SKY-31, SKY-32). SC-005 therefore defines its +2 MB as a **delta on one
device**: idle footprint without text, then with `--debug-text-fill`, on the same
machine and build. That is valid on any hardware, because it is a difference rather than an absolute.

## R12. Failures that must not become renderer failures (FR-018)

**Decision**: Text setup has its own `TextRenderingError`, with these cases:
- `bitmapContextUnavailable`
- `atlasTextureUnavailable`
- `pipelineUnavailable(underlying:)`, when the text shader functions are missing or fail to compile
- `bufferUnavailable`

`Renderer.init` builds the text pipeline, ring buffers and semaphore with `do/catch`. On failure it
logs the case with `os.Logger` (subsystem `com.swiftsky.app`, category `text`, level `error`, in every
build) and continues with no text component. It never throws a `RendererError` for text, so 001's
failure notice cannot appear because of text. The atlas build on the first frame, and any rebuild
after a scale change (R8), take the same path: text is disabled, logged, and the frame is still
drawn.

**Overflow log (FR-011)**: when `didOverflow` first becomes true in a run, the renderer logs one
`notice` with a static message. That single log call is the only possible allocation on the frame
path, and it happens at most once per run. Filling exactly the capacity never sets the flag.

## R13. Test string and fill content (FR-014, FR-015a)

**Decision**:
- **Test string lines**:
  - Line 1 is U+0020 to U+0040 (33 characters).
  - Line 2 is U+0041 to U+0060 (32 characters).
  - Line 3 is U+0061 to U+007E (30 characters).
  - Line 4 is `fps ` followed by the frame rate, or `fps --` before the first full second.
- **Size**: at 2- or 3-digit rates the test string is 101 or 102 characters, excluding line feeds.
- **Width**: the widest line, 33 characters at about 7.8 pt, is about 258 pt wide. It fits the
  narrowest surface iOS can hand this landscape-only app, which is iPad Slide Over at about 320 pt
  (001 FR-006b).
- **FPS** *(changed during implementation, replacing a frames-drawn counter)*:
  - `DebugTextPattern` counts the frames it is written for across a window of at least 1 s, then
    sets the value to `round(frames ÷ elapsed)` and starts a new window.
  - A gap of more than 0.25 s between frames means the loop was paused, so the window restarts.
  - Time comes from the `targetTimestamp` the frame loop already reads once per frame, passed in
    through `Renderer.render(…, timestamp:)`, so there is no second clock read (001 FR-033).
  - It is never read from `SimulationState`.
  - The whole text is still rewritten every frame, so SC-003's per-frame write path is still
    exercised even when the displayed value has not changed.
- **Fill (`--debug-text-fill`)**: repeats the pattern downward from the same anchor, advancing one
  blank line between copies. Every copy shows the current FPS. It writes while
  `remainingCapacity > 0` and cuts the last copy short with a character-limited write, so it reaches
  exactly 1,024 characters without setting `didOverflow`.

## Open items deliberately left to implementation

- The exact union cell size, which depends on the system font's metrics on each OS version. It is
  measured, not assumed, and logged per R10.
- Whether `addCompletedHandler` with a stored block is allocation-free (R5).
- `window.safeAreaInsets` behaviour under the SwiftUI host (R8).
- Window-capture resolution for low-resolution apps (R10).

## Sources

- macOS 27 SDK headers: `CoreText.framework/Headers/CTFont.h` (`CTFontUIFontType`,
  `kCTFontUIFontUserFixedPitch`, `CTFontCreateUIFontForLanguage`), and
  `AppKit.framework/Headers/NSFont.h` (`monospacedSystemFontOfSize:weight:`, macOS 10.15+).
- 001 research: R2 (baseline devices), R10 (surface pixel format), R12 (instrumentation compilation
  condition).
- 001 sources: `Renderer.swift`, `MetalSurfaceView.swift`, `FrameLoop.swift`,
  `Instrumentation.swift`.
