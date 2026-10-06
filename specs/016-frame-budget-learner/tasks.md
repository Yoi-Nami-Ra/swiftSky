# Tasks: Frame Budget That Does Not Lock Onto Stray Gaps

**Input**: Design documents from `/specs/016-frame-budget-learner/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/display-interval-learner.md, quickstart.md

**Tests**: requested by the spec (FR-008, US3): the learner gets a headless Swift Testing suite covering
contract C3. The wiring in the frame loop and the view is checked by the quickstart's hands-on checks.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1–US3 from spec.md

## Phase 1: Setup

- [ ] T001 Confirm the baseline: run `./Scripts/verify.sh` on `016-frame-budget-learner` before any code change and note the result and the test count

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: the pure learner every story is built on.

- [ ] T002 Create `struct DisplayIntervalLearner` in Sources/SwiftSkyPlatform/DisplayIntervalLearner.swift per contract C1 and data-model.md (fields `interval`, `isLearned`, `candidate`, `floor`; constants `tolerance = 0.05`, `fastestPlausible = 1/250`, `slowestPlausible = 1/20`, `defaultInterval = 1/60`; `observe(gap:) -> Double?`, `forget() -> Double`, `setMaximumFramesPerSecond(_:) -> Double?`), compiled in every build (no `#if`), no imports beyond Swift, no allocation, with a doc comment stating the consecutive-confirmation and floor rules and withdrawing the "whole number of intervals / never has a partner" premise (FR-009, research R6)

**Checkpoint**: the package builds; nothing uses the learner yet.

## Phase 3: User Story 1 — The budget stays at the display's real interval for a whole run (Priority: P1) 🎯 MVP

**Goal**: consecutive confirmation in the running app, so stray and jitter gaps no longer lower the budget.

**Independent Test**: contract C3 series 1–5 headlessly; quickstart check 2 by hand.

- [ ] T003 [P] [US1] Add Tests/SwiftSkyPlatformTests/DisplayIntervalLearnerTests.swift with C3 series 1–5 (steady 120 Hz → 1/120; 60 Hz with one doubled gap stays 1/60; two 14.84 ms gaps separated by normal ones not adopted; late/catch-up jitter `(h60, h60, 22.0, 11.3) × 25` does not lower; single 5.0 ms startup outlier ignored), plus: implausible gaps (3 ms, 60 ms) neither confirm nor clear; `observe` returns `nil` when the adopted value equals `interval`; a disagreeing shorter gap replaces the candidate
- [ ] T004 [US1] Replace `displayInterval`, `candidateInterval`, `learnDisplayInterval(from:)`, `forgetDisplayInterval()` and their constants in Sources/SwiftSkyPlatform/FrameLoop.swift with a stored `DisplayIntervalLearner`: step 3 calls `if let budget = learner.observe(gap: elapsed) { instrumentation.updateBudget(seconds: budget) }`; `.backingScaleChanged` calls `instrumentation.updateBudget(seconds: learner.forget())`; move the SC-003 rationale comment to the learner

**Checkpoint**: `verify.sh` passes; series 1–5 pass.

## Phase 4: User Story 2 — Moving to another display and resizing do not leave a false budget (Priority: P2)

**Goal**: the floor from the display's maximum rate reaches the learner.

**Independent Test**: contract C3 series 6–7 and the floor tests headlessly; quickstart checks 3–5 by hand.

- [ ] T005 [P] [US2] Add to Tests/SwiftSkyPlatformTests/DisplayIntervalLearnerTests.swift: C3 series 6 (learned 1/120, then `setMaximumFramesPerSecond(60)` and `forget()`, then 3 × 120 Hz and 20 × 60 Hz gaps → 1/60) and series 7 (learned 1/120, a burst of 10 × 4.17 ms gaps then 120 Hz gaps → stays 1/120); `setMaximumFramesPerSecond(60)` with a learned 1/120 forgets and returns 1/60 on its own; `setMaximumFramesPerSecond(120)` with a learned 1/60 returns `nil`; an 8.3330 ms pair with floor 120 adopts exactly 1/120; unknown rate (0) leaves only the 250 Hz bound (two 4.17 ms gaps adopted); two adjacent 14.84 ms gaps with floor 120 are adopted (documented residual risk)
- [ ] T006 [P] [US2] Add `case displayRateChanged(maximumFramesPerSecond: Int)` with a doc comment (contract C2, research R3) to Sources/SwiftSkyPlatform/SurfaceEvent.swift
- [ ] T007 [US2] Apply `.displayRateChanged(let n)` in `applyPendingEvents` in Sources/SwiftSkyPlatform/FrameLoop.swift: `if let budget = learner.setMaximumFramesPerSecond(n) { instrumentation.updateBudget(seconds: budget) }`
- [ ] T008 [US2] In Sources/SwiftSkyPlatform/MetalSurfaceView.swift, read the screen's maximum rate (`window?.screen.maximumFramesPerSecond` on iOS, `window?.screen?.maximumFramesPerSecond ?? 0` on macOS) in `surfaceGeometryChanged`, and post `.displayRateChanged` before the geometry event when it differs from the last value posted (stored in a private property)

**Checkpoint**: `verify.sh` passes (both apps build); series 6–7 pass.

## Phase 5: User Story 3 — Checked without a device, costs nothing per frame (Priority: P3)

**Goal**: the suite runs in the single command, and the frame loop still allocates nothing.

**Independent Test**: `verify.sh`; quickstart check 6.

- [ ] T009 [US3] Run `./Scripts/verify.sh` and confirm the new suite runs headlessly (no Metal device), and everything passes; then build the macOS app once in the Release configuration (`xcodebuild -project swiftSky.xcodeproj -scheme 'swiftSky (macOS)' -configuration Release -destination platform=macOS CODE_SIGNING_ALLOWED=NO build`) to confirm FR-010 (the learner compiles in every build and adds no output: `Instrumentation.updateBudget` is the Release no-op); record the result in specs/016-frame-budget-learner/quickstart.md
- [ ] T010 [US3] Quickstart check 6 (011 check 25 on the optimised instrumented build, 60 s): left for the user; mark it so in specs/016-frame-budget-learner/quickstart.md

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T011 [P] Add a `specs/016-frame-budget-learner` entry and a key-locations line for `DisplayIntervalLearner.swift` and `.displayRateChanged` to CLAUDE.md
- [ ] T012 Grep Sources/ for comments that still state the old premise ("whole number of", "never does", "spurious one never", "a genuine interval always has a partner") and update them (FR-009)
- [ ] T013 Quickstart checks 2–5 (10-minute loaded iOS simulator run; macOS live resize; idle 120 Hz; move to a 60 Hz display): left for the user; record them as open in specs/016-frame-budget-learner/quickstart.md

## Dependencies & Execution Order

- T001 → T002 → US1 (T003 ∥ T004) → US2 (T005 ∥ T006 → T007 → T008) → US3 (T009, T010) → Polish (T011 ∥ T012, T013).
- US2 depends on US1's wiring in `FrameLoop.swift` (same file). US3 verifies both.

## Parallel Example

```text
US1: T003 (tests file) ∥ T004 (FrameLoop.swift)
US2: T005 (tests file) ∥ T006 (SurfaceEvent.swift)
```

## Implementation Strategy

MVP is US1: consecutive confirmation alone removes the simulator lock observed on 2026-10-06. US2 adds
the floor for the display-move and live-resize cases. Commit after each phase.
