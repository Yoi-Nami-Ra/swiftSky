# Implementation Plan: Draw the Order Overlay

**Branch**: `014-order-overlay` | **Date**: 2026-10-05 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/014-order-overlay/spec.md`

## Summary

While the ship flies an order, the renderer draws a destination marker, a ring around the ship and the
remaining planned path, between the background and the ship, in every build. A pure rendering-layer
value, `OrderOverlay`, prepares the geometry in pixels each frame from the state, the drawn pose and a
new `poseTick`; two pipelines built once draw it with one signed-distance fragment shader and
`max` blending, fed by `setVertexBytes`.

**Technical approach** (decision record in [research.md](./research.md)):
- **Prepared value** (R1): `OrderOverlay`, `nil` when nothing is drawn; tested headlessly.
- **Reached points** (R2): `poseTick` from the frame loop; `PlannedPath.tick(ofPoint:)` in the logic
  layer.
- **Line** (R3): drawn ship → remaining points → destination, always ending at the marker.
- **Drawing** (R4, R5): distance-field capsules and rings, anti-aliased, `max` blend over black.
- **Data** (R6): `setVertexBytes`, ≤ 2,064 bytes of points; no buffers.
- **Style** (R7): `OrderOverlayStyle` constants; cyan-green at 85 %.
- **Ring centre** (R8): the sprite's own whole-pixel centre.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency; Metal Shading Language.
Unchanged.

**Primary Dependencies**: Metal. None new.

**Storage**: N/A.

**Testing**: Swift Testing, headless, in `SwiftSkySimulationTests` and `SwiftSkyRenderingTests`, run by
`Scripts/verify.sh`. No test creates a Metal device.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: 001's frame budget; zero heap allocations per frame (011 check 25). Added per
frame while an order is flown: one walk over at most 256 path points, about 4 KB of stack values, two
`setVertexBytes` copies (≤ 2 KB), two instanced draws of at most 257 and 2 quads. Fragment work is
bounded by the quads' area: thin strips along the path plus two small squares.

**Constraints**:
- **Blending** is correct over the black background only (R5).
- **Visible output** with no order is unchanged (SC-004).
- **Reduce Motion**: nothing animates (FR-014).

**Scale/Scope**: 1 changed file in the logic layer; 2 new and 2 changed files in rendering
(`Shaders.metal`, `Renderer.swift`); 1 changed file in the platform layer; 1 new and 1 changed test
file. No change to `Package.swift` or `verify.sh`. `CLAUDE.md` gains a line for spec 014.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. The overlay reads the state and the drawn pose and writes nothing back (FR-016); pixels stay in rendering. |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command | **PASS**. Visibility, reached points and placement are pure and tested (FR-017); the shader is render code, exempt. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation | **PASS**. Fixed capacity, stack values, pipelines built once (FR-013); check 25 re-run (SC-005). |
| IV. Accessibility & Platform UX | Reduced motion; not colour alone | **PASS**. No animation (FR-014); marker and ring differ by size (FR-008). |
| V. Simplicity & YAGNI | Simplest solution | **PASS**. One fragment shader for both shapes; no buffers, no off-screen indicator, no style system. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | `poseTick` crosses into rendering as a plain argument, beside the drawn pose (R2). |
| II | **PASS** | The reached rule's tick arithmetic is tested in the logic layer, where the path's bookkeeping lives (C1). |
| III | **PASS** | `setVertexBytes` stays under its 4 KB limit at full capacity (R6); no completion tracking needed. |
| IV | **PASS** | Unchanged. |
| V | **PASS** | `max` blending replaced a stencil or merged-field design (R5). |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/014-order-overlay/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R9
├── data-model.md        # Phase 1 output: OrderOverlay, the style, PlannedPath.tick(ofPoint:)
├── quickstart.md        # Phase 1 output: validation guide, checks 1–12
├── contracts/
│   └── order-overlay.md # C1–C5: point ticks, the overlay, render, poseTick, shaders
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Sources/
├── SwiftSkySimulation/
│   └── PlannedPath.swift            # CHANGED: + tick(ofPoint:)
├── SwiftSkyRendering/
│   ├── OrderOverlay.swift           # NEW: OrderOverlay and OrderOverlayStyle
│   ├── OrderOverlayPipelines.swift  # NEW: the two pipeline states, built once
│   ├── Shaders.metal                # CHANGED: overlay vertex functions and fragment
│   └── Renderer.swift               # CHANGED: render(…, poseTick:, …); encodeOrderOverlay
└── SwiftSkyPlatform/
    └── FrameLoop.swift              # CHANGED: poseTick beside the drawn pose

Tests/
├── SwiftSkySimulationTests/
│   └── PlannedPathTests.swift       # CHANGED: tick(ofPoint:)
└── SwiftSkyRenderingTests/
    └── OrderOverlayTests.swift      # NEW: visibility, reached points, placement, line ends

CLAUDE.md                            # CHANGED: mention spec 014 and OrderOverlay.swift
```

**Structure Decision**: the rendering layer's one-file-per-concept layout is kept, mirroring the ship:
`OrderOverlay.swift` is the tested placement (like `ShipSpritePlacement.swift`), and
`OrderOverlayPipelines.swift` the GPU state built once (like `ShipSprite.swift`).

## Complexity Tracking

No violations.
