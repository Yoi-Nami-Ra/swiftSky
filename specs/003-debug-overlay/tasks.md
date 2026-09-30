---

description: "Task list for 003-debug-overlay"
---

# Tasks: Live Debug Overlay

**Input**: Design documents from `/specs/003-debug-overlay/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/debug-overlay.md, quickstart.md

**Tests**: Required. FR-016 and User Story 5 call for headless tests, and constitution Principle II
requires tests for the window, the refresh schedule and the number formatting. Drawing code is
exempt, and is validated by the quickstart checks instead.

**Organization**: tasks are grouped by user story, so that each story can be implemented and
validated on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US5)
- Paths are relative to the repository root. `R<n>` refers to research.md and `check <n>` to
  quickstart.md.

## Path Conventions

- Layer sources are under `Sources/SwiftSky{Simulation,Rendering,Platform}/`, tests under `Tests/`,
  and scripts under `Scripts/`. See plan.md for the project structure.
- "Instrumentation only" means the code sits inside `#if SWIFTSKY_INSTRUMENTATION … #endif`
  (FR-009, R8).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the platform layer's first test target.

- [X] T001 Add `.testTarget(name: "SwiftSkyPlatformTests", dependencies: ["SwiftSkyPlatform"], swiftSettings: layerSettings)` to `Package.swift`, with a comment in the style of the two existing test targets. It depends on SwiftSkyPlatform **only**, and it tests pure measurement structs, never a view, layer or `FrameLoop` (R9)
- [X] T002 [P] Create `Tests/SwiftSkyPlatformTests/FrameTimeWindowTests.swift`, containing `import Testing`, `@testable import SwiftSkyPlatform` and a single placeholder `@Test`, which T019 replaces. SwiftPM needs one source per target

**Checkpoint**: `swift test --build-system swiftbuild` runs the new, empty target.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the pure pieces every story uses: the decimal writer, the window, the schedule, the
snapshot value and the overlay's composition (data-model.md).

**⚠️ CRITICAL**: no user story work can begin until this phase is complete.

- [X] T003 [P] Add `writeHundredths(_ value: Double, width: Int = 0, limit: Int = .max)` and `writePadded(_ text: StaticString, width: Int, limit: Int = .max)` to `TextBuffer` in `Sources/SwiftSkyRendering/Text/TextBuffer.swift`, in every build (R5, FR-007, contracts/debug-overlay.md):
  - **Clamp**: NaN and negative values become `0`, and values at or above `Double(UInt64.max) / 100` are clamped to it.
  - **Round**: `hundredths = UInt64((value * 100).rounded(.toNearestOrAwayFromZero))`.
  - **Pad**: count the digits of `hundredths / 100` with a division loop on a local, so the written width is `digits + 3`, then place `width − written` spaces first.
  - **Write**: the integer part with the existing `write(UInt64)`, then `.`, then `write(hundredths % 100, minimumDigits: 2)`.
  - **`writePadded`**: counts the literal's UTF-8 bytes, pads with spaces, then writes it.
  - **Rules**: every character respects `limit`, nothing allocates, and nothing is cut short.
- [X] T004 [P] Implement `FrameTimeBucket` and `FrameTimeWindow` in `Sources/SwiftSkyPlatform/FrameTimeWindow.swift`, instrumentation only (R2, data-model.md):
  - **Storage**: `open` bucket, a `closed: InlineArray<4, FrameTimeBucket>` ring, `next`, and `closedCount` capped at 4.
  - **Operations**: `record(frameSeconds:)`, `closeBucket()` and `restart()`.
  - **`mean` and `worst`**: `nil` until four buckets have closed, and `mean` is also `nil` when the closed buckets hold zero frames.
  - **Constants**: `static let bucketCount = 4` and `static let windowSeconds = 1.0`.
  - **Doc comment**: explain why a long gap between frames is *not* a restart trigger (R2).
