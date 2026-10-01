---

description: "Task list for 010-ship-path-prediction"
---

# Tasks: Predict the Ship's Planned Path

**Input**: Design documents from `/specs/010-ship-path-prediction/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/planned-path.md, quickstart.md

**Tests**: Required. FR-013 calls for headless tests of the prediction (Principle II), and SC-001–SC-006
are written as test criteria. The Debug log line (FR-014) and the running-app checks (SC-007, SC-009)
are verified through quickstart.md.

**Organization**: Tasks are grouped by user story, so each story can be implemented and validated on
its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US3)
- Paths are relative to the repository root. `R<n>` refers to research.md and `check <n>` to
  quickstart.md; "the contract" is contracts/planned-path.md.

## Path Conventions

- Logic layer: `Sources/SwiftSkySimulation/`, tests in `Tests/SwiftSkySimulationTests/` (imports
  `Foundation`, `Testing`, `@testable import SwiftSkySimulation`, as `AutopilotTests.swift`). Exactness
  is asserted with `bits(_:)` from `StateBits.swift`, never `==`, wherever the spec says "bit for bit".
- The logic layer imports nothing new. `SwiftSkyRendering`, `Package.swift` and `Scripts/verify.sh`
  MUST NOT change. In `SwiftSkyPlatform` only `Instrumentation.swift`'s `recordOrder` and its one call
  in `FrameLoop.swift` change (R8).
- Run the tests with `swift test --build-system swiftbuild --explicit-target-dependency-import-check=error`.

---

## Phase 1: Setup (Shared Infrastructure)

No setup: the logic layer and its test target exist, and `InlineArray` is in the standard library.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared tick, the path type with its thinning, and its test bits, which every story
uses.

- [ ] T001 [P] Change `Sources/SwiftSkySimulation/Simulation.swift`: add `static func tick(_ ship: inout Ship, _ autopilot: inout Autopilot)` (internal) whose body is `let input = autopilot.control(for: ship); ship.step(input)`, and make `advance(_:ticks:)`'s loop call `tick(&next.ship, &next.autopilot)` instead of its two inline lines. Doc comment: one tick flown by the autopilot, shared by `advance(_:ticks:)` and the path prediction so the prediction flies the real flight by construction (R3, 010 FR-002); the phase it records is evaluated from the ship at the start of the tick (006 R6). `advance(_:ticks:input:)` is unchanged. Every existing test must still pass unchanged
- [ ] T002 [P] Create `Sources/SwiftSkySimulation/PlannedPath.swift` (no imports) with `public struct PlannedPath: Sendable, Equatable` per the contract and data-model.md: `typealias Points = InlineArray<256, Vector2>` (private storage `points`), `public static let capacity = Points.count`, `public static let maxFlightTicks = 60 * FixedTimestep.tickRate`, `public static let empty`, the `public private(set)` fields `count`, `startTick`, `spacing`, `endTick`, `reachesArrival`, `isEmpty`, `subscript(index:)` (precondition `0 ≤ index < count`), `last`, and a hand-written `==` over the fields and points `0..<count` only (R7). Internal recording API: `init(start:tick:)` (one point, `spacing` 1), `mutating func append(_ position: Vector2)` and `mutating func finish(reachesArrival: Bool)` implementing the contract's thinning exactly — count the ticks recorded, store a point when the tick count is a multiple of `spacing`, compacting first when full (keep even indices, halve `count`, double `spacing`); otherwise keep it as the pending final position; `finish` stores a pending final position as the last point (compacting first if full) and sets `endTick = startTick + ticks`. Doc comments: what the path is and who reads it (SKY-30, 010 FR-001); why inline storage (no allocation, no sharing between copies, R2); the tick of every point (FR-004); the thinning rule and its guarantees — ≤ 256 always, every tick for flights of ≤ 255 ticks, ≥ 128 otherwise, the final position always last (FR-005, R5); the cap derived from the tick rate (FR-006, R6)
- [ ] T003 Change `Tests/SwiftSkySimulationTests/StateBits.swift`: add `func bits(_ path: PlannedPath) -> [UInt64]` — `count`, `startTick`, `spacing`, `endTick`, the arrival flag as 0/1, then the x and y bit patterns of points `0..<count` (R7), with a doc comment (010). `bits(_ state:)` is extended in T005, once the state has the field. Depends on T002

**Checkpoint**: `swift build` passes with no warnings; every existing test passes unchanged.

---

## Phase 3: User Story 1 - Know where an order will take the ship (Priority: P1) 🎯 MVP

**Goal**: Every accepted order carries a path that starts on the ship and ends, bit for bit, where the
real simulation first reports arrival.

**Independent Test**: `./Scripts/verify.sh` runs the grid tests; quickstart checks 3, 4 and 13.

### Implementation for User Story 1

- [ ] T004 [US1] Add to `Sources/SwiftSkySimulation/PlannedPath.swift`: `init(predictingFrom ship: Ship, autopilot: Autopilot, tickCount: UInt64)` (internal), following the contract's prediction steps 1–5 on local copies — `.empty` without an order; one point when `autopilot.phase == .arrived`; else up to `maxFlightTicks` iterations of `Simulation.tick(&ship, &autopilot)`, `append(ship.position)`, and `finish(reachesArrival: true)` on the first `arrived` phase, `finish(reachesArrival: false)` at the cap. Doc comment: why it stops on the first state that *reports* arrived and ends on that state's position, the same predicate as the frame loop's arrival log (R4, FR-003, SC-009); that it touches only its copies (FR-009); bounded work and no allocation (FR-011). Depends on T001, T002
- [ ] T005 [US1] Change `Sources/SwiftSkySimulation/SimulationState.swift`: add `public private(set) var plannedPath: PlannedPath`, set to `.empty` in `init(tickCount:ship:)` (the other initialisers delegate to it); in `setOrder(to:)`, after `autopilot.setOrder(order, for: ship)`, set `plannedPath = PlannedPath(predictingFrom: ship, autopilot: autopilot, tickCount: tickCount)`; a refused order still returns `false` before touching anything. Update the type's doc comment (the state now carries the current order's planned path, which the renderer receives but draws nothing from until SKY-30; still a plain value, now about 4.3 KB, no heap) and `setOrder(to:)`'s (it also predicts the path, FR-007). In `Tests/SwiftSkySimulationTests/StateBits.swift`, append `bits(state.plannedPath)` to `bits(_ state:)` and mention the path in its doc comment, so every existing bit-for-bit comparison now covers the path too (R7). Depends on T003, T004
- [ ] T006 [US1] Create `Tests/SwiftSkySimulationTests/PlannedPathTests.swift` with `@Suite("Planned path")` and a helper that flies a copy of an ordered state one tick at a time with `Simulation.advance(_:ticks: 1)`, recording the ship's position at every tick, until `autopilot.phase == .arrived` or 3,600 ticks. Tests, each comparing the state's `plannedPath` with that real flight via bit patterns: (a) 006's rest grid, `arguments: AutopilotTests.restDistances, 0..<16`: with `θ = Double(direction) * .pi / 8`, the state is `AutopilotTests.ordered(to: Vector2(x: distance * cos(θ), y: distance * sin(θ)))` (a launch ship at the origin, heading 0) — point 0 is the ship's position at `startTick == tickCount`; every point `i < count − 1` equals the real position at `startTick + i · spacing`; the last point and `endTick` equal the first `arrived` state's position and tick count; `reachesArrival` (SC-001, SC-002, US1-1, US1-3); (b) the same over 006's moving-start grid, `arguments: [100.0, 400, 1_000], [0.0, 50, 1_000, 5_000]` with 8 directions each, built with `AutopilotTests.moving(_:to:)` (SC-001, SC-002, US1-2); (c) the four named moving starts of 006, each `AutopilotTests.moving(velocity, to: destination)` — too close to stop: velocity (400, 0) to (20, 0); moving away: (−300, 0) to (500, 0); ordered to its own position: (0, 200) to (0, 0); moving across: (0, 300) to (1,000, 0) (the cases are a local list in `AutopilotTests.namedMovingStarts`, so copy them); (d) already there: a ship at rest ordered to its own position gives `count == 1`, `startTick == endTick`, `reachesArrival` (US1-4). Depends on T005
- [ ] T007 [P] [US1] Change `Sources/SwiftSkyPlatform/Instrumentation.swift`: `recordOrder(_ outcome: MoveOrderOutcome, viewPoint: Vector2, path: PlannedPath)`; for `.ordered`, extend the line to `order view=(…) world=(…) predicted=(x, y) ticks=N points=P arrives=yes|no` with `path.last` and `path.endTick` interpolated exactly as `recordArrival` interpolates its position and tick count, `path.count`, and `path.reachesArrival` with `format: .answer` (R8, contract); the dropped lines are unchanged; give the Release no-op the same parameter. Change `Sources/SwiftSkyPlatform/FrameLoop.swift`'s one call to pass `path: state.plannedPath`. Update both doc comments (010 FR-014). Depends on T005
- [ ] T008 [US1] Run `./Scripts/verify.sh`, then quickstart check 13 (Debug build, log streaming, 10 orders flown to arrival, on each platform where a session allows) and record checks 3, 4 and 13 in the Evidence section of `specs/010-ship-path-prediction/quickstart.md`. Depends on T006, T007

**Checkpoint**: Every order carries a correct path, and the Debug log shows it. MVP complete.

---

## Phase 4: User Story 2 - Long and endless flights still fit (Priority: P2)

**Goal**: The thinning keeps every path within 256 points, and the cap ends impossible flights.

**Independent Test**: `./Scripts/verify.sh` runs the thinning and cap tests; quickstart checks 5 and 6.

### Tests for User Story 2

- [ ] T009 [US2] Add to `Tests/SwiftSkySimulationTests/PlannedPathTests.swift` a thinning test over every flight length `n` in `0...3_700`: start a path with `PlannedPath(start: p(0), tick: 1_000)`, `append(p(k))` for `k = 1…n`, then `finish(reachesArrival: true)`, where `p(k) = Vector2(x: Double(k), y: -Double(k))` encodes its own tick. Expect: `count ≤ PlannedPath.capacity`; for `n ≤ 255`, `count == n + 1` and `spacing == 1`; otherwise `128 ≤ count ≤ 256`; `spacing` is a power of two; point `i < count − 1` is `p(i · spacing)`; the last point is `p(n)` and `endTick == 1_000 + n`; `startTick == 1_000` (SC-003, FR-004, FR-005, US2-1, US2-2). Depends on T002
- [ ] T010 [US2] Add to `Tests/SwiftSkySimulationTests/PlannedPathTests.swift`: (a) capped flights, parameterised over a ship with `maxThrustAcceleration` 0 ordered 1,000 units ahead, and a ship with `maxAngularAcceleration` 0 facing away (heading π) from a destination 1,000 units along +x — each path ends on the real state's position after exactly 3,600 ticks of `Simulation.advance`, with `endTick − startTick == 3_600`, `reachesArrival == false`, `count == 226` and `spacing == 16` (SC-004, FR-006, US2-3); (b) the work bound: in every prediction made by this suite, `endTick − startTick ≤ UInt64(PlannedPath.maxFlightTicks)` — assert it in the grid tests' shared helper (SC-004). Depends on T006

### Implementation for User Story 2

- [ ] T011 [US2] No new code: the thinning and the cap are T002 and T004. Run `./Scripts/verify.sh` and record quickstart checks 5 and 6 in the Evidence section of `specs/010-ship-path-prediction/quickstart.md`. Depends on T009, T010

**Checkpoint**: Paths of every length fit; capped flights end where they should.

---

## Phase 5: User Story 3 - Planned once per order, free on every frame (Priority: P3)

**Goal**: The path changes only with the order, is deterministic, and costs no allocation or dropped
frame.

**Independent Test**: `./Scripts/verify.sh` runs the per-order and determinism tests; quickstart checks
7–12.

### Tests for User Story 3

- [ ] T012 [US3] Add to `Tests/SwiftSkySimulationTests/PlannedPathTests.swift`: (a) advancing an ordered state by each of 1, 7, 60, 333 and 1,000 ticks, with `advance(_:ticks:)` and with `advance(_:ticks:input:)`, leaves `bits(state.plannedPath)` unchanged (SC-005, FR-008, US3-1); (b) a new order mid-flight replaces the path with exactly `PlannedPath(predictingFrom:autopilot:tickCount:)` of the re-ordered state, starting at the ship's current position and tick, and so does re-ordering to the same destination (US3-2, edge cases); (c) a refused order (`.nan` and `.infinity` components) leaves `bits(state)` unchanged (US3-3); (d) a fresh state's path is empty, and so is the path of a state advanced 600 ticks with no order; (e) FR-009: after `setOrder(to:)`, the ship, the autopilot and the tick count are bit-identical to a copy whose `autopilot.setOrder(_:for:)` was called directly. Depends on T005
- [ ] T013 [US3] Check that 006's `tenRunsAreIdentical` (in `Tests/SwiftSkySimulationTests/AutopilotTests.swift`, unchanged) now compares paths through the extended `bits(_ state:)` (T003), and add to `PlannedPathTests.swift` one assertion that the scenario's final state, `AutopilotTests.scenario()`, has a non-empty path, so the determinism check is known to cover one (SC-006, US3-4). Depends on T003, T005

### Implementation for User Story 3

- [ ] T014 [US3] Quickstart check 9: build a throwaway `-O -wmo` executable in the scratchpad (not committed) from `Sources/SwiftSkySimulation/*.swift` plus a `main.swift` that, 3 runs each, times with `ContinuousClock` and counts allocations with `malloc_zone_statistics` around (a) 1,000 capped predictions (zero-thrust ship) and 1,000 predictions of a 1,000-unit order from rest, and (b) 10,000,000 single-tick `Simulation.advance` calls, on this branch and on `main` (`main`'s sources extracted into the scratchpad with `git archive main Sources/SwiftSkySimulation | tar -x -C <dir>`, which leaves the repository untouched); include a control that allocates, to prove the counter works. Record the numbers in the Evidence section of `specs/010-ship-path-prediction/quickstart.md` (SC-007, FR-011, Principle III, R10). Depends on T005
- [ ] T015 [US3] Run quickstart checks 10, 11 and 12 where an interactive session allows, otherwise record each as not run with its reason and the structural evidence (inline storage, check 9's zero allocations), in the Evidence section of `specs/010-ship-path-prediction/quickstart.md`. Depends on T007

**Checkpoint**: The path is planned once per order, deterministic, and free on every frame.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T016 [P] Update `CLAUDE.md`: add `specs/010-ship-path-prediction` to "Built so far" (giving an order also predicts its planned path in the logic layer; nothing draws it yet), and to "Key locations" `Sources/SwiftSkySimulation/PlannedPath.swift` (up to 256 positions in an `InlineArray`, thinned by halving, the tick of every point, the 3,600-tick cap; predicted by `SimulationState.setOrder(to:)` through `Simulation.tick`, which `advance(_:ticks:)` shares), and the `predicted=… ticks=… points=… arrives=…` fields on the Debug order log line
- [ ] T017 [P] Update `.tickets/26.yaml` `status` to `done`
- [ ] T018 Run `./Scripts/verify.sh` and quickstart checks 1, 2, 7 and 8, and fill in the rest of the Evidence section of `specs/010-ship-path-prediction/quickstart.md`, marking any check not run with its reason

---

## Dependencies & Execution Order

- **Foundational (Phase 2)**: T001 ∥ T002; T003 after T002. Blocks every story.
- **US1 (Phase 3)**: T004 → T005 (also extends `bits(_ state:)`) → T006; T007 after T005, in parallel with T006; T008 last. MVP.
- **US2 (Phase 4)**: T009 after T002 (can start as soon as the type exists); T010 after T006; T011 last.
- **US3 (Phase 5)**: T012, T013 and T014 after T005; T015 after T007.
- **Polish (Phase 6)**: after all stories.

### Parallel Opportunities

- T001 ∥ T002 (different files).
- T006 ∥ T007 (logic tests vs platform log line).
- T016 ∥ T017.
- T006, T009, T010, T012 and T013 share `PlannedPathTests.swift`: sequential.

### Parallel Example: User Story 1

```text
Task: "T006 Create PlannedPathTests.swift: the grids against the real flight"
Task: "T007 Add the prediction fields to the Debug order log line"
```

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 2: the build passes and every existing test still does.
2. Phase 3: orders carry correct paths. **Stop and validate**: checks 3, 4 and 13.

### Incremental Delivery

US2 → US3 → Polish. Each phase ends green and is committed on its own.
