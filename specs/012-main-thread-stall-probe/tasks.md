# Tasks: Measure Main-Thread Stalls and Verify Continuous Resize Under Thread Sanitizer

**Input**: Design documents from `/specs/012-main-thread-stall-probe/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/main-thread-stall-probe.md,
quickstart.md

**Tests**: Required by FR-010 and Principle II for the tracker and the packed figures (plain types). The
run-loop observers, the markers and the drag are verified by quickstart checks 2–8.

**Organization**: by user story. US1 builds and proves the probe; US2 runs the two drags and records
check 29.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: US1 or US2

## Phase 1: Setup

- [X] T001 Record the "before" baseline for SC-005 from `main` (`2f88a12`): build the optimised instrumented
  macOS app (quickstart "The drag procedure" step 1, second command) from a `git worktree add` of `main`
  into the session scratchpad, run it idle 30 s, and save its summaries to the scratchpad for T019

## Phase 2: Foundational

No shared prerequisite beyond Phase 1: the plain types in US1 are the foundation and are tested there.

## Phase 3: User Story 1 — Read the main thread's worst stall from the log (P1) 🎯 MVP

**Goal**: summaries end with `mainworst=…ms mainover=…`; drags are bracketed by markers; a deliberate
stall shows up.

**Independent Test**: `Scripts/verify.sh` passes with the new tests; quickstart checks 2–4.

### Tests for User Story 1

- [X] T002 [P] [US1] Write `Tests/SwiftSkyPlatformTests/MainThreadStallTests.swift` (Swift Testing): for
  `BusyStretchTracker` — after/before-waiting returns the difference; before-waiting with no open stretch
  returns `nil`; a nested sequence (after, before, after, before) yields two stretches; a clock that goes
  backwards yields 0. For `MainThreadStallFigures` — packing round-trips; `recording` keeps the maximum in
  microseconds; a stretch equal to the interval is not over, one nanosecond longer is; counts accumulate;
  an interval change between two stretches judges each against its own interval; worst and count saturate
  at 2⁴⁰−1 µs and 2²⁴−1; `.zero` is all zeros (data-model.md). For `MainThreadStallProbe`, driven through `record(stretchNanoseconds:)`
  without `install()`: `take()` returns what was recorded and leaves zero; a stretch recorded after a
  `take()` appears only in the next one (FR-005); `restart(intervalSeconds:)` discards the figures and
  judges later stretches against the new interval (FR-006). These fail until T003 and T004

### Implementation for User Story 1

- [X] T003 [US1] Create `Sources/SwiftSkyPlatform/MainThreadStallFigures.swift` with `BusyStretchTracker`
  and `MainThreadStallFigures` exactly as in data-model.md, compiled in every build like
  `FrameAllocationCounts.swift`, with doc comments citing 012 FR-001–FR-005 and research R3, R4; make T002
  pass
- [X] T004 [US1] Create `Sources/SwiftSkyPlatform/MainThreadStallProbe.swift`, entirely under
  `#if SWIFTSKY_INSTRUMENTATION`: `final class MainThreadStallProbe: Sendable` holding
  `figures: Atomic<UInt64>` and `intervalNanoseconds: Atomic<UInt64>` (Synchronization), a main-thread-only
  `BusyStretchTracker` (`nonisolated(unsafe)`, documented as main-only), and two `CFRunLoopObserver`s on
  `CFRunLoopGetMain()` in `.commonModes`: `kCFRunLoopAfterWaiting` at order `Int.min` opens a stretch,
  `kCFRunLoopBeforeWaiting` at order `Int.max` closes it and folds it into `figures` with a
  compare-and-exchange loop using the current interval (research R1, R2, R4). Clock:
  `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)`. `install()` / `uninstall()` (main thread, idempotent), `take()`
  (`exchange(0)`), `restart(intervalSeconds:)` (store interval, then `take()`) and the internal
  `record(stretchNanoseconds:)` the observer calls, per data-model.md; make T002's probe tests pass. No
  allocation after `install()`
- [X] T005 [US1] Change `Sources/SwiftSkyPlatform/Instrumentation.swift`: in the instrumented branch, hold a
  `let stallProbe: MainThreadStallProbe` (passed to `init`), call `stallProbe.restart(intervalSeconds:)`
  in `init` and in `updateBudget(seconds:)` (research R6), and in `summary()` take the figures once and
  append `mainworst=\(ms)ms mainover=\(n)` to the end of both summary forms (contract C1, research R9),
  keeping every existing field unchanged; update the type's doc comment. Release branch: add the new `init`
  parameter shape as a no-op so `FrameLoop` compiles in both
- [X] T006 [US1] Change `Sources/SwiftSkyPlatform/FrameLoop.swift`: create the probe in `init` (instrumented
  only) and pass it to `Instrumentation`; call `install()` in `start()` (main thread) and `uninstall()` in
  `stopAndDrain()`; document both in the type's isolation notes (the probe is the second cross-thread
  channel, lock-free). No per-frame change (contract C3). Depends on T004, T005