- [X] T005 [P] Implement `OverlayRefreshSchedule` in `Sources/SwiftSkyPlatform/OverlayRefreshSchedule.swift`, instrumentation only (R3, data-model.md):
  - **Constants**: `static let refreshRate = 4.0`, the one named value FR-006 requires, and `static let interval = 1.0 / refreshRate`.
  - **`nextDue: Double?`**.
  - **`isDue(at:)`**: due at once when `nextDue` is `nil`. Otherwise it advances on the grid, and re-anchors at `t + interval` when a frame was late by more than a whole interval, so it never bursts.
  - **`restart()`**.
- [X] T006 [P] Implement `DebugOverlayStatistics` (`Sendable, Equatable`, the six fields of data-model.md, with a public memberwise `init`) and `DebugOverlay` (`public init()`, `public var statistics`, `public func write(into:surface:)`) in `Sources/SwiftSkyRendering/Debug/DebugOverlay.swift`, instrumentation only. Depends on T003. (R6, contracts/debug-overlay.md "Overlay text"):
  - **`write`**: returns without writing when `statistics` is `nil`. Otherwise it calls `begin` at `safeAreaInsets.left + 8`, `safeAreaInsets.top + 8`, then writes the six lines. It never calls `clear()`, because the renderer clears first, as it does for `DebugTextPattern` (contracts/debug-overlay.md).
  - **Labels**: `StaticString` constants, each exactly 8 columns.
  - **Frame times**: seconds × 1000 through `writeHundredths(width: 6)` + `" ms"`, or `writePadded("--", width: 6)` + `" ms"` when `nil`.
  - **Counts**: through `write(UInt64)`.
  - **Rules**: every write is capped at `remainingCapacity`, and the anchor inset is shared with `DebugTextPattern.insetPoints` rather than duplicated.
- [X] T007 Extend `Instrumentation` in `Sources/SwiftSkyPlatform/Instrumentation.swift`, inside the existing `#if SWIFTSKY_INSTRUMENTATION` branch only. Depends on T004, T005, T006. (data-model.md, R1, R11, FR-013):
  - **New state**: `private var window = FrameTimeWindow()` and `private var schedule = OverlayRefreshSchedule()`.
  - **`recordPresented`**: also calls `window.record(frameSeconds:)`.
  - **`updateBudget`**: also calls `restartOverlayWindow()`, so both the window and the schedule restart.
  - **`overlayStatistics(at:) -> DebugOverlayStatistics?`**: on `schedule.isDue(at:)`, calls `window.closeBucket()` (except on the anchoring refresh right after a restart, which starts the first bucket) and returns the snapshot of `window.mean`, `window.worst`, `budgetSeconds`, `droppedFrames`, `skippedFrames` and `lastTickCount`. Otherwise it returns `nil`.
  - **`restartOverlayWindow()`**: restarts both the window and the schedule.
  - **Unchanged**: `summary()`, the existing counters, and the Release stub.

**Checkpoint**: `./Scripts/verify.sh` passes. Nothing is drawn yet.

---

## Phase 3: User Story 1 - Developer reads live frame stats on macOS (Priority: P1) 🎯 MVP

**Goal**: a macOS Debug build launched with no argument shows the six live lines 8 pt in from the
safe-area top-left, refreshing four times a second and agreeing with the log.

**Independent Test**: quickstart checks 6, 7, 8, 10, 11 and 17 on macOS.

- [X] T008 [US1] Wire the overlay into `Renderer` in `Sources/SwiftSkyRendering/Renderer.swift`, instrumentation only (contracts/debug-overlay.md):
  - **New members**: `public var debugOverlay: DebugOverlay?`, documented as set once before the loop starts, like `debugTextPattern`, and `public func updateDebugOverlay(_ statistics: DebugOverlayStatistics)`, which sets `debugOverlay?.statistics`.
  - **`prepareText`**: calls `textBuffer.clear()` whenever either is set, then writes `debugTextPattern` if it is set, `else if let debugOverlay` writes `debugOverlay.write(into: textBuffer, surface:)`.
  - **Unchanged**: the atlas, overflow and draw paths.
