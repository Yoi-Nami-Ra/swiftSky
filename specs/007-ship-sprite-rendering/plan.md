# Implementation Plan: Ship Sprite Rendering

**Branch**: `007-ship-sprite-rendering` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-ship-sprite-rendering/spec.md`

## Summary

The ship becomes visible. The rendering layer decodes a byte-identical copy of
`design/sprites/ship.png` from its own resource bundle once at start-up. It uploads the image to an sRGB
texture with a mip chain and, every frame, draws it as a blended quad between the black background
and the text. The quad's four corners come from a pure, tested `ShipSpritePlacement`: through the
camera to view points, snapped to a whole surface pixel, then rotated by heading − π/2 and sized at
40 points. A missing or unusable image is a new `RendererError` case. Two Debug-only launch arguments,
`--debug-ship-spin` and `--no-ship`, make rotation visible and keep the earlier black-surface checks
runnable.

**Technical approach**:
- **Resource** (R1): `.copy` into `SwiftSkyRendering`'s bundle, with a `cmp` stage in `verify.sh`.
- **Image** (R2, R3): ImageIO and Core Graphics to premultiplied sRGB RGBA8, headlessly testable;
  `.rgba8Unorm_srgb` texture; `one` / `oneMinusSourceAlpha` blending, which matches Core Graphics
  over black.
- **Texture** (R4): 7 mip levels generated once by a blit at init; `constexpr` trilinear sampler.
- **Geometry** (R5, R6): the CPU computes the corners; 32 bytes a frame through `setVertexBytes`.
- **Switches** (R9): platform-layer parsing beside `DebugTextMode`; the spin uses the existing
  explicit-input `Simulation.advance`.

See [research.md](./research.md) for the decision record.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency; Metal Shading Language.
Unchanged.

**Primary Dependencies**: Apple frameworks only. New imports in the rendering layer: ImageIO
(`ShipImageBitmap`) and CoreGraphics (already used by text). No third-party dependencies (001 FR-018).

**Storage**: One bundled resource, `ship.png` (41 KB); about 34 KB of texture memory with mips.

**Testing**: Swift Testing, headless: `SwiftSkyRenderingTests` (placement, image decoding, error) and
`SwiftSkyPlatformTests` (launch arguments). Run through `Scripts/verify.sh`. The Metal-device guard
stays: no test creates a device or texture.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: Frame budget unchanged (001 SC-003). Added per-frame cost: one pipeline switch,
32 bytes of inline vertex data, one texture bind and one four-vertex draw (R10).

**Constraints**: No per-frame allocation (001 FR-020). Everything is created once at init (FR-011).
Release contains no trace of the switches (FR-015).

**Scale/Scope**: New: `ShipImageBitmap.swift`, `ShipSpritePlacement.swift`, `ShipSprite.swift`,
`Resources/ship.png`, the two sprite shaders, and 4 test files (or suites). Changed: `Renderer.swift`,
`RendererError.swift`, `Shaders.metal`, `GameSurfaceView.swift`, `FrameLoop.swift`,
`SimulationState.swift` (comment only), `GameSpace.swift` (comment only), `Package.swift`,
`Scripts/verify.sh`, `CLAUDE.md`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. Drawing is in the rendering layer; it reads `SimulationState.ship` and writes nothing back (FR-001). The switches are parsed in the platform layer. The logic layer changes one comment. |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command | **PASS**. Placement maths, image decoding, the error mapping and argument parsing are tested headlessly. The draw itself is visual (exempt) and covered by quickstart checks. `verify.sh` stays the single command and gains the byte-identity stage. No remote yet, so no CI (recorded below). |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; memory budget; before/after | **PASS**. Allocation-free per frame by construction (R5, R10). The before/after measurement against 003's baseline is quickstart check 19. |
| IV. Accessibility & Platform UX | VoiceOver, reduced motion, HIG | **PASS**. The surface's accessible description is unchanged, by clarification (FR-016a). Nothing moves at launch; the only motion is the Debug-only spin, which is opt-in. |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction | **PASS**. One sprite, one texture; no general sprite system, atlas or batching; no interpolation. The mip chain is justified by FR-010 at 1× (R4). |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Confirmed. The spin reuses the logic layer's existing explicit-input entry point; no debug concept enters the logic layer (R9). |
| II | **PASS** | Strengthened. The shader does no placement maths, so the tested corners are the drawn corners (R5). |
| III | **PASS** | Unchanged. `setVertexBytes` avoids a per-frame buffer and its slot ring. |
| IV | **PASS** | Unchanged. |
| V | **PASS** | R2 rejects MetalKit; R4 rejects a sampler object; R5 rejects a transform uniform. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/007-ship-sprite-rendering/
├── plan.md              # This file
├── research.md          # Phase 0: decision record R1–R11
├── data-model.md        # Phase 1: pose, bitmap, placement, sprite, error, switches
├── quickstart.md        # Phase 1: validation guide, checks 1–19
├── contracts/
│   └── ship-sprite.md   # API and guarantees C1–C17
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/
├── SwiftSkySimulation/
│   └── SimulationState.swift        # CHANGED: doc comment only (the renderer now draws the ship)
├── SwiftSkyRendering/
│   ├── Resources/ship.png           # NEW: byte-identical copy of design/sprites/ship.png (R1)
│   ├── ShipImageBitmap.swift        # NEW: CPU decode to premultiplied sRGB RGBA8; ShipImageError (R2)
│   ├── ShipSpritePlacement.swift    # NEW: pure corner maths (R6)
│   ├── ShipSprite.swift             # NEW: pipeline + texture + mips, built once (R4)
│   ├── Renderer.swift               # CHANGED: build ShipSprite; draw between quad and text; drawsShip
│   ├── RendererError.swift          # CHANGED: .shipImageUnavailable(reason:) (R7)
│   ├── Shaders.metal                # CHANGED: swiftsky_sprite_vertex / _fragment; header comment
│   └── GameSpace.swift              # CHANGED: note points at ShipSpritePlacement
└── SwiftSkyPlatform/
    ├── GameSurfaceView.swift        # CHANGED: DebugShipOptions; wires drawsShip and debugShipSpin
    └── FrameLoop.swift              # CHANGED: debugShipSpin → explicit turn input

Tests/
├── SwiftSkyRenderingTests/
│   ├── ShipSpritePlacementTests.swift   # NEW: C1–C10
│   ├── ShipImageBitmapTests.swift       # NEW: C11–C13
│   └── RendererErrorTests.swift         # NEW: C14
└── SwiftSkyPlatformTests/
    └── DebugShipOptionsTests.swift      # NEW: C15

Package.swift                        # CHANGED: SwiftSkyRendering resources: [.copy("Resources/ship.png")]
Scripts/verify.sh                    # CHANGED: ship-image byte-identity stage
CLAUDE.md                            # CHANGED: mention spec 007, the sprite and the switches
```

**Structure Decision**: The rendering layer's flat, one-file-per-concept layout is kept, as for
`FullscreenQuad.swift`. A `Ship/` subfolder was not worth it for three files. Resources go in
`Resources/`, the SwiftPM convention.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command. |
| **A checked duplicate of the ship image** | SwiftPM resources must live inside the target directory | A symlink or build-phase copy is more fragile; the `cmp` stage makes drift impossible to miss (R1). |
