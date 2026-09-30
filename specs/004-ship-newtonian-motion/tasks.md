---

description: "Task list for 004-ship-newtonian-motion"
---

# Tasks: Ship State and Newtonian Motion

**Input**: Design documents from `/specs/004-ship-newtonian-motion/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ship-motion.md, quickstart.md

**Tests**: Required. FR-015 and the ticket's "done when" call for Swift Testing coverage, and
constitution Principle II requires tests for all physics. There is no drawing code in this feature.

**Organization**: tasks are grouped by user story, so that each story can be implemented and
validated on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US4)
- Paths are relative to the repository root. `R<n>` refers to research.md and `check <n>` to
  quickstart.md.

## Path Conventions

- The logic layer is `Sources/SwiftSkySimulation/`, its tests `Tests/SwiftSkySimulationTests/`. No
  other layer changes (plan.md, research R9).
- Angles are radians in code (R2). Tests convert the spec's degrees once:
  `let degree = Double.pi / 180`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the test helper every story's bit-exact assertions use.

- [X] T001 [P] Create `Tests/SwiftSkySimulationTests/StateBits.swift` with an internal `func bits(_ state: SimulationState) -> [UInt64]` returning `[tickCount]` followed by the `bitPattern` of `ship.position.x`, `.y`, `ship.velocity.x`, `.y`, `ship.heading`, `ship.angularVelocity`, and the three `ship.limits` values, in that order, plus an overload `bits(_ ship: Ship)` that returns the same list without the tick count. Doc-comment why `==` is not enough: `+0 == −0` and `NaN != NaN` (R8). Test-only code, so the array is fine

**Checkpoint**: none on its own; T001 compiles once T005 exists.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the value types and the state field every story uses (data-model.md,
contracts/ship-motion.md).

**⚠️ CRITICAL**: no user story work can begin until this phase is complete.

- [X] T002 [P] Create `Sources/SwiftSkySimulation/Vector2.swift`: `public struct Vector2: Sendable, Equatable` with `var x, y: Double`, `init(x:y:)`, `static let zero`, and `static` `+`, `+=` and `* (Vector2, Double)`. Nothing else (Principle V). Doc comment: why not `SIMD2` (R10), and that positive y is "up" for the heading convention (FR-004)
- [X] T003 [P] Create `Sources/SwiftSkySimulation/Ship.swift` with, per the contract:
  - **`ShipLimits`**: three `public let` `Double`s (`maxThrustAcceleration`, `maxAngularSpeed`, `maxAngularAcceleration`); the initialiser maps non-finite and negative values to `0` (FR-003, R6); `public static let default = ShipLimits(maxThrustAcceleration: 200, maxAngularSpeed: .pi, maxAngularAcceleration: 2 * .pi)`, doc-commented with the degree values, units, and "retune once SKY-23 fixes the scale". This is the only place the defaults are written
  - **`ControlInput`**: `public let thrust, turn: Double`; the initialiser maps non-finite to `0`, then clamps thrust to `0...1` and turn to `-1...1` (FR-007); `public static let neutral = ControlInput(thrust: 0, turn: 0)`. Doc comment: turn is a *target rate of turn* as a fraction of `maxAngularSpeed`, positive counter-clockwise (FR-004, FR-008, clarification 1)
  - **`Ship`**: `var position, velocity: Vector2`, `var heading, angularVelocity: Double`, `let limits: ShipLimits`; `init(limits: ShipLimits = .default)` gives the launch ship (origin, at rest, heading 0, not turning — FR-002); `init(position:velocity:heading:angularVelocity:limits:)` wraps the heading with `Ship.wrapped(_:)` (added in T004), and takes the angular velocity as given
  - All three `public struct … : Sendable, Equatable`, with doc comments naming the FRs, in the style of `SimulationState.swift`
- [X] T004 Add `static func wrapped(_ heading: Double) -> Double` to `Ship` in `Sources/SwiftSkySimulation/Ship.swift`: returns `heading` untouched if it is in (−π, π]; otherwise `heading.remainder(dividingBy: 2 * .pi)`, with an exact `-.pi` mapped to `.pi`. Non-finite input returns `0` so a constructed ship can never hold a NaN heading (R5, FR-005). Depends on T003
- [X] T005 Change `Sources/SwiftSkySimulation/SimulationState.swift`: add `public var ship: Ship`; `init()` and `init(tickCount:)` set `ship = Ship()`; add `public init(tickCount: UInt64, ship: Ship)`. Rewrite the type's doc comment: the state now carries the ship too, still a plain copied value (FR-001, 001 FR-012c), and the renderer ignores the ship until SKY-27 (R9). Depends on T003

**Checkpoint**: `swift build --build-system swiftbuild` succeeds; all existing tests still pass unchanged.

---

## Phase 3: User Story 1 - The ship obeys thrust and drift (Priority: P1) 🎯 MVP

**Goal**: thrust accelerates the ship along its heading, and it drifts at constant velocity when the
engine is off (FR-009, FR-010, FR-011).

**Independent Test**: `swift test --build-system swiftbuild --filter ShipMotion` — the rest, thrust
and drift tests pass (checks 3, 4).

### Implementation for User Story 1

- [X] T006 [US1] Create `Sources/SwiftSkySimulation/ShipMotion.swift` with `extension Ship { public mutating func step(_ input: ControlInput) }` implementing contract steps 5 and 6 only, for now: `let dt = FixedTimestep.tickDuration`; if `input.thrust > 0`, `velocity += Vector2(x: cos(heading), y: sin(heading)) * (input.thrust * limits.maxThrustAcceleration * dt)`; then `position += velocity * dt`. Import with `#if canImport(Darwin) import Darwin #else import Glibc #endif`, and doc-comment why this is the layer's only import and why it is not a boundary break (R3). Leave a `// Steps 1–4 (rotation): T009.` marker where rotation goes, *before* the thrust update
- [X] T007 [US1] Change `Simulation.advance` in `Sources/SwiftSkySimulation/Simulation.swift` to `advance(_ state: SimulationState, ticks: Int, input: ControlInput = .neutral)`: keep the `ticks > 0` guard; loop `ticks` times calling `next.ship.step(input)`; add `UInt64(ticks)` to the tick count as before. Update the doc comment: every tick of one call gets `input` (FR-011, clarification 2), and the default means the frame loop's existing call is unchanged (FR-010, R1). Depends on T006

