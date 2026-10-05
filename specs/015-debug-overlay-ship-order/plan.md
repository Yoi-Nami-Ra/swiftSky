# Implementation Plan: Ship and Order Lines on the Debug Overlay

**Branch**: `015-debug-overlay-ship-order` | **Date**: 2026-10-05 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/015-debug-overlay-ship-order/spec.md`

## Summary

The debug overlay (003) gains five ship lines and one or three order lines under its six frame-statistic
lines, in Debug and Profiling builds only. A plain rendering-layer value, `DebugOverlayShip`, is taken
from the simulation state at the overlay's 4 Hz refresh, in the frame loop's step 3a, and handed to the
renderer beside the frame statistics. `DebugOverlay.write` composes the lines with `TextBuffer`'s
allocation-free writers, extended by one signed form.

**Technical approach** (decision record in [research.md](./research.md)):
- **Snapshot** (R1): `DebugOverlayShip`, built from `SimulationState` at step 3a, before step 4 advances
  it: the state after the latest completed tick. Scalars only, no planned path.
- **Hand-over** (R2): `Renderer.updateDebugOverlay(_:ship:)` sets both at once.
- **Signed numbers** (R3): `TextBuffer.writeSignedHundredths(_:width:limit:)`, sharing the unsigned
  writer's digit code; a value that rounds to zero has no sign.
- **Degrees and the seam** (R4): converted in the overlay; a heading that rounds to −180.00 is written
  `180.00`.
- **Layout** (R5): eight-column labels, nine-column values, ASCII units; at most 29 characters per line.
- **Release** (R6): everything new except the signed writer is inside `#if SWIFTSKY_INSTRUMENTATION`;
  the strings check looks for the labels and units, not the phase names, which Swift's reflection
  metadata keeps in every build.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: Metal (unchanged, through 002's text renderer). None new.

**Storage**: N/A.

**Testing**: Swift Testing, headless, in `SwiftSkyRenderingTests`, run by `Scripts/verify.sh`. No test
creates a Metal device.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: 001's frame budget; zero heap allocations per frame (011 check 25). Added: one
copy of about 80 bytes four times a second, and about 190 more glyphs written per frame (the overlay is
rewritten every frame from its last snapshot, 003 R8).

**Constraints**: 1,024-character text capacity (about 300 used after this feature, under 384 at the normal-range maxima); 33 characters per
line within normal ranges (003 FR-005); printable ASCII only (002's atlas).

**Scale/Scope**: 3 changed source files (`TextBuffer.swift`, `DebugOverlay.swift`, `Renderer.swift`)
and 1 in the platform layer (`FrameLoop.swift`); 2 changed test files (`DecimalWritingTests.swift`,
`DebugOverlayTests.swift`). No change to `Package.swift` or `verify.sh`. `CLAUDE.md` gains a line.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; unidirectional flow | **PASS**. The frame loop hands the renderer a plain value; the renderer reads nothing back and writes nothing to the state (FR-011). |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command | **PASS**. Signed formatting, degree conversion, the seam and both layouts are tested (FR-013). |
| III. Performance & Resource Efficiency | No hot-path allocation | **PASS**. Stack values and `StaticString` writes only; check 25 re-run (SC-004). |
| IV. Accessibility & Platform UX | Player-facing UI rules | **PASS (N/A)**. Developer-only debug text, not exposed to assistive technology (003 FR-010). |
| V. Simplicity & YAGNI | Simplest solution | **PASS**. One struct, one writer, no toggles, no new launch argument. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | `DebugOverlayShip` is defined by its consumer, as `DebugOverlayStatistics` is (R1). |
| II | **PASS** | The seam rule is a pure static function, tested on its own (C2). |
| III | **PASS** | The snapshot carries no planned path (R1). |
| IV | **PASS** | Unchanged. |
| V | **PASS** | The signed writer reuses the unsigned one's digit code (R3). |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/015-debug-overlay-ship-order/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R6
├── data-model.md        # Phase 1 output: DebugOverlayShip, the line set
├── quickstart.md        # Phase 1 output: validation guide
├── contracts/
│   └── debug-overlay-ship-order.md   # C1–C4: signed writer, snapshot, lines, hand-over
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Sources/
├── SwiftSkyRendering/
│   ├── Text/TextBuffer.swift        # CHANGED: + writeSignedHundredths
│   ├── Debug/DebugOverlay.swift     # CHANGED: + DebugOverlayShip, ship and order lines
│   └── Renderer.swift               # CHANGED: updateDebugOverlay(_:ship:)
└── SwiftSkyPlatform/
    └── FrameLoop.swift              # CHANGED: step 3a takes the ship snapshot

Tests/
└── SwiftSkyRenderingTests/
    ├── DecimalWritingTests.swift    # CHANGED: signed writer
    └── DebugOverlayTests.swift      # CHANGED: ship and order lines

CLAUDE.md                            # CHANGED: mention spec 015
```

**Structure Decision**: the snapshot lives beside `DebugOverlayStatistics` in `DebugOverlay.swift`,
defined by its consumer; the writer joins its unsigned sibling in `TextBuffer.swift`.

## Complexity Tracking

No violations.
