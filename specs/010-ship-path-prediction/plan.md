# Implementation Plan: Predict the Ship's Planned Path

**Branch**: `010-ship-path-prediction` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-ship-path-prediction/spec.md`

## Summary

Giving the ship an order now also predicts where it will fly. `SimulationState` gains a
`plannedPath: PlannedPath`, written only by `setOrder(to:)`: it flies copies of the ship and the
autopilot forward with the same tick function the real simulation uses, until the copy reports
`arrived` or 60 simulated seconds pass, recording up to 256 positions with the tick each belongs to.
Nothing new is drawn; SKY-30 will draw the path. In Debug and Profiling builds the existing order log
line also reports the predicted end point and tick, which the arrival line later confirms.

**Technical approach** (decision record in [research.md](./research.md)):
- **In the state, written by `setOrder` only** (R1): `private(set)`, so no advance can change it, and
  every order — tests, tap, click — gets a path with no platform change.
- **Inline storage** (R2): `InlineArray<256, Vector2>`, so building and copying the path never
  allocates.
- **One shared tick** (R3): `Simulation.tick(_:_:)` is the body of `advance(_:ticks:)`'s loop and the
  prediction's step, so the copy flies the real flight by construction.
- **Stop on the first `arrived` state** (R4): the same predicate the frame loop logs arrival on.
- **One-pass thinning** (R5): when full, keep every other point and double the spacing; the final
  position is always the last point. At least 128 points for any long flight.
- **Cap** (R6): `60 × tickRate` ticks; about 0.6 ms for a capped prediction in an optimised build.
- **Tests** (R9): synthetic thinning for every length 0…3,700; 006's grids checked against the real
  flight bit for bit; capped flights; per-order behaviour; determinism through `StateBits`.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: none new. `InlineArray` is in the standard library (already used by
`FrameTimeWindow.swift`). `SwiftSkySimulation` still declares no target dependency.

**Storage**: N/A.

**Testing**: Swift Testing, headless, in `SwiftSkySimulationTests`, run by `Scripts/verify.sh`.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: 001's frame budget; zero heap allocations per frame, including frames that
apply an order. A prediction costs one autopilot tick (148–189 ns, 006 check 14) per simulated tick:
≈ 0.6 ms at the 3,600-tick cap, ≈ 60 µs for a 1,000-unit order (SC-007's target: under 1 ms). Measured
by quickstart check 9.

**Constraints**:
- **Memory**: `SimulationState` grows by `PlannedPath`, 4,129 bytes — from about 140 bytes to about
  4.3 KB — copied once per `advance` call and when handed to the renderer; no heap. The cost of the
  larger copy is measured before/after (check 9b).
- **Determinism**: bit-identical across runs on one platform and binary (FR-010), as 004 and 006.
- **Visible output**: unchanged in every build (SC-007).

**Scale/Scope**: 1 new and 2 changed source files in the logic layer, 2 changed source files in the
platform layer (one log line and its call); 1 new and 1 changed test file. No change to rendering,
`Package.swift` or `verify.sh`. `CLAUDE.md` gains a line for spec 010.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. The path and its prediction are in `SwiftSkySimulation` (FR-012). Input → `setOrder` → state → renderer; the renderer still writes nothing back. |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command; CI once a remote exists | **PASS**. Every FR and SC-001–006 gets a headless test (FR-013); SC-007 and SC-009 are manual checks with a headless benchmark behind SC-007. No remote yet: recorded below. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; memory budget; before/after | **PASS**. No allocation (FR-011); bounded work (cap); memory delta stated above; before/after in check 9 and check 11. |
| IV. Accessibility & Platform UX | Dynamic Type, VoiceOver, contrast; reduced motion; HIG | **PASS (N/A)**. Nothing visible changes. |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction | **PASS**. One value type, one function; positions and three tick numbers only; no configuration knobs (capacity and cap are constants). |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Unchanged. The only platform change is three fields on an existing Debug log line (R8). |
| II | **PASS** | Strengthened: the thinning rule is tested for every flight length, not sampled (R9); path bits join `StateBits`, so 006's determinism test covers them (R7). |
| III | **PASS** | The state copy grows to ~4.3 KB; inline storage keeps it allocation-free (R2) and check 9b measures the copy. Rejected: a heap array (copy-on-write allocation on order frames). |
| IV | **PASS (N/A)** | Unchanged. |
| V | **PASS** | The shared `tick` removes a duplication instead of adding a layer (R3); thinning is one pass (R5). |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/010-ship-path-prediction/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R10
├── data-model.md        # Phase 1 output: PlannedPath and the changed SimulationState
├── quickstart.md        # Phase 1 output: validation guide, checks 1–13
├── contracts/
│   └── planned-path.md  # Public API, the prediction, thinning and the log fields
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Sources/
├── SwiftSkySimulation/
│   ├── PlannedPath.swift            # NEW: PlannedPath, its thinning and the prediction
│   ├── SimulationState.swift        # CHANGED: + plannedPath, predicted in setOrder(to:)
│   └── Simulation.swift             # CHANGED: + tick(_:_:), called by advance(_:ticks:)
├── SwiftSkyRendering/               # unchanged
└── SwiftSkyPlatform/
    ├── Instrumentation.swift        # CHANGED: recordOrder gains the path (Debug fields, Release no-op)
    └── FrameLoop.swift              # CHANGED: passes state.plannedPath to recordOrder

Tests/
└── SwiftSkySimulationTests/
    ├── PlannedPathTests.swift       # NEW: thinning, grids vs the real flight, cap, per order
    ├── StateBits.swift              # CHANGED: + path bits, appended to the state's
    └── AutopilotTests.swift         # unchanged; its grids and `fly` are reused

CLAUDE.md                            # CHANGED: mention spec 010 and PlannedPath.swift
```

**Structure Decision**: the logic layer's one-file-per-concept layout is kept: the path type, its
thinning and its prediction are one concept in one file. The shared tick stays in `Simulation.swift`
beside `advance`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command and runs the new tests. |
