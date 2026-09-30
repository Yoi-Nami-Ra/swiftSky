# Implementation Plan: Game Space and Camera

**Branch**: `005-game-space-camera` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-game-space-camera/spec.md`

## Summary

The world meets the screen. One world unit is one point, the world is unbounded, and a fixed camera
puts the world origin at the centre of the whole surface. `SwiftSkyRendering` gains a `Camera` value,
built from a `RenderSurface` by a failable initialiser that stores the surface's half-width and
half-height in points and returns `nil` for a zero-area surface or an unusable backing scale. It maps
world → view points `(w/2 + x, h/2 − y)`, view points → world `(vx − w/2, h/2 − vy)` and world → clip
`(x ÷ w/2, y ÷ h/2)`. Beside it, `GameSpace.shipLength = 40` and the sprite-orientation note for
SKY-27. Nothing is wired in and nothing visible changes.

**Technical approach**:
- **Rendering layer** (R1), `Vector2` for all three spaces (R2).
- **Validate once, store half-extents** (R3); divide rather than multiply by reciprocals so the
  edges land on exactly ±1 and 1×/2×/3× agree bit for bit (R4).
- **No wiring** (R6): consumers arrive with SKY-10, SKY-11, SKY-27 and SKY-30.
- **Tests**: `CameraTests` in the rendering test target, which gains `SwiftSkySimulation` as a
  declared dependency (R8).

See [research.md](./research.md) for the decision record.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: none new. No framework import in the new files.

**Storage**: N/A.

**Testing**: Swift Testing, headless, in the existing `SwiftSkyRenderingTests` target. Run through
`Scripts/verify.sh`.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: unchanged. The camera is not on the frame path in this feature (R6, R10).

**Constraints**:
- **Memory**: `Camera` is 16 bytes; `GameSpace` has no instances.
- **Exactness**: corner and edge values exact; view → world → view within 1e-9 points (R4, R5).
- **Visible output**: unchanged in every build (SC-006).

**Scale/Scope**: 2 new source files (`Camera.swift`, `GameSpace.swift`), 1 new test file, 1 changed
doc comment (`Ship.swift`), `Package.swift` (one test-target dependency), `CLAUDE.md`. No change to the
renderer, shaders, platform layer or `verify.sh`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. The camera sits in the rendering layer, consumes only `RenderSurface` and the logic layer's `Vector2`, and imports no platform code (FR-011). The logic layer is untouched apart from a comment. |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command; CI once a remote exists | **PASS**. The transforms are logic every later placement and input depends on, so each FR and contract guarantee gets a headless test (FR-014). `verify.sh` is the single command. No remote yet: recorded below. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; memory budget; before/after | **PASS**. Not on the hot path in this feature; the type is allocation-free by construction (SC-007). SKY-27 carries the before/after measurement when it puts the camera on the draw path. |
| IV. Accessibility & Platform UX | Dynamic Type, VoiceOver, contrast; reduced motion; HIG | **PASS (N/A)**. No UI and nothing visible. |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction | **PASS**. No pan, zoom, follow or bounds; no wrapper types per space; no stored camera nobody reads. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Clarified. The rendering test target now declares `SwiftSkySimulation` (R8); that is the logic layer, which is GPU-free, so the target stays headless and no forbidden direction is added. |
| II | **PASS** | Strengthened. R4 makes the exact-value expectations (edges at ±1, identical across scales) sound rather than lucky. |
| III | **PASS** | Unchanged. R10 records why structural evidence suffices. |
| IV | **PASS (N/A)** | Unchanged. |
| V | **PASS** | R2 rejects per-space wrapper types; R6 rejects wiring a camera nobody reads. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/005-game-space-camera/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R10
├── data-model.md        # Phase 1 output: spaces, Camera, GameSpace
├── quickstart.md        # Phase 1 output: validation guide, checks 1–11
├── contracts/
│   └── camera.md        # Public API and guarantees C1–C11
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Sources/
├── SwiftSkySimulation/
│   └── Ship.swift                   # CHANGED: ShipLimits.default's doc comment only (R9)
├── SwiftSkyRendering/
│   ├── Camera.swift                 # NEW: Camera, init?(surface:), three mappings
│   └── GameSpace.swift              # NEW: GameSpace.shipLength, scale/extent/sprite notes
└── SwiftSkyPlatform/                # unchanged

Tests/
└── SwiftSkyRenderingTests/
    └── CameraTests.swift            # NEW: mappings, round trip, scales, resize, insets, no-camera

Package.swift                        # CHANGED: SwiftSkyRenderingTests + SwiftSkySimulation dependency (R8)
CLAUDE.md                            # CHANGED: mention spec 005 and the camera
```

**Structure Decision**: the rendering layer's flat one-file-per-concept layout is kept; the camera
sits beside `RenderSurface.swift`, which it is built from.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command and runs the new tests. |
