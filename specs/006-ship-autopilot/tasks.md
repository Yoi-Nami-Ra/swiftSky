---

description: "Task list for 006-ship-autopilot"
---

# Tasks: Ship Autopilot — Turn, Burn, Flip and Brake

**Input**: Design documents from `/specs/006-ship-autopilot/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/autopilot.md, quickstart.md

**Tests**: Required. FR-017 and the ticket's "done when" call for tests, and constitution Principle II
requires tests for game logic. There is no drawing code in this feature.

**Organization**: tasks are grouped by user story, so each story can be implemented and validated
on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US5)
- Paths are relative to the repository root. `R<n>` refers to research.md, `check <n>` to
  quickstart.md, "the contract" to contracts/autopilot.md.

## Path Conventions

- The logic layer is `Sources/SwiftSkySimulation/`, its tests `Tests/SwiftSkySimulationTests/`. No
  other layer changes (plan.md).
- Angles are radians in code (004 R2). Run tests with
  `swift test --build-system swiftbuild --filter Autopilot`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: extend the bit-exact helper and add the flight helper every story's tests use.

- [X] T001 [P] Extend `Tests/SwiftSkySimulationTests/StateBits.swift`: `bits(_ state:)` appends, after the ship's values, the autopilot's tolerance bit patterns, a presence flag plus the destination's `x`/`y` bit patterns for the order (zeros when absent), and a phase code (0 = none, 1…5 = aligning…arrived). Existing 004 callers keep working because they only compare equal-length lists from the same build
- [X] T002 [P] Create `Tests/SwiftSkySimulationTests/AutopilotTests.swift` with a file-private flight helper `fly(_ state: SimulationState, maxTicks: Int) -> Flight` that advances one tick at a time with `Simulation.advance(_:ticks:)` until the phase is `.arrived` or the cap is hit, recording: ticks to arrival, the phase sequence with consecutive duplicates collapsed, the tick the first `.flipping` starts and the distance covered by then, the maximum overshoot along the start → destination unit vector `û` (`max((p − D)·û)`; when the start equals the destination, `û` is the initial velocity's direction, and if that is zero too, overshoot and passes are not measured), the accumulated signed bearing sweep of `p − D` around the destination (sum of wrapped angle deltas), the number of destination passes (sign changes of `(p − D)·û` after leaving the start), and the final state. Also a `referenceTime(distance:angle:limits:)` helper implementing SC-002's ideal pilot: rest-to-rest turn time for `angle` plus `2·t1 + Tflip`, with `t1` solving `a·t1² + a·t1·Tflip = distance` and `Tflip` the rest-to-rest 180° time. Depends on T006 to compile

**Checkpoint**: none on its own; compiles once Phase 2 exists.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the value types, the state field and the `advance` overloads every story uses
(data-model.md, the contract).

**⚠️ CRITICAL**: no user story work can begin until this phase is complete.

- [X] T003 Create `Sources/SwiftSkySimulation/Autopilot.swift` with, per the contract:
  - **`MoveOrder`**: `public let destination: Vector2`; `public init?(destination:)` returns `nil` if either component is non-finite (FR-001, FR-002)
  - **`AutopilotPhase`**: `public enum` with `aligning, burning, flipping, braking, arrived`, each case doc-commented with its meaning (FR-005)
  - **`ArrivalTolerances`**: `public let position, speed: Double`; initialiser maps negative or non-finite to `0`; `public static let default = ArrivalTolerances(position: 1, speed: 1)` — the only place the defaults are written (FR-010, R8)
  - **`Autopilot`**: `public let tolerances`, `public private(set) var order: MoveOrder?`, `public private(set) var phase: AutopilotPhase?`, `public init(tolerances: ArrivalTolerances = .default)`; `public mutating func setOrder(_ order: MoveOrder, for ship: Ship)` sets `order`, clears `phase`, then sets `phase` from the law's classification of `ship` (T004; the two files compile together) so the read-out is valid at once. Doc comment states the invariant `order == nil ⇔ phase == nil` and that `phase` is the only memory between ticks (R6, FR-014)
  - All `Sendable, Equatable`, doc comments naming FRs, in the style of `Ship.swift`
- [X] T004 Create `Sources/SwiftSkySimulation/AutopilotLaw.swift` (with the same `#if canImport(Darwin) import Darwin #else import Glibc #endif` header and comment as `ShipMotion.swift`): an `extension Autopilot` with `public mutating func control(for ship: Ship) -> ControlInput` and an internal pure `func evaluate(_ ship: Ship) -> (input: ControlInput, phase: AutopilotPhase)` that implements the contract's steps 1–8 exactly, including every division guard (FR-013). Tuning constants as documented `static let`s: `brakingMargin = 0.9` (R3), `tailGain = 10` (R4), `thrustCone = 0.1` (R5), `holdFraction = 0.5` (R5), `settleSpeed = 0.001` (R5). Helpers: `restToRestTurnTime(_ angle:limits:)` (R2), heading wrap via `Ship.wrapped(_:)`. Without an order, `control(for:)` returns `.neutral` and leaves `phase` `nil`. No allocation, no loops (FR-015). Depends on T003
- [X] T005 Change `Sources/SwiftSkySimulation/SimulationState.swift`: add `public var autopilot: Autopilot` (set to `Autopilot()` by every existing initialiser), `@discardableResult public mutating func setOrder(to destination: Vector2) -> Bool` (builds `MoveOrder`; on `nil` returns `false` and changes nothing; else calls `autopilot.setOrder(_:for: ship)` and returns `true`), and `public var distanceRemaining: Double?` (`nil` without an order, else the Euclidean distance from `ship.position` to the destination). Update the type's doc comment: the state now also carries the order and the autopilot's memory so a copy flies the same path (FR-003, FR-014). Depends on T003 and T004
- [X] T006 Change `Sources/SwiftSkySimulation/Simulation.swift`: replace `advance(_:ticks:input: = .neutral)` with two overloads (R7): `advance(_:ticks:)` — for each tick, `input = next.autopilot.control(for: next.ship)` when `next.autopilot.order != nil`, else `.neutral`, then `next.ship.step(input)`; and `advance(_:ticks:input:)` — the explicit 004 loop, order and phase untouched. Both return `state` unchanged for `ticks <= 0` and add `ticks` to `tickCount`. Rewrite the doc comments (FR-011, clarification 3). Depends on T005 (and T004 for `control(for:)`)

