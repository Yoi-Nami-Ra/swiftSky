# Implementation Plan: Ship Autopilot — Turn, Burn, Flip and Brake

**Branch**: `006-ship-autopilot` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-ship-autopilot/spec.md`

## Summary

The simulation gets a pilot. `SimulationState` gains an `Autopilot` value holding the current
`MoveOrder` (a destination), the last `AutopilotPhase` and fixed `ArrivalTolerances` (1 unit,
1 unit/s). `Simulation.advance(_:ticks:)` asks the autopilot for each tick's `ControlInput` when
there is an order and steps the ship with it; `advance(_:ticks:input:)` keeps 004's explicit-input
behaviour and leaves the order alone. Nothing is visible: no code issues orders yet, so the frame
loop's unchanged call keeps passing the neutral input.

**Technical approach** (decision record in [research.md](./research.md)):
- **Closed-loop velocity tracking** (R1): each tick, a desired velocity towards the destination whose
  speed the ship can still brake from, `min(vStop(d, T), k·d)`; the ship turns to face the velocity
  error and thrusts along it once inside a 0.1 rad cone. Sideways drift is cancelled by construction.
- **Flip time in the profile** (R2): `vStop(d, T) = 2d / (T + √(T² + 2d/a′))`, `T` being the time to
  turn to the braking attitude, so the flip starts before halfway.
- **No-overshoot margin** (R3): the profile brakes at `a′ = 0.9 a`; the ship brakes at up to `a`.
- **Linear tail, turn law, hold rule** (R4, R5): exponential settle in the last 3.6 units; a
  √-profile turn with a deadbeat last tick; the ship never turns round to add a sliver of speed.
- **Phases classified per tick** (R6) from what the tick does, with the previous phase as the only
  memory (arrival latch, braking latch).
- **Tests** (R9): parameterised grids for SC-001–004, re-order, station-keeping and ten-run
  determinism with `StateBits`.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: none new. `Darwin` for `atan2`, `cos`, `sin`, `sqrt` (already imported by
`ShipMotion.swift`). `SwiftSkySimulation` still declares no target dependency.

**Storage**: N/A.

**Testing**: Swift Testing, headless, in `SwiftSkySimulationTests`, run by `Scripts/verify.sh`.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: 001's frame budget; zero heap allocations per frame. The law costs about
four `sqrt`, one `atan2`, one `cos`/`sin` pair and ~60 floating-point operations per tick, at most
four ticks per frame (expected < 100 ns per tick; measured by quickstart check 14).

**Constraints**:
- **Memory**: `SimulationState` grows by the autopilot — two tolerance `Double`s, an optional
  two-`Double` order and an optional phase tag — under 64 bytes, copied once per frame, no heap.
- **Determinism**: bit-identical across runs on one platform and binary (FR-012), as 004.
- **Visible output**: unchanged in every build (SC-007).

**Scale/Scope**: 2 new source files, 2 changed source files, 1 new and 1 changed test file, all in the logic layer
and its tests. No change to rendering, platform, `Package.swift` or `verify.sh`. `CLAUDE.md` gains a
line for spec 006.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. Everything is in `SwiftSkySimulation`, no new target dependency. Order → state → `advance` → state → renderer (FR-016). |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command; CI once a remote exists | **PASS**. The autopilot is exactly the "AI/game logic" the principle names; every FR and SC-001–006, 008 gets a headless test (FR-017). No remote yet: recorded below. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; memory budget; before/after | **PASS**. Constant work, value-only (FR-015); memory delta stated; before/after via the headless benchmark (check 14) plus on-device checks 11–12. |
| IV. Accessibility & Platform UX | Dynamic Type, VoiceOver, contrast; reduced motion; HIG | **PASS (N/A)**. No UI, nothing visible. |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction | **PASS**. One order, no queue, no cancel, no path planner or solver; tuning constants are `static let`s, not knobs. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Unchanged. The new `import Darwin` mirrors `ShipMotion.swift` (004 R3). |
| II | **PASS** | Strengthened: R9 parameterises the SC grids so each failing case is named; determinism compares bit patterns. |
| III | **PASS** | Unchanged: check 14 always runs, device checks as for 004. |
| IV | **PASS (N/A)** | Unchanged. |
| V | **PASS** | The phase is a per-tick classification with one remembered value (R6), not a state machine; the law is one function. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/006-ship-autopilot/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R10
├── data-model.md        # Phase 1 output: entity shapes and invariants
├── quickstart.md        # Phase 1 output: validation guide, checks 1–14
├── contracts/
│   └── autopilot.md     # Public API and the per-tick law
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Sources/
├── SwiftSkySimulation/
│   ├── Autopilot.swift              # NEW: MoveOrder, AutopilotPhase, ArrivalTolerances, Autopilot
│   ├── AutopilotLaw.swift           # NEW: the per-tick law (control(for:)); imports Darwin
│   ├── SimulationState.swift        # CHANGED: + autopilot, + setOrder(to:), + distanceRemaining
│   └── Simulation.swift             # CHANGED: advance(_:ticks:) autopilot-driven; advance(_:ticks:input:) explicit
├── SwiftSkyRendering/               # unchanged
└── SwiftSkyPlatform/                # unchanged (FrameLoop's call compiles as is)

Tests/
└── SwiftSkySimulationTests/
    ├── AutopilotTests.swift         # NEW: grids, re-order, read-out, edges, station-keeping, determinism
    ├── StateBits.swift              # CHANGED: + autopilot tolerances, order and phase bits
    ├── ShipMotionTests.swift        # unchanged; still passes
    └── SimulationTests.swift        # unchanged; still passes

CLAUDE.md                            # CHANGED: mention spec 006 and the autopilot files
```

**Structure Decision**: the logic layer's one-file-per-concept layout is kept. As with the ship, the
types and the law are split so that the `Darwin` import sits beside the maths that needs it.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command and runs the new tests. |