- [X] T009 [US1] Update `FrameLoop` in `Sources/SwiftSkyPlatform/FrameLoop.swift`. Depends on T007, T008.
  - **Step 3a**: after `learnDisplayInterval(from:)` and before the simulation advance, add `if let statistics = instrumentation.overlayStatistics(at: now) { renderer.updateDebugOverlay(statistics) }`, wrapped in `#if SWIFTSKY_INSTRUMENTATION`.
  - **Visibility**: in `applyPendingEvents`, on `.visibilityChanged(isVisible: true)`, also call `instrumentation.restartOverlayWindow()`, under the same condition.
  - **Documentation**: update the delegate method's doc comment to list the new step (R4, FR-008).
- [X] T010 [US1] Extend `DebugTextMode` in `Sources/SwiftSkyPlatform/GameSurfaceView.swift` (R7, FR-001, FR-011, FR-012):
  - **Cases and argument**: add the `.overlay` case and `static let noOverlayArgument = "--no-debug-overlay"`.
  - **`init(arguments:)`**: returns `.fill` > `.testString` > `.none` (when `--no-debug-overlay` is given) > `.overlay`.
  - **Wiring**: add `var overlay: DebugOverlay?`, which is `DebugOverlay()` only for `.overlay`, and set `renderer.debugOverlay` beside `renderer.debugTextPattern` in `buildSetup()`.
  - **Documentation**: update the type's doc comment.
- [ ] T011 [US1] **Open (2026-09-30)**: window capture is refused in this session, so the checks that need eyes on the overlay wait for a person. The log side of check 6 is recorded. Build and run the macOS Debug app. Perform quickstart checks 6, 7, 8, 10, 11 and 17 on macOS, and record the date, device, result and numbers under "Evidence to record" in `specs/003-debug-overlay/quickstart.md`. Mark any check that cannot be run here (for example check 7 without a second display) as open, with the reason.

**Checkpoint**: US1 is fully working. The overlay is the MVP.

---

## Phase 4: User Story 2 - Developer reads live frame stats on iOS (Priority: P2)

**Goal**: the same overlay on iOS, inside the safe area in every orientation.

**Independent Test**: quickstart check 9, checks 11 and 12 on iOS, and check 18.