**Checkpoint**: `swift build --build-system swiftbuild` succeeds; every existing test passes unchanged
(`FrameLoop`'s `Simulation.advance(state, ticks:)` compiles as is and behaves identically with no
order).

---

## Phase 3: User Story 1 — Send a resting ship somewhere and have it stop there (Priority: P1) 🎯 MVP

**Goal**: from rest, the ship aligns, burns, flips before halfway, brakes and arrives within
tolerance, without overshoot, within SC-002's time bound, and holds still.

**Independent Test**: `swift test --build-system swiftbuild --filter Autopilot` — the arrival-grid
tests pass (checks 3, 4, 5, 9).

### Tests for User Story 1

- [X] T007 [US1] In `Tests/SwiftSkySimulationTests/AutopilotTests.swift`, add a parameterised `@Test` over 5 distances {0.5, 10, 100, 1,000, 10,000} × 16 directions (`k·π/8` relative to heading 0), each from a resting launch ship: arrives (phase `.arrived`) within 1 unit and below 1 unit/s (SC-001, US1-1, US1-2)
- [X] T008 [US1] In the same file, for the same grid: ticks to arrival × dt ≤ 1.1 × `referenceTime` + 0.5 s (SC-002); overshoot ≤ 1 unit (SC-003, US1-3); for cases with a flip, the straight-line distance from the start when it begins is < half the trip (US1-4, FR-007); the collapsed phase sequence is in canonical order (aligning < burning < flipping < braking < arrived, each at most once) (FR-005)
- [X] T009 [US1] In the same file: the 1,000-unit order along heading 0 has the collapsed phase sequence `[burning, flipping, braking, arrived]`, and one along heading π has `[aligning, burning, flipping, braking, arrived]` (US1-1, US1-2, FR-005)
- [X] T010 [US1] In the same file, station-keeping: after arriving from a 1,000-unit order and from a 10-unit order at 45°, advance 10,000 more ticks one at a time: phase `.arrived` and distance ≤ 1 on every tick; at the end speed < 0.01 u/s and `angularVelocity == 0` (SC-008, US1-5, FR-009). Then nudge it with `advance(_:ticks:input:)` (full thrust, 30 ticks) so it leaves the position tolerance: the next autopilot-driven tick's phase is not `.arrived`, and it arrives again within tolerance (FR-009 resume clause)

### Implementation for User Story 1

- [X] T011 [US1] Run the US1 tests against T004's law and tune only within the contract (the constants of R3–R5 may be adjusted, each change recorded in research.md with its reason) until T007–T010 pass. Update `Sources/SwiftSkySimulation/AutopilotLaw.swift` doc comments to match what shipped

