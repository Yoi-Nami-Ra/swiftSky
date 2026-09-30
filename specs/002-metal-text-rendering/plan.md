# Implementation Plan: Metal Text Rendering

**Branch**: `002-metal-text-rendering` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-metal-text-rendering/spec.md`

## Summary

This adds the ability to draw text through swiftSky's own Metal pipeline, and nothing more. The
proof is a four-line test string, shown in Debug and Profiling builds only when launched with
`--debug-text`. A second argument, `--debug-text-fill`, draws a full 1,024 changing characters for
the performance gates. Release stays uniformly black. The text capability itself ships in every
build, ready for SKY-29.

**Technical approach**:
- **Font**: the platform layer resolves the 13-pt system monospaced font through AppKit or UIKit and
  hands it to the renderer as a `CTFont`.
- **Glyph images**: the renderer rasterises the 95 printable ASCII glyphs on the CPU, with Core Text
  and Core Graphics, into a 16 × 6 grayscale grid at the display's backing scale. It uploads the grid
  once as an `r8Unorm` texture.
- **Layout**: a pure, Metal-free `TextBuffer` lays text out into up to 1,024 pixel-snapped 8-byte
  `GlyphInstance`s without allocating.
- **Drawing**: each frame, the renderer copies the instances into one of three ring buffers, guarded
  by a zero-timeout semaphore. It then issues one instanced draw on top of 001's black quad, through
  a second pipeline that is created once.
- **Scale and safe area**: a change of backing scale rebuilds the atlas as a one-off. Safe-area
  insets now travel in `RenderSurface`.
- **Tests**: layout, metrics, the atlas bitmap and the debug pattern are covered by a new headless
  `SwiftSkyRenderingTests` target.

See [research.md](./research.md) for the decision record.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged from 001.

**Primary Dependencies**: Metal, QuartzCore, **Core Text** and **Core Graphics** in the rendering
layer. **AppKit** (`NSFont`) and **UIKit** (`UIFont`) are used only in the platform layer, for font
lookup. Zero third-party dependencies (FR-002).

**Storage**: N/A.

**Testing**: Swift Testing, headless. The existing `SwiftSkySimulationTests` is joined by a new
`SwiftSkyRenderingTests`, which depends on `SwiftSkyRendering` only and never creates an
`MTLDevice`. Both run through `Scripts/verify.sh`.

**Target Platform**: iOS 26+ (landscape-only iPhone and iPad) and macOS 26+. Unchanged from 001.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: 001's frame budget holds with 1,024 characters changing every frame. Zero heap
allocations on our side in the per-frame draw path, and zero skipped frames over a 60 s run.

**Constraints**:
- **Memory**: under 200 KB steady state, against SC-005's 2 MB ceiling (research R11).
- **Setup**: character images are built once, and rebuilt only on a backing-scale change.
- **Frame loop**: never blocks.
- **Failures**: a text failure never becomes a renderer failure.
- **Baseline**: the 001 baseline devices (iPhone 11, and the Intel MacBook Pro 16-inch 2019) are
  still pending (SKY-31, SKY-32), so Principle III's evidence is recorded as same-device deltas.

**Scale/Scope**: 7 new source files in the rendering layer, 2 changed platform files, 2 new
shader functions, and 1 new test target with 6 test files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow; platform code thin | **PASS**. Text is a presentation concern in the rendering layer. The logic layer is untouched, and the frames-drawn counter is not simulation state (FR-014, 001 FR-012b). Platform-only font APIs stay in the platform layer (R1). No new cross-layer import. |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one checked-in command; CI once a remote exists | **PASS**. Layout, metrics and atlas packing are logic and get headless tests (FR-019). `verify.sh` stays the single command. There is still no remote, so the CI absence stays recorded below. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; stated memory budget; before/after measurement | **PASS**. Zero-allocation design (R5, R6), a stated budget (R11), and before/after measurement in quickstart checks 15 to 18. |
| IV. Accessibility & Platform UX | Dynamic Type, VoiceOver, contrast for UI; reduced motion; HIG | **PASS**. The text is developer-only debug content, hidden from assistive technology (FR-020), and the spec's Assumptions record why Dynamic Type doesn't apply. It is white on black, the highest contrast possible. Reduced motion doesn't apply: a changing counter isn't motion. The safe area is respected (FR-006a). |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction; justified dependencies | **PASS with justified complexity**. One size, one colour, ASCII only, one pipeline. Two items are recorded below. |

**Gate result: PASS.** No unjustified violations. Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Sharpened. R1 found that Core Text alone cannot reach the system monospaced design, which could have tempted AppKit or UIKit into the renderer. Injecting a `CTFont` keeps them in the platform layer. `RenderSurface` grows by one value field, and still crosses the thread boundary by copy. |
| II | **PASS** | Strengthened. R7 adds a `verify.sh` guard, so "headless" is checked by the script rather than by convention. The atlas bitmap is split from the texture upload specifically so that SC-007 can be automated. |
| III | **PASS** | Unchanged in substance. One open item: R5's stored completion block must be shown allocation-free (quickstart check 15), with a named fallback if it is not. |
| IV | **PASS** | Unchanged. |
| V | **PASS with justified complexity** | The instance ring and the sRGB coverage conversion are the only additions beyond the naive design, and both are recorded below. One anticipated addition was avoided: no fifth "text" package target (R6). |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/002-metal-text-rendering/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R13
├── data-model.md        # Phase 1 output: entity shapes and invariants
├── quickstart.md        # Phase 1 output: validation guide, checks 1–20
├── contracts/
│   └── text-rendering.md    # Changed and new inter-layer seams, launch arguments, shaders
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Package.swift                              # + testTarget SwiftSkyRenderingTests → [SwiftSkyRendering]

Sources/
├── SwiftSkySimulation/                    # unchanged
│
├── SwiftSkyRendering/
│   ├── Renderer.swift                     # CHANGED: textFont param, owns TextRenderer, debug pattern hook
│   ├── RenderSurface.swift                # CHANGED: + SurfaceInsets, + safeAreaInsets
│   ├── Shaders.metal                      # CHANGED: + text_vertex, text_fragment
│   ├── Text/
│   │   ├── TextMetrics.swift              # NEW: pixel-rounded font metrics per scale (R3)
│   │   ├── GlyphInstance.swift            # NEW: 8-byte POD, mirrored in the shader
│   │   ├── TextBuffer.swift               # NEW: fixed-capacity, allocation-free layout (R6)
│   │   ├── GlyphAtlasBitmap.swift         # NEW: CPU rasterisation, 16×6 grid (R2)
│   │   ├── TextRenderer.swift             # NEW: atlas texture, pipeline, instance ring, draw (R5)
│   │   └── TextRenderingError.swift       # NEW: failures that never become RendererError (R12)
│   └── Debug/
│       └── DebugTextPattern.swift         # NEW: #if SWIFTSKY_INSTRUMENTATION only (R9, R13)
│
└── SwiftSkyPlatform/
    ├── MetalSurfaceView.swift             # CHANGED: safe-area insets in currentSurface (R8)
    └── GameSurfaceView.swift              # CHANGED: resolves CTFont; parses launch args (debug only)

Tests/
├── SwiftSkySimulationTests/               # unchanged
└── SwiftSkyRenderingTests/                # NEW
    ├── TextBufferLayoutTests.swift        # cells, line feeds, replacement, clipping, clamping
    ├── TextBufferCapacityTests.swift      # 1,024 cap, overflow flag, limit-based writes
    ├── NumberWritingTests.swift           # 0, padding, UInt64.max, never cut short
    ├── TextMetricsTests.swift             # rounding at 1×/2×/3×, snapping, GlyphInstance size
    ├── GlyphAtlasBitmapTests.swift        # ink in every non-space cell, all cells distinct
    └── DebugTextPatternTests.swift        # 95 chars in order, lines ≤ 33, fill == 1,024, no overflow

Scripts/
└── verify.sh                              # CHANGED: + guard that no test creates Metal device/buffer/texture
```