- [X] T007 [P] [US1] Change `Sources/SwiftSkyPlatform/MetalSurfaceView.swift` (macOS block): override
  `viewWillStartLiveResize` and `viewDidEndLiveResize`, calling `super` and, under
  `SWIFTSKY_INSTRUMENTATION`, logging `live resize began` / `live resize ended` at `notice` with
  `Logger(subsystem: "com.swiftsky.app", category: "frame")` (FR-013, research R7, contract C4)
- [X] T008 [P] [US1] Change `Sources/SwiftSkyPlatform/GameSurfaceView.swift`: add `--debug-main-stall`
  (instrumented builds only) beside the existing `--debug-*` arguments; when present, schedule one
  main-queue block 5 s after setup that spins on the clock for 50 ms (research R8, contract C5). Add a
  parsing test to `Tests/SwiftSkyPlatformTests/DebugShipOptionsTests.swift` if the option lives in a
  parsed struct
- [X] T009 [US1] Run `Scripts/verify.sh`; fix any warning or failure; run the new suites 10 times in a row
  (`swift test --filter MainThreadStall` ×10) and record quickstart check 1 in
  `specs/012-main-thread-stall-probe/quickstart.md` Results (SC-001, SC-007)
- [X] T010 [US1] Quickstart check 2: Debug macOS build, idle 10 s; ask the user to drag a corner for 5 s;
  confirm the new fields, `mainover=0` when idle, the two markers, and a drag that reads as short stretches
  (research R2's fail-loud case absent). Record in quickstart Results (SC-002, FR-013)
- [X] T011 [US1] Quickstart check 3: Debug build with `--debug-main-stall`; confirm `mainworst` ≥ 50 ms and
  `mainover` ≥ 1 in the summary after 5 s, `mainover=0` elsewhere after the first. Record (SC-002)
- [X] T012 [US1] Quickstart check 4: Release build of `swiftSky (macOS)`; `nm` and `strings -a` find none of
  `mainworst=`, `mainover=`, `live resize`, `--debug-main-stall`, `MainThreadStallProbe`. Record (FR-008)

**Checkpoint**: the probe is in place and proven; US2 can run.

## Phase 4: User Story 2 — Verify a continuous resize: no races, no main-thread stall (P2)

**Goal**: 001 check 29 decided.

**Independent Test**: quickstart checks 5 and 6.

- [X] T013 [US2] Build the Thread Sanitizer app (quickstart step 1, first command) into the scratchpad
- [X] T014 [US2] Quickstart check 5: launch it with standard error saved, wait for the second summary, ask
  the user to drag a corner continuously for at least 10 s, then quit; count `WARNING: ThreadSanitizer`
  in standard error and confirm summaries throughout the drag (contract C6). A race: find it from the
  report, fix it, and repeat. Record with the stall figures for information (SC-003)
- [X] T015 [US2] Build the optimised instrumented app from this branch (quickstart step 1, second command)
- [X] T016 [US2] Quickstart check 6: same procedure; every covering summary must have `mainover=0` and
  `mainworst` ≤ `budget=` (contract C6). On a stall, repeat with `sample <pid> 5` running, find the
  source, fix it if it is the app's, and repeat; a cause wholly in system code is recorded as a FAIL with
  the sample and a new ticket (spec Clarifications). Record (SC-004)
- [X] T017 [US2] Record check 29 in `specs/001-metal-app-shell/quickstart.md`: replace "**Check 29 —
  PARTIAL (2026-07-28)**" with the result (date, Mac and display, both builds, drag length and how it was
  made, the sanitizer verdict, each covering summary's `mainworst`/`mainover`/`budget`), pointing to this
  feature's quickstart; update or remove the check-29 row of the open-checks table, and the note under the
  status roll-up (FR-011)

**Checkpoint**: check 29 recorded.

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T018 [P] Quickstart check 8: the optimised instrumented build, idle 60 s by 011's method: `allocs=0
  allocframes=0` in every summary after the first. Record (SC-006)
- [X] T019 Quickstart check 7: run this branch's optimised instrumented build idle 30 s on the same Mac and
  compare its mean frame time and `dropped=` with T001's baseline (within 10% or 0.1 ms). Record (SC-005)
- [X] T020 [P] Update `CLAUDE.md`: spec 012 in the "Built so far" list; the probe, its fields, the markers,
  `--debug-main-stall` and the drag procedure under Key locations
- [X] T021 [P] Update `.tickets/5.yaml`: description to the result; status to `in-review`
- [X] T022 Run `Scripts/verify.sh` a final time; mark the spec `Status: Implemented`

## Dependencies & Execution Order

- **Phase 1** (T001): independent; needed only by T019.
- **US1**: T002 → T003 → T004 → T005 → T006; T007 and T008 parallel with T004–T006; T009 after T006–T008;
  T010–T012 after T009.
- **US2**: after US1 (needs the probe). T013 → T014; T015 → T016; T017 after T014 and T016.
- **Polish**: T018, T019 after T015; T020, T021 after T017; T022 last.

## Parallel Example: User Story 1

```text
T007 (MetalSurfaceView markers) and T008 (--debug-main-stall) alongside T004–T006.
```

## Implementation Strategy

- **MVP**: US1 (T002–T012). The probe on its own is useful for every later responsiveness check.
- **Then** US2 (T013–T017): the two drags, which need the user at the Mac.
- **Commit** after each phase.