**Checkpoint**: MVP — a resting ship flies any order and holds station.

---

## Phase 4: User Story 2 — Send a moving ship somewhere without swinging round the target (Priority: P2)

**Goal**: from arbitrary initial velocities the ship cancels unwanted motion and arrives without
orbiting or ringing.

**Independent Test**: the moving-start grid passes (check 6).

### Tests for User Story 2

- [X] T012 [US2] In `Tests/SwiftSkySimulationTests/AutopilotTests.swift`, add a parameterised `@Test` over ≥ 64 starting conditions: speeds {100, 400, 1,000} u/s × 8 velocity directions (`k·π/4` relative to the ship → destination bearing) × destination distances {0, 50, 1,000, 5,000} (≥ 96 cases), ship heading 0: arrives within tolerance within 3,600 ticks (60 s); `abs(bearing sweep) < 2π`; destination passes ≤ 2 (SC-004)
- [X] T013 [US2] In the same file, the named scenarios: moving fast straight at a destination 20 units away passes it and returns (US2-2); moving directly away (US2-3); ordered to its own position while moving (US2-4); moving across the line (US2-1) — each arrives within tolerance

### Implementation for User Story 2

- [X] T014 [US2] Make T012–T013 pass in `Sources/SwiftSkySimulation/AutopilotLaw.swift`, again only within the contract (hold rule, cone and margins); record any constant change in research.md. US1 tests must stay green

**Checkpoint**: moving starts arrive without orbiting.

---

## Phase 5: User Story 3 — Change the order mid-flight (Priority: P3)

**Goal**: a new order replaces the old immediately, in any phase.

**Independent Test**: the re-order tests pass (check 7).

### Tests for User Story 3

- [X] T015 [US3] In `Tests/SwiftSkySimulationTests/AutopilotTests.swift`, add a parameterised `@Test` over the phases aligning, burning, flipping, braking and arrived: fly a first order from rest (start facing away so aligning occurs) until the phase first equals the case, call `setOrder(to:)` with a second destination 2,000 units off to one side, fly on: arrives at the second destination within tolerance. Assert "no dependence on the old destination": a state built with the same ship and only the second order produces a bit-identical next state (SC-006, US3-1, US3-2)
- [X] T016 [US3] In the same file: re-ordering to the same destination mid-flight still arrives within tolerance (US3-3); `setOrder(to:)` with a NaN or infinite component returns `false` and leaves `bits(state)` unchanged (FR-002)

### Implementation for User Story 3

- [X] T017 [US3] Confirm `setOrder` in `Sources/SwiftSkySimulation/Autopilot.swift` and `Sources/SwiftSkySimulation/SimulationState.swift` makes T015–T016 pass; fix any dependence on stale state (the only memory is `phase`, re-evaluated at `setOrder`)

**Checkpoint**: orders can be changed at any time.

---

## Phase 6: User Story 4 — Watch what the autopilot is doing (Priority: P4)

**Goal**: order, phase and distance remaining are readable from the state.

**Independent Test**: the read-out tests pass (check 8).

### Tests for User Story 4

- [X] T018 [P] [US4] In `Tests/SwiftSkySimulationTests/AutopilotTests.swift`: a fresh state has `autopilot.order == nil`, `phase == nil`, `distanceRemaining == nil`, and advancing it 600 ticks is bit-identical to advancing with `input: .neutral` (US4-1, FR-011); after `setOrder(to: (300, 400))` on the launch ship, `phase != nil` straight away and `distanceRemaining == 500` (US4-3, FR-003); `order == nil ⇔ phase == nil` holds on every tick of a flight
- [X] T019 [P] [US4] In the same file, edge cases: an order within both tolerances of a resting ship is `.arrived` immediately and the ship does not move over 60 ticks; a ship with `ShipLimits(maxThrustAcceleration: 0, …)`, one with zero angular limits, and one with all zero limits, each ordered 1,000 units away for 3,600 ticks, keep every state component finite and the order stays in progress (FR-013, Edge Cases); a destination at (10⁶, −10⁶) is reached within tolerance (Edge Cases); the exactly-behind case turns counter-clockwise on its first turning tick (FR-012); `ArrivalTolerances(position: -1, speed: .nan)` sanitises to (0, 0) and `.default` is (1, 1); a flight with `state.autopilot = Autopilot(tolerances: ArrivalTolerances(position: 5, speed: 5))` arrives within 5 units and below 5 u/s, and no later than with the defaults (FR-010)

