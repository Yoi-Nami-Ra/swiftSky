# Tasks: Replace the Profiling Build with an Instrumented Build Script

**Input**: Design documents from `specs/019-instrumented-build-script/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/build-instrumented.md,
quickstart.md

**Tests**: No unit tests: there is no Swift logic. The feature's automated checks are the two new
`verify.sh` stages (US2); the quickstart's checks validate the rest.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Setup

- [X] T001 Record the baseline: run `./Scripts/verify.sh` on the unchanged code, timed, cold (fresh worktree) and warm, and keep the times for quickstart check 10 (specs/019-instrumented-build-script/quickstart.md)

---

## Phase 2: Foundational — remove Profiling

**Purpose**: The project has only Debug and Release before anything names the replacement.

- [X] T002 Delete the three `XCBuildConfiguration` blocks named Profiling (`5500000000000000000003`, `6600000000000000000003`, `7700000000000000000003`) and their three entries in the `XCConfigurationList`s, changing nothing else, in swiftSky.xcodeproj/project.pbxproj (research R6)
- [X] T003 Confirm `xcodebuild -list -project swiftSky.xcodeproj` shows only Debug and Release, and `git diff main -- swiftSky.xcodeproj` removes lines only (quickstart checks 1, 2)

**Checkpoint**: Profiling gone; Debug and Release untouched.

---

## Phase 3: User Story 1 — One command makes the instrumented build (Priority: P1) 🎯 MVP

**Goal**: `Scripts/build-instrumented.sh [ios|macos|both]` builds the optimised instrumented app(s) into `.build/instrumented/` and prints their absolute paths.

**Independent Test**: quickstart checks 3, 5, 7, 8, 9 (and 4, 6 by hand).

- [X] T004 [US1] Create Scripts/build-instrumented.sh (POSIX `sh`, `set -eu`, executable, header comment in `verify.sh`'s style citing 011 R1/R12 and this spec) implementing contracts/build-instrumented.md: argument parsing (`ios`, `macos`, `both`, default `both`; anything else or more than one → usage on stderr, exit 64), `cd` to the repository root, one `build()` function running research R1's `xcodebuild` command with `-derivedDataPath .build/instrumented` and output to stderr, then printing the absolute app path on stdout; macOS before iOS
- [X] T005 [US1] Run quickstart checks 3, 5, 7, 8, 9 against Scripts/build-instrumented.sh and fix any failure; record results in specs/019-instrumented-build-script/quickstart.md
- [X] T006 [US1] Run quickstart check 13 (C override removed → link fails), restore the script, and record the result in specs/019-instrumented-build-script/quickstart.md

**Checkpoint**: The instrumented build is one command.

---

## Phase 4: User Story 2 — `verify.sh` guards both builds (Priority: P2)

**Goal**: Two new stages fail the run if the instrumented macOS app lacks `dropped=` or the plain Release app carries any 001 check 27 probe.

**Independent Test**: quickstart checks 10, 11, 12.

- [X] T007 [US2] Add a section "Instrumented and Release builds (macOS)" to Scripts/verify.sh after the app-target builds, inside the `if [ -d swiftSky.xcodeproj ]` branch: stage `instrumented macOS build carries the instrumentation` (runs `Scripts/build-instrumented.sh macos`, then `strings -a` on the executable must find `dropped=`), and stage `Release macOS build carries no instrumentation (001 check 27)` (Release build into `.build/release-check/` with `CODE_SIGNING_ALLOWED=NO -quiet`, then `strings -a` must find none of `skipped=`, `dropped=`, `worst=`, `SWIFTSKY_INSTRUMENTATION`; print any found); both through `run_stage`, no launch, no simulator, no log (FR-008, FR-009); update the file's header comment to mention the two stages
- [X] T008 [US2] Run quickstart check 10 (`./Scripts/verify.sh`, timed warm and cold) and record the before/after times in specs/019-instrumented-build-script/quickstart.md
- [X] T009 [US2] Run quickstart checks 11 and 12 (each deliberate breakage once, then restore with `git checkout --`), confirm each fails the run, and record the results in specs/019-instrumented-build-script/quickstart.md

**Checkpoint**: The instrumented build cannot silently break again.

---

## Phase 5: User Story 3 — Documentation names one way (Priority: P3)

**Goal**: No document in scope calls Profiling a build that exists or carries instrumentation; 008 #12 and 009 #9 are annotated.

**Independent Test**: quickstart checks 14, 15, 16.

- [X] T010 [P] [US3] Reword CLAUDE.md: every "Debug/Profiling" or "Debug and Profiling" becomes Debug and the instrumented Release build (lines ~21, 114, 131, 141, 173, 218), and the allocation-counter paragraph (~192) names `Scripts/build-instrumented.sh` instead of the copied overrides and says the Profiling configuration was removed (019); add 019 to the "Built so far" list and `Scripts/build-instrumented.sh` beside `verify.sh`
- [X] T011 [P] [US3] Reword the Complexity Tracking row "Debug/profiling instrumentation … a third build configuration" in specs/001-metal-app-shell/plan.md to the instrumented Release build made by `Scripts/build-instrumented.sh` (019), keeping its justification
- [X] T012 [P] [US3] Reword the Profiling comments in Package.swift (lines ~44–46 and ~85–86) to the command-line condition and `Scripts/build-instrumented.sh`
- [X] T013 [P] [US3] Reword "Debug and Profiling builds only" doc comments to "Debug and instrumented Release builds only" in Sources/SwiftSkyPlatform/GameSurfaceView.swift (3), Sources/SwiftSkyPlatform/FrameTimeWindow.swift, Sources/SwiftSkyPlatform/OverlayRefreshSchedule.swift, Sources/SwiftSkyRendering/Debug/DebugOverlay.swift and Sources/SwiftSkyRendering/Debug/DebugTextPattern.swift
- [X] T014 [P] [US3] Add the research R7 note to check 12's result in specs/008-tap-to-order-ios/quickstart.md and to check 9's result in specs/009-click-to-order-macos/quickstart.md, and reword their "Reading the order log (Debug and Profiling)" headings and check-definition rows to the instrumented build (results otherwise unchanged)
- [X] T015 [P] [US3] In specs/011-draw-allocation-counter/quickstart.md, "The method" step 1: replace the hand-written `xcodebuild` command with `Scripts/build-instrumented.sh ios|macos` and the printed path, and replace "A Profiling build carries no instrumentation at all" with the history note (removed by 019); point step 2's app paths at `.build/instrumented/`
- [X] T016 [P] [US3] In specs/001-metal-app-shell/quickstart.md, specs/002-metal-text-rendering/quickstart.md, specs/003-debug-overlay/quickstart.md, specs/004-ship-newtonian-motion/quickstart.md, specs/006-ship-autopilot/quickstart.md, specs/007-ship-sprite-rendering/quickstart.md and specs/010-ship-path-prediction/quickstart.md: reword each Profiling mention per FR-012 (results that say a check was or was not run on a Profiling build get the R7 note; "Method since 011 … a Profiling build carries no instrumentation" points to the script; headings say Debug and instrumented Release)
- [X] T017 [US3] Run quickstart checks 14, 15, 16, confirm with `git diff --stat main` that no file outside FR-010–FR-012's list was reworded (FR-013), and record the results in specs/019-instrumented-build-script/quickstart.md

**Checkpoint**: The documentation sends every measurement to the script.

---

## Phase 6: Polish

- [ ] T018 Run `./Scripts/verify.sh` on the finished branch and record the result in specs/019-instrumented-build-script/quickstart.md
- [ ] T019 Leave quickstart checks 4 and 6 (launching the instrumented apps and reading the log) for the developer, recorded as open in specs/019-instrumented-build-script/quickstart.md; set the spec's Status line in specs/019-instrumented-build-script/spec.md

---

## Dependencies & Execution Order

- Phase 1 → Phase 2 → US1 (Phase 3) → US2 (Phase 4, needs the script) → US3 (Phase 5, needs the script's name and paths) → Phase 6.
- Within US3, T010–T016 touch different files and can run in parallel; T017 follows them.

## Parallel Example: User Story 3

```text
T010 CLAUDE.md   T011 001 plan   T012 Package.swift   T013 Sources/*   T014 008/009 quickstarts
T015 011 quickstart   T016 other quickstarts
```

## Implementation Strategy

MVP is US1: the script alone gives developers the working build. US2 then guards it, US3 corrects the
documentation. Commit after each phase.