**Structure Decision**: the text code goes in a `Text/` subfolder of the existing
`SwiftSkyRendering` target, not in a new package target. It is presentation, it needs no layer
boundary of its own, and a test target on `SwiftSkyRendering` gives the same headless testability
(R6). `DebugTextPattern` gets its own `Debug/` folder, so that the `SWIFTSKY_INSTRUMENTATION`
boundary is visible in the tree. Each of the four files in the rendering layer that would otherwise
mix concerns stays single-purpose: metrics, layout, bitmap and GPU.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **Instance ring of 3 buffers plus a zero-timeout semaphore** (R5) | The CPU rewrites text every frame while the GPU may still read up to two earlier frames. Without a ring, the two race. | **A single shared buffer** races. **`setVertexBytes`** exceeds Metal's 4 KB guidance at full capacity (8 KB). **Relying on the layer's three drawables** works today, but that setting belongs to the platform layer, so the renderer's correctness would depend on a setting it does not own. The semaphore adds about 10 lines. |
| **sRGB coverage conversion in the text shader** (R4) | Blending on the sRGB surface happens in linear space, which makes anti-aliased edges visibly bolder than the system's text and would fail SC-001 | **Coverage used directly as alpha** is one function simpler, and produces visibly wrong stroke weight. The conversion is one line. |
| **One-off allocations off the steady-state path**: atlas rebuild on a scale change (FR-010), and one overflow log line per run (FR-011) | Both are events rather than per-frame work, and the spec requires both | **Pre-building atlases for every scale** would waste memory for scales that never occur. **Staying silent on overflow** would hide truncated overlay text from developers. |
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command, and it gains the headless guard (R7). |
