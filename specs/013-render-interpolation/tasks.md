# Tasks: Interpolate Rendering Between Simulation Ticks

**Input**: Design documents from `/specs/013-render-interpolation/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ship-pose.md, quickstart.md

**Tests**: Required. FR-011 and Principle II ask for headless tests of the fraction, the blend and the
previous-pose tracking.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Phase 1: Setup

- [ ] T001 Run `./Scripts/verify.sh` on the branch before any change and note the test counts, as the baseline for SC-006

---

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: the logic-layer pieces every story uses: the pose, the fraction and the recorded previous pose.

- [ ] T002 [P] Create `ShipPose` (position, heading, `init(_ ship:)`, `init(position:heading:)`, `Equatable`, `Sendable`) and `static func blended(from:to:fraction:)` per research R3 and contract C1 in `Sources/SwiftSkySimulation/ShipPose.swift`: clamp the fraction into `[0, 1.0.nextDown]`; fraction 0 returns `from`; equal position components and equal headings return `from`'s; heading by `remainder(dividingBy: 2π)` with `−π` → `+π`, wrapped by `Ship.wrapped`
- [ ] T003 [P] Add `tickFraction` (`unconsumed / tickDuration` clamped into `0 ... 1.0.nextDown`) and clamp `unconsumed` to `max(0, …)` after taking whole ticks in `consume(elapsed:)`, per research R1 and contract C2, in `Sources/SwiftSkySimulation/TimeAccumulator.swift`
- [ ] T004 Add `advance(_:ticks:previousPose:)` and `advance(_:ticks:input:previousPose:)`, recording `ShipPose(ship)` immediately before the last tick of the loop and leaving it alone for `ticks <= 0`; make the two existing overloads call them with a discarded pose, per research R4 and contract C3, in `Sources/SwiftSkySimulation/Simulation.swift` (depends on T002)

**Checkpoint**: `swift build` succeeds; all existing tests still pass.

---

## Phase 3: User Story 1 — The ship moves smoothly on a fast display (Priority: P1) 🎯 MVP

**Goal**: the sprite is drawn from the blended pose; `--no-interpolation` draws the tick pose.

**Independent Test**: quickstart checks 8 and 9: a 120 Hz Mac with and without `--no-interpolation`, and at 60 Hz.

- [ ] T005 [US1] Change `render(state:surface:drawable:timestamp:)` to `render(state:shipPose:surface:drawable:timestamp:)` and make `encodeShip` place the sprite from the pose (position and heading) per contract C4 in `Sources/SwiftSkyRendering/Renderer.swift`
- [ ] T006 [US1] Add `interpolates` (false with `--no-interpolation`) and its argument constant to `DebugShipOptions`, and hand it to the frame loop where `spins` is handed over, in `Sources/SwiftSkyPlatform/GameSurfaceView.swift`
- [ ] T007 [US1] In `Sources/SwiftSkyPlatform/FrameLoop.swift`: add `previousPose` (initialised from the initial state's ship) and, under `SWIFTSKY_INSTRUMENTATION`, `debugNoInterpolation`; advance with the `previousPose:` variants in both the autopilot and the spin branches; compute the drawn pose by `ShipPose.blended(from:to:fraction:)` at `accumulator.tickFraction`, or the tick pose when `debugNoInterpolation`; pass it to `render` (depends on T004, T005, T006)
- [ ] T008 [US1] Build both apps (`./Scripts/verify.sh` covers the macOS and iOS `xcodebuild` stages) and run quickstart checks 8 and 9 on the development Mac; record the results in `specs/013-render-interpolation/quickstart.md`

**Checkpoint**: the ship flies smoothly at 120 Hz; the switch restores the old stepping.

---

## Phase 4: User Story 2 — The blended pose is tested and exact (Priority: P2)

**Goal**: headless tests for every rule the smooth picture rests on.

**Independent Test**: `swift test` runs the new suites; quickstart checks 3–7.

- [ ] T009 [P] [US2] Create `Tests/SwiftSkySimulationTests/ShipPoseTests.swift`: fraction 0 and equal pairs (including `−0` components) bit for bit with `StateBits`; 1,000+ pairs (positions within ±10,000 units) and fractions from a local fixed-seed generator, each blended position within 1e-9 units of the exact point at that fraction along the segment; fractions near 1 approach the current pose; seam pairs 3.1 → −3.1 and −3.1 → 3.1 on the short arc; exactly opposite headings blend counter-clockwise; every heading in (−π, π]; out-of-range fractions clamped (SC-001, SC-002)
- [ ] T010 [P] [US2] Extend `Tests/SwiftSkySimulationTests/TimeAccumulatorTests.swift`: 10,000+ elapsed values including 0, negative, non-finite, sub-tick, exact multiples of a tick and 10 s stalls; after each, `tickFraction` in [0, 1) and `unconsumed ≥ 0`; a value one ulp below a whole tick multiple does not leave `unconsumed` negative (SC-003, FR-001)
- [ ] T011 [P] [US2] Extend `Tests/SwiftSkySimulationTests/SimulationTests.swift`: for 0, 1, 2 and 4 ticks, with the autopilot flying an order and with an explicit input, `previousPose` is unchanged at 0, equals the pose after `ticks − 1` single-tick advances otherwise, and the returned state is byte-identical (`StateBits`) to the overload without `previousPose` (SC-003, FR-005)
- [ ] T012 [P] [US2] Extend `Tests/SwiftSkyPlatformTests/DebugShipOptionsTests.swift`: `interpolates` is true by default and false with `--no-interpolation`, independent of the other switches (FR-008)

**Checkpoint**: all new tests pass headlessly.

---

## Phase 5: User Story 3 — Smoothness costs nothing per frame (Priority: P3)

**Goal**: zero allocations per frame and frame times within budget, on both platforms.

**Independent Test**: quickstart check 10.

- [ ] T013 [US3] Run 011's check 25 by "the method" in `specs/011-draw-allocation-counter/quickstart.md` (optimised build carrying the counter, 60 s flying orders) on macOS and in the iOS simulator, on this branch and on `main` for the before figure (Principle III); record `allocs=` and frame times, before and after, in `specs/013-render-interpolation/quickstart.md`

---

## Phase 6: Polish & cross-cutting

- [ ] T014 [P] Add spec 013 and `ShipPose.swift` (the blend, `tickFraction`, the `previousPose:` advance variants, the drawn pose passed to `render`, `--no-interpolation`) to `CLAUDE.md`
- [ ] T015 Run `./Scripts/verify.sh` and `swift test --build-system swiftbuild` 10 times in a row (quickstart checks 1, 2); check 11 by reading the Release path (the argument is parsed only under `SWIFTSKY_INSTRUMENTATION`); record all evidence in `specs/013-render-interpolation/quickstart.md`

---

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002–T004)** → stories.
- T002 and T003 are independent; T004 needs T002.
- **US1** (T005–T008) needs the foundation. T005 and T006 are independent; T007 needs T004–T006.
- **US2** (T009–T012) needs the foundation only, so it can run alongside US1; T012 needs T006.
- **US3** (T013) needs US1.
- **Polish** (T014, T015) last.

## Parallel Example

```text
After T004:  T005 (Renderer.swift) | T006 (GameSurfaceView.swift) | T009 | T010 | T011
After T006:  T012
```

## Implementation Strategy

MVP is US1: the foundation plus T005–T007 makes the ship smooth. US2's tests then pin the rules down,
and US3 confirms the cost. Commit after each phase.