### Tests for User Story 1

- [X] T008 [US1] Create `Tests/SwiftSkySimulationTests/ShipMotionTests.swift` with `@Suite("ShipMotion")` and, in a `// MARK: - Thrust and drift` section:
  - **Launch ship** (FR-002): `SimulationState().ship` is at `.zero`, at rest, heading 0, not turning, with `.default` limits of 200, π, 2π
  - **At rest stays put** (SC-001, US1-1): 10,000 neutral ticks, in one `advance` call and as 10,000 single-tick calls; `bits(ship)` unchanged in both
  - **Full thrust for one second** (SC-002, US1-2): 60 ticks at `thrust: 1` from rest at heading 0; `abs(speed − 200) < 0.0001`; `abs(position.x − 100) <= 3.34`; `position.y == 0` and `velocity.y == 0` exactly
  - **Coast** (SC-002, US1-3): continue 60 neutral ticks; the velocity's bits never change on any tick; the distance travelled over those 60 ticks is within 0.0001 units of 200; each tick's position delta equals `velocity × dt` to within 1e-12 (bitwise equality is impossible: adding a constant to a growing position rounds differently as it grows); the velocity's bits are unchanged on every tick
  - **Thrust follows the heading** (US1-4), parameterised over headings 0°, 90°, −135°, 180°: after one full-thrust tick from rest the velocity's direction matches `(cos h, sin h)` within 1e-12, and its magnitude is `200 × dt` within 1e-12
  - **Partial thrust** (US1-5), parameterised over 0.25, 0.5, 0.75: after 60 ticks the speed is `thrust × 200` within 0.0001
  - **Zero and negative ticks** (Edge Cases): a mid-flight state advanced by 0 and by −3 ticks with full thrust is bit-identical to the input
  Depends on T001, T007

**Checkpoint**: US1 is complete — thrust and drift behave as Newtonian motion, headlessly tested.

---

## Phase 4: User Story 2 - The ship turns within its limits (Priority: P2)

**Goal**: the rate of turn moves toward `turn × maxAngularSpeed` no faster than the angular
acceleration limit, and the heading stays in (−π, π] (FR-004, FR-005, FR-008).

**Independent Test**: `swift test --build-system swiftbuild --filter ShipMotion` — the turning tests
pass (check 5).