### Implementation for User Story 4

- [X] T020 [US4] Make T018–T019 pass in `Sources/SwiftSkySimulation/Autopilot.swift`, `AutopilotLaw.swift` and `SimulationState.swift`

**Checkpoint**: downstream tickets (SKY-26, SKY-29) can read the autopilot.

---

## Phase 7: User Story 5 — Every run is reproducible, and the app is unchanged (Priority: P5)

**Goal**: bit-exact determinism, batching equivalence, explicit-input semantics, unchanged app.

**Independent Test**: determinism tests pass (check 10); checks 1, 2, 13.

### Tests for User Story 5

- [X] T021 [US5] In `Tests/SwiftSkySimulationTests/AutopilotTests.swift`: the SC-005 scenario — start moving at (120, −80) u/s, order to (1,500, 700), re-order to (−800, 300) on the first burning tick, to (400, −1,200) on the first flipping tick and to (0, 0) on the first braking tick, ≥ 1,200 ticks in all using a fixed pattern of advances of 1, 2, 3 and 4 ticks — run 10 times: identical `bits` (SC-005, US5-1)
- [X] T022 [US5] In the same file: one flight advanced 4 ticks at a time vs 1 tick at a time gives identical `bits` at every multiple of 4 (US5-2, FR-011); advancing an ordered state 30 ticks with an explicit `input:` leaves `autopilot` bit-identical and the next autopilot-driven tick continues and still arrives (FR-011, clarification 3); a copy of a mid-flight state flown separately ends bit-identical to the original (FR-014)

### Implementation for User Story 5

- [X] T023 [US5] Make T021–T022 pass; any nondeterminism is a defect in `Sources/SwiftSkySimulation/AutopilotLaw.swift` or `Simulation.swift`, not a test to loosen

**Checkpoint**: all stories complete.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T024 Run `./Scripts/verify.sh` (check 1) and `swift test --build-system swiftbuild` 10 times in a row (check 2); record both in `specs/006-ship-autopilot/quickstart.md` Evidence
- [X] T025 Run the headless before/after benchmark (check 14) in the session scratchpad on `main` and on this branch, 3 runs each; record ns per tick and allocation counts in `specs/006-ship-autopilot/quickstart.md` Evidence
- [X] T026 Record checks 3–10 and the manual checks 11–13 (run, or "Not run" with the structural argument, as 004 did) in `specs/006-ship-autopilot/quickstart.md` Evidence
- [X] T027 [P] Update `CLAUDE.md`: add `specs/006-ship-autopilot` to "Built so far" (a move order, the autopilot and its phases in the logic layer; nothing issues orders yet) and the Key locations entry for `Autopilot.swift` / `AutopilotLaw.swift` (and that `AutopilotLaw.swift` is the second file with a `Darwin` import)
- [X] T028 [P] Update `.tickets/25.yaml` status to `done`; record any follow-up (e.g. SKY-29's order lines) only if not already ticketed

---

## Dependencies & Execution Order

- **Setup (Phase 1)**: T001, T002 can be written first but compile only after Phase 2.
- **Foundational (Phase 2)**: T003 → T004 → T005 → T006 (T005 needs T004's `evaluate` for
  `setOrder`; T006 needs `control(for:)`). Blocks every story.
- **US1 (Phase 3)**: after Phase 2. MVP.
- **US2 (Phase 4)**: after US1 (tunes the same law; US1 tests guard regressions).
- **US3, US4, US5 (Phases 5–7)**: after US1; independent of each other in behaviour, but all append
  to `AutopilotTests.swift`, so run them in order.
- **Polish (Phase 8)**: after all stories.

### Parallel Opportunities

- T001 ∥ T002 (different files).
- T018 ∥ T019 are marked [P] as independent test groups, but share one file — parallel only across
  separate branches/agents with a merge.
- T027 ∥ T028 (different files).

### Parallel Example: Phase 1

```text
Task: "T001 Extend StateBits.swift with autopilot bits"
Task: "T002 Create AutopilotTests.swift with fly() and referenceTime() helpers"
```

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 + Phase 2 → the build passes with all existing tests.
2. Phase 3 → a resting ship flies any order and holds station. **Stop and validate**: checks 3–5, 9.

### Incremental Delivery

US2 (moving starts) → US3 (re-orders) → US4 (read-out and edges) → US5 (determinism) → Polish. Each
phase ends green and is committed on its own.
