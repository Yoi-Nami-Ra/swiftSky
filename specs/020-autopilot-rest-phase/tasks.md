---

description: "Task list for 020 — a re-order from rest starts in aligning (SKY-46)"
---

# Tasks: A Re-order From Rest Starts in Aligning

**Input**: Design documents from `/specs/020-autopilot-rest-phase/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/phase-rule.md, quickstart.md

**Tests**: Required by the spec (FR-005, FR-005a, FR-006, FR-007) and by constitution II. All tests are
headless Swift Testing in `SwiftSkySimulationTests`.

**Organization**: Both stories are P1. **US2 runs first**, because its fingerprints must be recorded from the
law **before** the fix (research R3, spec Assumptions). US1 then adds the failing reproduction and the fix.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2)

## Phase 1: Setup

**Purpose**: The new suite and its shared station-keeping setup. `Sources/` is not touched yet.

- [ ] T001 Confirm `Sources/SwiftSkySimulation/AutopilotLaw.swift` is unchanged from `main` (`git diff main -- Sources/` empty), so everything recorded in this phase and in Phase 3 comes from the law before the fix
- [ ] T002 Create `Tests/SwiftSkySimulationTests/AutopilotRestPhaseTests.swift` with `@Suite("Autopilot from rest (020)") struct AutopilotRestPhaseTests` and a doc comment naming SKY-46 and spec 020. Use `import Foundation`, `import Testing` and `@testable import SwiftSkySimulation`, like `AutopilotTests.swift`
- [ ] T003 In the same file, add `static func stationKept() -> SimulationState`: a `SimulationState(tickCount: 0, ship: Ship())` ordered with `setOrder(to: Vector2(x: 1_000, y: 0))`, flown with `fly(_:maxTicks: 3_600)` (helper in `AutopilotTests.swift`) to arrival, then advanced 600 more ticks one at a time with `Simulation.advance(_:ticks: 1)` in a `while` loop (research R4)
- [ ] T004 In the same file, add `static func reorder(_ state: SimulationState, turnedBy offset: Double) -> SimulationState`. It returns a copy ordered to the point 1,000 units from the ship's position in direction `atan2(v.y, v.x) + offset`, where `v` is the ship's velocity. The two uses are `offset = .pi` (straight behind) and `offset = 2 * .pi / 3` (120°)
- [ ] T005 Add the test "Station keeping leaves a leftover velocity below the settle speed (FR-005 setup)". It asserts that the ship from `stationKept()` has phase `.arrived`, a speed greater than 0 and at most `Autopilot.settleSpeed`, and velocity `x`/`y` `bitPattern`s equal to recorded constants. Record the constants from a first run; research R1 gives the decimal values `(0.0009974385557949639, -3.859627003769714e-05)`

**Checkpoint**: `swift test --filter AutopilotRestPhase` passes with the law unchanged.

---

## Phase 2: User Story 2 — The flight itself does not change (Priority: P1)

**Goal**: Pin every tick's control input and ship state of both re-orders, recorded from the law before the
fix (spec FR-004, FR-007, SC-002).

**Independent Test**: The fingerprint tests pass against the unfixed law now. After Phase 3's fix they still
pass, with the constants unedited.

- [ ] T006 [US2] In `Tests/SwiftSkySimulationTests/AutopilotRestPhaseTests.swift`, add `static func fingerprint(_ start: SimulationState, maxTicks: Int) -> (fingerprint: UInt64, ticks: Int)`. Each tick, it takes the input from a copy (`var probe = state.autopilot; let input = probe.control(for: state.ship)`), advances with `Simulation.advance(_:ticks: 1)`, and folds `input.thrust.bitPattern`, `input.turn.bitPattern` and `bits(state.ship)` (from `StateBits.swift`) into FNV-1a 64 (offset `0xcbf29ce484222325`, prime `0x100000001b3`, `&*`). It stops on the first tick whose phase is `.arrived` and returns the hash and tick count. It loops with `while`, and the phase is never hashed (research R3)
- [ ] T007 [US2] Add the parameterised test "A re-order from station keeping flies bit-identical inputs and states (FR-007, SC-002)" over `offset` ∈ {`.pi`, `2 * .pi / 3`}. It asserts the fingerprint and tick count against constants recorded **now**, from the unfixed law. Add a comment saying they were recorded before the 020 fix and must never be edited to make the test pass (spec FR-004)
- [ ] T008 [US2] Run `swift test --filter AutopilotRestPhase`. All tests pass on the unfixed law. Commit Phase 1 and Phase 2 together, so the recorded constants exist in history before the fix

**Checkpoint**: The inputs and states are pinned before any source change.

---

## Phase 3: User Story 1 — A new order after arrival reads as a fresh start (Priority: P1) 🎯 MVP

**Goal**: A re-order from station keeping starts `aligning` (or `burning` when already facing the burn
direction), and its phases move forward only (spec FR-001–FR-003, FR-005, FR-005a, FR-006).

**Independent Test**: `swift test --filter AutopilotRestPhase`. The tests in T009–T011 fail before T012 and
pass after it, and T007 still passes, unedited.

### Tests (written first, failing on the unfixed law)

- [ ] T009 [US1] In `Tests/SwiftSkySimulationTests/AutopilotRestPhaseTests.swift`, add "A re-order at 120° from the leftover velocity starts aligning and only moves forward (FR-005, FR-006)". Fly `reorder(stationKept(), turnedBy: 2 * .pi / 3)` with `fly(_:maxTicks: 3_600)`. Expect `phases == [.aligning, .burning, .flipping, .braking, .arrived]`, and check forward-only with `AutopilotTests.rank`: ranks sorted and no duplicates, as `AutopilotTests.swift` does
- [ ] T010 [US1] Add "A re-order straight behind the leftover velocity starts burning (scenario 3, FR-006)". Fly `reorder(stationKept(), turnedBy: .pi)` and expect `phases == [.burning, .flipping, .braking, .arrived]` with the same forward-only check
- [ ] T011 [US1] Add "The rest boundary is the settle speed, inclusive (FR-005a)". Build `SimulationState(tickCount: 0, ship: Ship(position: .zero, velocity: Vector2(x: s, y: 0), heading: .pi, angularVelocity: 0))` ordered to the point 1,000 units away at 120° from +x. Call `state.autopilot.control(for: state.ship)` once and read `state.autopilot.phase`. Expect `.aligning` for `s = Autopilot.settleSpeed` and `.flipping` for `s = Autopilot.settleSpeed.nextUp`
- [ ] T012 [US1] Run `swift test --filter AutopilotRestPhase` and confirm that T009–T011's rest cases fail as research R1 records (`flipping, braking, …`, `braking, burning, …`, `.flipping` at exactly the settle speed) and that everything else passes. Note the output in the commit message of T014

### Implementation

- [ ] T013 [US1] In `Sources/SwiftSkySimulation/AutopilotLaw.swift` `evaluate`, apply research R2 and contracts/phase-rule.md:
  - before step 5's settled return, add `let atRest = speed <= Self.settleSpeed` and `let namedAgainstMotion = facingAgainstMotion && !atRest`, with a comment citing 020 and SKY-46;
  - use `namedAgainstMotion` in the settled return, the thrusting rule and the final coasting return of step 8;
  - make the turning rule's guard `guard !atRest, targetX * vx + targetY * vy < 0 else { … }`;
  - leave `facingAgainstMotion` in step 6 (`committedToBraking`) and every input calculation untouched;
  - update the step 8 comment to say that at rest the velocity has no direction.
- [ ] T014 [US1] Run `swift test` (the whole package). All 020 tests pass, T007's constants are unedited, and `AutopilotTests` and `PlannedPathTests` pass unchanged (`git diff main -- Tests/SwiftSkySimulationTests/AutopilotTests.swift Tests/SwiftSkySimulationTests/PlannedPathTests.swift` empty). If T007 fails, **stop and report**; do not edit the constants or the inputs (spec FR-004). Commit

**Checkpoint**: The bug is fixed and the inputs are proven unchanged.

---

## Phase 4: Polish & Cross-Cutting Concerns

- [ ] T015 [P] In `specs/006-ship-autopilot/research.md` R6, add a **Rest** paragraph after rule 4. It says that rules 2–4 treat a speed of at most `settleSpeed` (0.001 u/s) as rest, with no direction, so never against the motion. Why: station keeping leaves up to that much velocity and calls it settled, so the settle speed is the law's own "no motion". It is phase naming only, and the hold rule is unchanged, so inputs are bit-identical (020, SKY-46)
- [ ] T016 [P] In `specs/006-ship-autopilot/contracts/autopilot.md` step 8, replace the three bullets with the wording of `specs/020-autopilot-rest-phase/contracts/phase-rule.md` (the rest clause, and the note that step 6 still reads `ĥ·v < 0` without it)
- [ ] T017 [P] In `CLAUDE.md`, add one sentence to the `AutopilotLaw.swift` bullet. When naming the phase, a speed of at most `settleSpeed` is rest (020, SKY-46), and the hold rule and inputs do not use that rule. Add `specs/020-autopilot-rest-phase` to the "Built so far" list
- [ ] T018 Run `./Scripts/verify.sh` (in the background; it takes minutes) and confirm it passes (SC-004). Then walk `specs/020-autopilot-rest-phase/quickstart.md` checks 1–6 and record the results under each check
- [ ] T019 Commit Phase 4 on the worktree branch (no push)

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → Phase 3 → Phase 4, strictly in that order. Phase 2's constants must be recorded and
  committed before T013 changes the law, and Phase 3's tests must fail before T013.
- US2 does not depend on US1. US1's fix (T013) depends on US2's constants being committed (T008).
- T015, T016 and T017 are separate files and can run in parallel after T014.

## Parallel Example

```text
After T014:
  T015 specs/006-ship-autopilot/research.md
  T016 specs/006-ship-autopilot/contracts/autopilot.md
  T017 CLAUDE.md
```

## Implementation Strategy

1. Phases 1–2: pin the setup and the pre-fix flight (commit).
2. Phase 3: failing reproduction, then the four-line fix (commit). This is the MVP: SKY-46 is fixed.
3. Phase 4: docs and `verify.sh` (commit).