### Implementation for User Story 2

- [X] T009 [US2] In `Sources/SwiftSkySimulation/ShipMotion.swift`, replace the T009 marker with contract steps 1–4, before the thrust update (clarification 3): `target = input.turn * limits.maxAngularSpeed`; `maxStep = limits.maxAngularAcceleration * dt`; `let delta = target - angularVelocity`; if `abs(delta) <= maxStep` then `angularVelocity = target` else `angularVelocity += delta > 0 ? maxStep : -maxStep`; `heading = Ship.wrapped(heading + angularVelocity * dt)`. Comment why the snap gives exact arrival with no overshoot or sign change, and why no separate clamp at `maxAngularSpeed` is needed (R4). Update the file's doc comment to list all six steps in order

### Tests for User Story 2

- [X] T010 [US2] Add a `// MARK: - Turning` section to `Tests/SwiftSkySimulationTests/ShipMotionTests.swift`:
  - **Spin-up** (SC-003, US2-1): full turn from rest; for each tick until the rate equals `.pi` exactly, the increase is `6 × degree` within 1e-6 degree; it reaches exactly `.pi` on tick 30 or 31; over a 600-tick run it is never above `.pi`
  - **Spin-down** (SC-003, US2-2): from `angularVelocity = .pi`, neutral input; the rate reaches exactly 0 within 31 ticks, is never negative, and then stays exactly 0
  - **Mirror** (US2-3): turn −1 gives the negated rate on every tick of a 60-tick run
  - **Partial turn** (US2-4): turn 0.5 held for 60 ticks settles at exactly `0.5 * .pi`
  - **Lowered target** (Edge Cases): from the maximum rate, turn 0.25; the rate falls to exactly `0.25 * .pi` and never below it
  - **Heading wrap** (FR-005, US2-5): 6,000 ticks of full turn in each direction; the heading stays in (−π, π] on every tick; and `Ship.wrapped` of `.pi`, `-.pi`, `3 * .pi`, `-3 * .pi + 0.1`, `100`, `.nan` returns values in range, with `-.pi → .pi` and `.nan → 0`
  - **Thrust after turn** (clarification 3): from rest, one tick of `thrust: 1, turn: 1`; the velocity points along the heading *after* that tick's rotation, not heading 0
  Depends on T009

**Checkpoint**: US1 and US2 are complete — the full per-tick rule is implemented and tested.

---

## Phase 5: User Story 3 - Every run is reproducible (Priority: P3)

**Goal**: identical inputs give byte-identical results, however the ticks are batched (FR-011,
FR-012, SC-004).

**Independent Test**: `swift test --build-system swiftbuild --filter ShipMotion` — the determinism
tests pass (check 6).

### Tests for User Story 3

- [X] T011 [US3] Add a `// MARK: - Determinism (SC-004)` section to `Tests/SwiftSkySimulationTests/ShipMotionTests.swift`:
  - **Ten runs**: a fixed `[(ticks: Int, input: ControlInput)]` script totalling at least 600 ticks, which thrusts, turns both ways, holds a partial turn, coasts, and uses multi-tick advances of 1–4 ticks (the catch-up clamp); run it ten times from `SimulationState()`; every run's `bits` equals the first's. Sanity-check that the ship actually moved and turned, so identity cannot pass trivially
  - **Batching**, parameterised over n in 1, 2, 4, 60: from a mid-flight ship, `advance(s, ticks: n, input: i)` has the same `bits` as n single-tick advances (FR-011)
- [X] T012 [US3] Add a `// MARK: - Sanitisation` section to `Tests/SwiftSkySimulationTests/ShipMotionTests.swift` covering the contract's table exactly: `ControlInput(thrust: -0.5, turn: 2)`, `ControlInput(thrust: .nan, turn: -.infinity)`, `ShipLimits(maxThrustAcceleration: -1, maxAngularSpeed: .infinity, maxAngularAcceleration: 5)`; and a **zero-limits** ship (all 0) under full thrust and full turn for 60 ticks stays bit-identical to where it started (Edge Cases, FR-003, FR-007). Same file as T011, so it runs after T011

**Checkpoint**: US1–US3 are complete — the model is correct and reproducible.

---

## Phase 6: User Story 4 - The running app is unchanged (Priority: P4)

**Goal**: the frame loop runs the new step on every tick with no visible, allocation or frame-time
change (SC-005).

