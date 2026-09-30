# Implementation Plan: Ship State and Newtonian Motion

**Branch**: `004-ship-newtonian-motion` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-ship-newtonian-motion/spec.md`

## Summary

The simulation gets one ship. `SimulationState` gains a `Ship` value holding position, velocity,
heading and rate of turn, plus fixed `ShipLimits` (defaults 200 units/s², 180 °/s, 360 °/s²).
`Simulation.advance` gains a `ControlInput` parameter (thrust 0…1, turn −1…1) defaulting to neutral,
and steps the ship once per tick with frictionless semi-implicit Euler: the rate of turn moves toward
`turn × maxAngularSpeed` at the angular-acceleration limit, then the heading, then the velocity
(thrust along the new heading), then the position. Nothing is visible: the frame loop's call is
unchanged and passes the neutral input, so the ship stays at rest.

**Technical approach**:
- **Values only**: `Vector2`, `ShipLimits`, `ControlInput`, `Ship`, all `Sendable` structs of
  `Double`s. Input and limits are sanitised once, on construction (research R6).
- **One rule, one file**: `Ship.step(_:)` in `ShipMotion.swift`, the layer's only file with an import
  (`Darwin`, for `cos`/`sin`; research R3). `advance` loops `step` `ticks` times.
- **Angles in radians** internally; the defaults' degree values live in doc comments (R2).
- **Exactness where the spec asks for it**: the rate snaps to its target (R4), unthrusted ticks skip
  the thrust update, and in-range headings are not re-wrapped (R5), so neutral-at-rest is the bitwise
  identity.
- **Tests**: `ShipMotionTests` compares bit patterns, not `==` (R8).

See [research.md](./research.md) for the decision record.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: none new. `Darwin` (the C library) for `cos` and `sin`. There are zero
third-party dependencies, and `SwiftSkySimulation` still declares no target dependency.

**Storage**: N/A.

**Testing**: Swift Testing, headless, in the existing `SwiftSkySimulationTests` target. Run through
`Scripts/verify.sh`.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: 001's frame budget holds; zero heap allocations per frame. The step costs at
most one `cos`, one `sin` and about twenty floating-point operations per tick, at most four ticks per
frame.

**Constraints**:
- **Memory**: `SimulationState` grows from 8 bytes to 8 + 9 × 8 = 80 bytes. It is copied once per
  frame into the renderer; no heap involvement.
- **Determinism**: bit-identical across runs on one platform and binary (FR-012). Not promised
  across CPU architectures (research R3).
- **Visible output**: unchanged in every build (SC-005).

**Scale/Scope**: 3 new source files, 2 changed source files, 1 new test file and 1 test helper, all in
the logic layer and its tests. No change to rendering, platform or `verify.sh`. `Package.swift`
changes by one comment only: the logic layer "imports nothing" becomes "declares no dependencies and
imports only the C library, for `cos`/`sin`" (research R3).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. Everything is in `SwiftSkySimulation`, which gains no target dependency. Input → `advance` → state → renderer, as before (FR-014). |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command; CI once a remote exists | **PASS**. The motion rule is exactly the "physics" the principle names, and every FR gets a headless test (FR-015). `verify.sh` is the single command. No remote yet: recorded below. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; memory budget; before/after | **PASS**. The step runs on the hot path, so it is value-only and allocation-free (R7), the memory delta is stated above, and before/after evidence is a headless release-mode benchmark (quickstart check 11, always run) plus the on-device checks 8 and 9. |
| IV. Accessibility & Platform UX | Dynamic Type, VoiceOver, contrast; reduced motion; HIG | **PASS (N/A)**. No UI and nothing visible. |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction | **PASS**. One ship, not a fleet; no top speed, drag or reverse thrust; no physics engine, no `Angle` type, no generic integrator. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Clarified. The logic layer's first `import` is `Darwin`, the C library: no framework type and no target dependency (R3). Recorded so a reviewer does not read it as a boundary break. |
| II | **PASS** | Strengthened. R8 found that `==` on `Double` cannot check "bit-for-bit", so the tests compare bit patterns. |
| III | **PASS** | Strengthened. R7 adds a headless before/after benchmark (ns per tick, allocations) so the Principle III evidence never depends on having a device session. |
| IV | **PASS (N/A)** | Unchanged. |
| V | **PASS** | `Vector2` is a hand-written four-operator struct rather than `SIMD2` (R10): smaller than the argument that `SIMD2` arithmetic is bit-stable. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/004-ship-newtonian-motion/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R10
├── data-model.md        # Phase 1 output: entity shapes and invariants
├── quickstart.md        # Phase 1 output: validation guide, checks 1–11
├── contracts/
│   └── ship-motion.md   # Public API and the per-tick rule
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Sources/
├── SwiftSkySimulation/
│   ├── Vector2.swift                # NEW: plane vector, +, +=, * Double, .zero
│   ├── Ship.swift                   # NEW: Ship, ShipLimits (+ .default), ControlInput (+ .neutral)
│   ├── ShipMotion.swift             # NEW: Ship.step(_:), the per-tick rule; imports Darwin
│   ├── SimulationState.swift        # CHANGED: + ship, + init(tickCount:ship:)
│   └── Simulation.swift             # CHANGED: advance(_:ticks:input: = .neutral) loops ship.step
├── SwiftSkyRendering/               # unchanged
└── SwiftSkyPlatform/                # unchanged (FrameLoop's call compiles as is)

Tests/
└── SwiftSkySimulationTests/
    ├── StateBits.swift              # NEW: test helper, state → [UInt64] bit patterns
    ├── ShipMotionTests.swift        # NEW: rest, thrust, drift, turning, wrap, sanitising, determinism
    └── SimulationTests.swift        # unchanged; still passes

Package.swift                        # CHANGED: the logic layer's "imports nothing" comment (R3)
CLAUDE.md                            # CHANGED: mention spec 004 and the ship
```

**Structure Decision**: the logic layer's flat one-file-per-concept layout is kept. The per-tick rule
is separate from the types so that the layer's only `import` sits in one small file.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command and runs the new tests. |