- [ ] T012 [US2] **Open (2026-09-30)**: the iOS Simulator hung on `simctl install`. The iOS app builds. Build the iOS Debug app for the simulator (`xcodebuild … -scheme 'swiftSky (iOS)'`), launch it, and perform quickstart check 9 (both landscape orientations; Slide Over if an iPad simulator is available) and check 11 (background for 5 s, then return). Record the evidence in `specs/003-debug-overlay/quickstart.md`. No iOS-specific code is expected, because the safe-area insets come from 002. If a defect appears, fix it in the platform layer and record it.
- [ ] T013 [P] [US2] **Partly done (2026-09-30)**: check 18 passed except for the frame-log continuation. Check 12 needs Accessibility Inspector. Perform quickstart check 12 (Accessibility Inspector on macOS, and the accessibility hierarchy on iOS: only the 001 surface label is exposed, FR-010) and check 18 (002's forced atlas failure with no argument: the app runs without text and keeps logging). Record both in `specs/003-debug-overlay/quickstart.md`

**Checkpoint**: US1 and US2 both work.

---

## Phase 5: User Story 3 - The overlay does not disturb what it measures (Priority: P3)

**Goal**: evidence that the overlay allocates nothing per frame and keeps within the frame budget.

**Independent Test**: quickstart checks 13 and 14.

- [ ] T014 [US3] **Open (2026-09-30)**: `xctrace` never finished, as in 002, so this needs Instruments by hand. Perform quickstart check 13: an Allocations run of 60 s with the overlay showing, filtered to the frame-loop thread's draw path, using the method of 002 check 15. Record the result in `specs/003-debug-overlay/quickstart.md`. If an allocation of ours shows up, fix it at its source and re-run (FR-014).
- [X] T015 [US3] Perform quickstart check 14 on one device: 60 s each with `--no-debug-overlay` and with no argument, reading the instrumentation log's `mean=`, `worst=` and `dropped=`. Record both runs as the before/after pair in `specs/003-debug-overlay/quickstart.md` (SC-004, Principle III)

**Checkpoint**: Principle III evidence is recorded.

---

## Phase 6: User Story 4 - Release builds contain no overlay (Priority: P4)

**Goal**: proof that Release draws nothing new and contains none of the overlay.

**Independent Test**: quickstart checks 15 and 16.

- [ ] T016 [US4] **Partly done (2026-09-30)**: Release was built and inspected (check 16), but not launched and looked at. Build macOS Release (`xcodebuild … -configuration Release`), launch it with no argument, then with `--no-debug-overlay` and with `--debug-text`, and confirm a uniformly black surface each time (quickstart check 15). Record the result in `specs/003-debug-overlay/quickstart.md`.
- [X] T017 [US4] Perform quickstart check 16 on the same Release binary: `nm` after `strip -rSTx` for `DebugOverlay|FrameTimeWindow|OverlayRefreshSchedule`, and `strings` for `no-debug-overlay`, `dropped ` and `skipped `. Record the counts in a table in the style of 001 check 27, in `specs/003-debug-overlay/quickstart.md` (SC-005, FR-009).

**Checkpoint**: the Release gate is proven.

---

## Phase 7: User Story 5 - Developer verifies overlay formatting without a GPU (Priority: P5)

**Goal**: headless tests for every piece of overlay logic. This phase can start as soon as Phase 2 is
done, in parallel with US1 to US4.

**Independent Test**: quickstart checks 1 to 5.

- [X] T018 [P] [US5] Write `Tests/SwiftSkyRenderingTests/DecimalWritingTests.swift`. Cover every row of the contract's `writeHundredths` table; `width: 0` writing no padding; a value wider than `width` written in full; `limit` respected mid-number; clamping of a huge value; and `writePadded("--", width: 6)` producing four spaces and `--` (FR-007, check 3). Reuse `newTextBuffer()` and read the characters back from `instances` as `DebugTextPatternTests` does.
- [X] T019 [P] [US5] Replace the placeholder in `Tests/SwiftSkyPlatformTests/FrameTimeWindowTests.swift` with tests (FR-004, FR-008, check 4) covering:
  - `mean` and `worst` are `nil` until four buckets have closed;
  - only the last four closed buckets count once a fifth closes;
  - a 0.3 s frame stays `worst` for exactly four closes (one second), however far apart the frames are, and drops out on the fifth;
  - `restart()` returns to `nil`;
  - the closed buckets holding zero frames gives a `nil` mean;
  - `bucketCount × OverlayRefreshSchedule.interval == windowSeconds`.
- [X] T020 [P] [US5] Write `Tests/SwiftSkyPlatformTests/OverlayRefreshTests.swift` (FR-006, FR-008, FR-013, SC-002, check 4) covering:
  - **Rate**: over 10 s of 60 Hz and 120 Hz timestamps, `isDue` fires 40 ± 1 times.
  - **Timing**: the first frame is due, and after a 2 s gap exactly one refresh fires, then the grid resumes.
  - **Restart**: `restart()` makes the next frame due.
  - **Snapshot**: an `Instrumentation` fed by `recordPresented`, `recordSkipped` and `updateBudget` returns snapshots whose budget, dropped, skipped and tick fields equal its own counters, and whose mean and worst are `nil` right after `updateBudget`.
- [X] T021 [P] [US5] Write `Tests/SwiftSkyRenderingTests/DebugOverlayTests.swift` (FR-004, FR-005, check 5) covering:
  - nothing is written while `statistics` is `nil`;
  - the six lines appear in order, with the exact labels and the example text of contracts/debug-overlay.md;
  - `--` appears for `nil` mean and worst;
  - every line is ≤ 33 characters at the normal-range maxima (999.99 ms, 9,999,999);
  - `UInt64.max` counts are written in full;
  - the first glyph lands at the safe-area inset + 8 pt;
  - `didOverflow` stays false.

  Reuse the line-splitting helper pattern from `DebugTextPatternTests.swift`.
- [X] T022 [US5] Run `swift test --build-system swiftbuild` 10 times in a row and record the 10 identical passes under check 2 in `specs/003-debug-overlay/quickstart.md`. Depends on T018 to T021. (SC-007)

**Checkpoint**: every story is independently verified.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T023 [P] Update `CLAUDE.md`: list `specs/003-debug-overlay` under "Built so far"; add `Tests/SwiftSkyPlatformTests/` to the test locations; and note under "Debug launch arguments" that the overlay is on by default in Debug/Profiling and that `--no-debug-overlay` hides it
- [X] T024 [P] Add a note at the top of the validation matrix in `specs/002-metal-text-rendering/quickstart.md`: since 003, a Debug build shows the overlay by default, so check 12's black-surface run takes `--no-debug-overlay`. Add the same note beside the visible-output checks in `specs/001-metal-app-shell/quickstart.md` (SC-006)
- [X] T025 Run `./Scripts/verify.sh` and confirm it exits 0 with no `warning:` lines, then record the result under check 1 in `specs/003-debug-overlay/quickstart.md`

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup. T003 to T006 are parallel. T006 needs T003's writers, which are small, so write T003 first or together. T007 waits for T004 to T006.
- **US1 (Phase 3)**: depends on Phase 2. T008 → T009 (T009 calls `updateDebugOverlay`). T010 is independent of T009. T011 comes last.
- **US2 (Phase 4)**: depends on US1's code (T008 to T010). It adds validation only.
- **US3 (Phase 5)** and **US4 (Phase 6)**: depend on US1's code. US3 and US4 are independent of each other.
- **US5 (Phase 7)**: depends on Phase 2 only, so it can run alongside US1.
- **Polish (Phase 8)**: after everything.

### Parallel opportunities

- T002 alongside T001's edit review.
- T003, T004, T005 and T006 (four different files).
- T018, T019, T020 and T021 (four different test files), as soon as Phase 2 is done, even while US1 is in progress.
- T013 alongside T012. T023 alongside T024.

### Parallel example: Phase 2

```text
Task: "writeHundredths + writePadded in Sources/SwiftSkyRendering/Text/TextBuffer.swift"
Task: "FrameTimeWindow in Sources/SwiftSkyPlatform/FrameTimeWindow.swift"
Task: "OverlayRefreshSchedule in Sources/SwiftSkyPlatform/OverlayRefreshSchedule.swift"
```

### Parallel example: US5

```text
Task: "DecimalWritingTests.swift"   Task: "FrameTimeWindowTests.swift"
Task: "OverlayRefreshTests.swift"   Task: "DebugOverlayTests.swift"
```

## Implementation Strategy

### MVP first (US1)

1. Phases 1 and 2, then Phase 3.
2. **Stop and validate**: launch on macOS and watch the overlay agree with the log (checks 6 and 8).
3. The overlay is already useful day to day at this point.

### Incremental delivery

1. US1 is the macOS overlay, the MVP.
2. US5's tests can land at the same time, since they only need Phase 2.
3. US2 adds the iOS evidence, US3 the performance evidence, and US4 the Release gate.
4. Polish comes last: docs and the cross-spec notes.

### Follow-ups, not in this task list

- The ship lines (SKY-24) and the active-order lines (SKY-25) extend `DebugOverlayStatistics` and
  `DebugOverlay` once their data exists.
