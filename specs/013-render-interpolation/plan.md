# Implementation Plan: Interpolate Rendering Between Simulation Ticks

**Branch**: `013-render-interpolation` | **Date**: 2026-10-04 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/013-render-interpolation/spec.md`

## Summary

The ship is drawn between its last two ticks instead of at the latest one. The logic layer gains
`ShipPose` (position and heading) with a pure blend, a `tickFraction` on the time accumulator, and
`advance` variants that record the pose before the last tick of a frame. The frame loop keeps that
previous pose, blends it with the current one at the frame's fraction, and passes the result to the
renderer, which places the sprite from it. `--no-interpolation` (instrumented builds) draws the tick
pose for comparison.

**Technical approach** (decision record in [research.md](./research.md)):
- **Fraction** (R1): derived from `unconsumed`, clamped into `[0, 1)`; `consume` also keeps
  `unconsumed ≥ 0`, which floating-point rounding could break.
- **Pose and blend** (R2, R3): a 24-byte logic-layer value; linear position, shortest-arc heading
  wrapped by `Ship.wrapped`; equal inputs and fraction 0 return the input bit for bit.
- **Previous pose** (R4): recorded inside `Simulation.advance`'s existing loop before the last tick,
  so the rule is pure and tested; the frame loop only holds the value.
- **Drawn pose** (R5): a `render` argument, the one pose SKY-30 and SKY-42 will also use.
- **Switch** (R6): `--no-interpolation` in `DebugShipOptions`.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: none new. `SwiftSkySimulation` still declares no target dependency.

**Storage**: N/A.

**Testing**: Swift Testing, headless, in `SwiftSkySimulationTests` and `SwiftSkyPlatformTests`, run
by `Scripts/verify.sh`.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: 001's frame budget; zero heap allocations per frame (011 check 25). Added per
frame: one 24-byte pose copy inside `advance`, one blend (a few multiplies, one `remainder`), and one
more argument to `render`. Negligible against the ~4.2 KB state copy the frame already makes.

**Constraints**:
- **Determinism**: the simulation's results are byte-identical to before (C3); the blend is pure.
- **Visible output**: the ship is drawn up to one tick (16.7 ms) behind the simulation, by design.
- **Reduce Motion**: unaffected (FR-010).

**Scale/Scope**: 1 new and 2 changed files in the logic layer, 1 changed file in rendering, 2 changed
files in the platform layer; 1 new and 3 changed test files. No change to `Package.swift` or
`verify.sh`. `CLAUDE.md` gains a line for spec 013.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. Pose, blend and fraction are in the logic layer; the frame loop holds the previous pose; the renderer reads the drawn pose and writes nothing back (FR-006). |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command | **PASS**. FR-001–FR-005 and FR-008 get headless tests (FR-011); SC-004 is a by-eye check, SC-005 a measured one. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation | **PASS**. Value types only; check 25 re-run on both platforms (SC-005). |
| IV. Accessibility & Platform UX | Reduced motion; HIG | **PASS**. Interpolation adds no motion; Reduce Motion unchanged (FR-010). |
| V. Simplicity & YAGNI | Simplest solution | **PASS**. Ship only, one value type, no snap handling (nothing teleports), no extrapolation. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Unchanged. The drawn pose crosses into rendering as a plain argument (R5). |
| II | **PASS** | Strengthened: the previous-pose rule is tested in the logic layer instead of living untested in the Metal-bound frame loop (R4). |
| III | **PASS** | One state copy per frame, as before; rejected the split advance that would copy it twice (R4). |
| IV | **PASS** | Unchanged. |
| V | **PASS** | The existing `advance` overloads become wrappers; no new layer or protocol. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/013-render-interpolation/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R8
├── data-model.md        # Phase 1 output: ShipPose and the changed types
├── quickstart.md        # Phase 1 output: validation guide, checks 1–11
├── contracts/
│   └── ship-pose.md     # C1–C5: pose, fraction, advance, render, the switch
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Sources/
├── SwiftSkySimulation/
│   ├── ShipPose.swift               # NEW: ShipPose and its blend
│   ├── TimeAccumulator.swift        # CHANGED: + tickFraction; unconsumed clamped ≥ 0
│   └── Simulation.swift             # CHANGED: + advance(…, previousPose:) variants
├── SwiftSkyRendering/
│   └── Renderer.swift               # CHANGED: render(…, shipPose:, …); encodeShip from the pose
└── SwiftSkyPlatform/
    ├── FrameLoop.swift              # CHANGED: previousPose, drawn pose, debugNoInterpolation
    └── GameSurfaceView.swift        # CHANGED: DebugShipOptions.interpolates, handed to the loop

Tests/
├── SwiftSkySimulationTests/
│   ├── ShipPoseTests.swift          # NEW: blend endpoints, segment, seam, range
│   ├── TimeAccumulatorTests.swift   # CHANGED: fraction range, unconsumed ≥ 0
│   └── SimulationTests.swift        # CHANGED: previous pose on 0/1/2/4-tick frames
└── SwiftSkyPlatformTests/
    └── DebugShipOptionsTests.swift  # CHANGED: --no-interpolation

CLAUDE.md                            # CHANGED: mention spec 013 and ShipPose.swift
```

**Structure Decision**: the logic layer's one-file-per-concept layout is kept: the pose and its blend
are one concept in one file. The fraction stays with the accumulator and the recorded pose with
`advance`.

## Complexity Tracking

No violations.