**Independent Test**: `./Scripts/verify.sh`, then quickstart checks 8–10.

- [X] T013 [US4] Run `./Scripts/verify.sh`; it must exit 0 with no `warning:` lines and build both app targets without touching `Sources/SwiftSkyPlatform/FrameLoop.swift` (FR-010). Then run `swift test --build-system swiftbuild` 10 times in a row; all 10 must pass (checks 1, 2, SC-006). Record the results in `specs/004-ship-newtonian-motion/quickstart.md` → Evidence
- [X] T014 [US4] Quickstart check 11, the headless before/after benchmark (required, R7): in the session scratchpad, build an `-O` executable with `swiftc` from `Sources/SwiftSkySimulation/*.swift` plus a `main.swift` that times 10,000,000 single-tick `Simulation.advance` calls with `ContinuousClock` and counts allocations around the loop with `malloc_zone_statistics(nil, &stats)` (`size_in_use` / `blocks_in_use` before and after). Run it 3 times against `main`'s sources (via `git show main:<path>` into the scratchpad, no input) and 3 times against this branch's (full thrust, full turn). Record ns per tick before and after, and the branch's allocation count, which must be 0, in `specs/004-ship-newtonian-motion/quickstart.md` → Evidence. Nothing from this is checked in
- [X] T015 [US4] Quickstart checks 8–10 on macOS and iOS: allocations over 60 s, frame time before (`main`) and after (this branch) from the 003 overlay, and Debug / `--no-debug-overlay` / Release visible output. Record results — or, for any check that cannot be run in this session, record it as **not run** with the reason — in `specs/004-ship-newtonian-motion/quickstart.md` → Evidence

**Checkpoint**: all four stories are complete.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T016 [P] Update the comment at `Package.swift:60` from "imports nothing" to "declares no dependencies; imports only the C library (Darwin), for `cos`/`sin` in ShipMotion.swift" (R3). Update `CLAUDE.md`: add `specs/004-ship-newtonian-motion` (one ship with Newtonian motion in the logic layer, not yet drawn) to "Built so far", and under Key locations name `Ship.swift`, `ShipMotion.swift` and the fact that `ShipMotion.swift` is the logic layer's only file with an import (`Darwin`, R3)
- [X] T017 [P] Update SKY-24's status through the repo's `tickets` skill once T013 and T014 pass. Set to `in-review` (implemented, not merged — the backlog's definition); it moves to `done` when the branch merges, as SKY-28/SKY-29 did
- [X] T018 Final pass over `specs/004-ship-newtonian-motion/`: every FR and SC maps to a passing test or a recorded quickstart result; mark all tasks `[X]`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: none; compiles once T005 lands.
- **Foundational (Phase 2)**: T002 ∥ T003 → T004, T005.
- **US1 (Phase 3)**: after Phase 2. T006 → T007 → T008.
- **US2 (Phase 4)**: after T006 (same file). T009 → T010.
- **US3 (Phase 5)**: after T010 (the full rule, same test file). T011 → T012.
- **US4 (Phase 6)**: after US1–US3. T013 → T014 → T015.
- **Polish (Phase 7)**: T016 and T017 after T013 and T014; T018 last, after T015.

### User Story Dependencies

- **US1** needs only Phase 2.
- **US2** extends US1's `step` in the same file, so it follows US1.
- **US3** tests the whole rule, so it follows US2.
- **US4** validates everything.

### Parallel Opportunities

- T001 ∥ T002 ∥ T003.
- T016 ∥ T017.
- The stories are sequential by design: they build one six-step function.

## Parallel Example: Phase 1–2

```text
Task: "T001 Create Tests/SwiftSkySimulationTests/StateBits.swift"
Task: "T002 Create Sources/SwiftSkySimulation/Vector2.swift"
Task: "T003 Create Sources/SwiftSkySimulation/Ship.swift"
```

## Implementation Strategy

### MVP first (User Story 1)

1. Phases 1 and 2: the types and the state field.
2. Phase 3: thrust and drift, tested. **Stop and validate**: `--filter ShipMotion`.

### Incremental delivery

1. US1 → a ship that accelerates and drifts along a fixed heading.
2. US2 → it turns within its limits. The model is feature-complete for SKY-25.
3. US3 → reproducibility proven.
4. US4 → the running app confirmed unchanged.
