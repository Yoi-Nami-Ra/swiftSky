# Data Model: Metal Text Rendering

**Feature**: `002-metal-text-rendering` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

Every entity here lives in the **rendering layer** (`SwiftSkyRendering`), except `DebugTextMode`,
which lives in the platform layer. Nothing is added to the logic layer (`SwiftSkySimulation`).
Signatures are in [contracts/text-rendering.md](./contracts/text-rendering.md).

**Mapping to the spec's Key Entities**:
- *Character set* is the 95 cells of `GlyphAtlas` (`GlyphAtlasBitmap.cell(for:)`).
- *Glyph images* is `GlyphAtlas`.
- *Font metrics* is `TextMetrics`.
- *Safe-area insets* is `SurfaceInsets`.
- *Text buffer* and *Laid-out text* are both `TextBuffer`, which lays text out as it is written and
  stores the result as `GlyphInstance`s.

---

## SurfaceInsets *(new, value type)*

The safe-area insets of the drawable surface, in **points**.

| Field | Type | Rule |
|-------|------|------|
| `top`, `left`, `bottom`, `right` | `Double` | ≥ 0. Zero is normal on macOS. |

- `Sendable, Equatable`. `.zero` is the default.

## RenderSurface *(extended from 001)*

| Field | Type | Change |
|-------|------|--------|
| `widthPixels`, `heightPixels` | `UInt32` | unchanged |
| `backingScale` | `Double` | unchanged |
| `safeAreaInsets` | `SurfaceInsets` | **new**, defaulting to `.zero`, so existing call sites and tests still compile |

- Still `Sendable, Equatable`, and still crosses to the loop thread by copy (001 FR-030).
- A change to the insets alone is reported as `SurfaceEvent.resized` (research R8).

## TextMetrics *(new, value type)*

The font's measurements, converted to whole pixels for one backing scale (research R3).

| Field | Type | Rule |
|-------|------|------|
| `scale` | `Double` | 1, 2 or 3 in practice. Any value > 0 is accepted. |
| `advancePixels` | `Int` | `round(advance × scale)`, ≥ 1 |
| `lineHeightPixels` | `Int` | `round((ascent + descent + leading) × scale)`, ≥ 1 |
| `cellWidthPixels`, `cellHeightPixels` | `Int` | the atlas cell size: union of glyph bounds, rounded out, plus 2 px |
| `cellOriginOffsetX`, `cellOriginOffsetY` | `Int` | from the pen position (baseline-left) to the cell's top-left, in pixels |
| `capHeightPoints` | `Double` | the font's cap height, recorded for SC-001's measurement |

- A pure value, derived from a `CTFont` and a scale. It is rebuilt only when the scale changes
  (FR-010).

## GlyphAtlas *(new)*

| Part | Where | Lifetime |
|------|-------|----------|
| `GlyphAtlasBitmap` | CPU: 8-bit grayscale bytes, a 16 × 6 grid of cells, plus `TextMetrics` | built on the first frame drawn and on each scale change, then discarded after upload |
| atlas texture | GPU: `r8Unorm`, the same size as the bitmap | lives until the next scale change |

- Cell index = character code − 0x20, from 0 to 94. The replacement glyph is the `?` cell, index
  0x3F − 0x20 = 31.
- **Invariants**, tested headlessly (research R7):
  - every cell except space (index 0) contains ink;
  - no two cells hold identical images;
  - the bitmap's scale equals `TextMetrics.scale`.

## GlyphInstance *(new, 8-byte POD)*

One drawn character. The same layout is used by Swift and by `Shaders.metal`.

| Field | Type | Meaning |
|-------|------|---------|
| `x`, `y` | `UInt16` | top-left of the glyph quad, in surface pixels, already snapped (FR-009) |
| `cell` | `UInt16` | atlas cell index, 0–94 |
| `padding` | `UInt16` | always 0 |

- `MemoryLayout<GlyphInstance>.size == 8` and `stride == 8`, asserted in a test.

## TextBuffer *(new, `final class`, fixed capacity)*

The reusable, per-frame text store (FR-011 to FR-013).

| State | Type | Rule |
|-------|------|------|
| `capacity` | `Int` | always 1,024 |
| `instances` | storage for 1,024 `GlyphInstance`s | allocated once in `init` and freed in `deinit`, never grown. The renderer creates the one `TextBuffer` on the first frame drawn and keeps it for the whole run, replacing only its `metrics` on a scale change. |
| `count` | `Int` | 0 to `capacity`. Line feeds are never stored. |
| `metrics` | `TextMetrics` | set by the renderer, and replaced on a scale change |
| cursor | pen position in pixels, plus the line's left edge | set by `begin(at:)`, advanced by writes |
| `didOverflow` | `Bool` | becomes true on the first dropped character, and stays true until `clear()` |

**Transitions per frame**: `clear()` → `begin(at:)` → `write(...)` / `newline()`, any number of
times → read by the renderer.

**Rules**:
- **Placement**: a character is placed at the pen position plus `cellOriginOffsetX/Y`. The pen then
  advances by `advancePixels`.
- **Line feed**: moves the pen back to the line's left edge and down by `lineHeightPixels`.
- **Mapping**: printable ASCII maps to its own cell. Anything else becomes the `?` cell (FR-003,
  research R6).
- **Capacity**: once `count == capacity`, every further character is dropped and `didOverflow`
  becomes true. `remainingCapacity == capacity − count`.
- **Clipping**: instances whose position is outside the surface are still stored. The GPU clips them
  (FR-005). A coordinate that falls outside `0...65535` is clamped.
- **Numbers**: `write(UInt64, minimumDigits:)` writes all the digits of values up to `UInt64.max`,
  with leading zeros up to `minimumDigits`, and never cuts digits (FR-013).

## DebugTextPattern *(new, Debug and Profiling builds only)*

Compiled under `SWIFTSKY_INSTRUMENTATION` (research R9).

| State | Type | Rule |
|-------|------|------|
| `mode` | `.testString` or `.fill` | fixed at construction |
| `framesPerSecond` | `UInt64?` | frames drawn in the past second, rounded, and updated once a second. `nil` until the first full second. Timed with the loop's per-frame timestamp, and never read from `SimulationState` (FR-014). |
| FPS window | start timestamp, frame count, last timestamp | the window restarts after a gap of more than 0.25 s (a pause) |

- `.testString` writes the four lines of research R13, 8 pt in from the top-left of the safe area
  (FR-006b).
- `.fill` repeats the same lines until exactly `capacity` characters are stored, and never sets
  `didOverflow` (FR-015a).

## DebugTextMode *(new, platform layer, Debug and Profiling builds only)*

Parsed once from the launch arguments: `none`, `testString` (`--debug-text`), or `fill`
(`--debug-text-fill`, which wins if both are given). The platform layer turns it into a
`DebugTextPattern` for the renderer.

## Relationships

```text
Platform ──CTFont, DebugTextMode──▶ Renderer.init
Platform ──RenderSurface(+SurfaceInsets)──▶ FrameLoop ──▶ Renderer.render
Renderer ─owns─▶ TextRenderer ─owns─▶ GlyphAtlas, TextBuffer, instance ring, pipeline
Renderer ─owns (debug)─▶ DebugTextPattern ─writes─▶ TextBuffer
```

`SimulationState` is not touched. The FPS measurement lives in `DebugTextPattern`, fed by the
timestamp the frame loop passes to `Renderer.render` (FR-014).
