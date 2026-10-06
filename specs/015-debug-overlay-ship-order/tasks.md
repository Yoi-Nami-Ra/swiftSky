# Tasks: Ship and Order Lines on the Debug Overlay

**Input**: Design documents from `/specs/015-debug-overlay-ship-order/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/debug-overlay-ship-order.md, quickstart.md

**Tests**: requested by the spec (FR-013, US4): the signed writer, the degree conversion and the line
composition get headless Swift Testing tests. The drawing itself is 002's and unchanged.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1–US4 from spec.md

## Phase 1: Setup

- [X] T001 Confirm the baseline: run `./Scripts/verify.sh` on `015-debug-overlay-ship-order` before any code change and note the test count

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: the signed writer and the snapshot plumbing every story needs.

- [X] T002 [P] Add `writeSignedHundredths(_:width:limit:)` per contract C1 to Sources/SwiftSkyRendering/Text/TextBuffer.swift: factor the rounding and digit writing of `writeHundredths` into a private helper taking the rounded hundredths and a sign flag; the sign is written only for a negative value whose rounded hundredths are not zero; padding counts the sign; NaN → `0.00`; magnitudes clamped as in `writeHundredths`; `writeHundredths`' output unchanged
- [X] T003 [P] Add tests for C1 to Tests/SwiftSkyRenderingTests/DecimalWritingTests.swift: the contract table at width 9 (0, −0.004, −0.005, 12.345, −1234.5, ±99999.99, −123456.789, NaN), width 0, −infinity clamped with a sign, and the limit respected mid-number including after the sign
- [X] T004 Add `DebugOverlayShip` (with nested `Order`) and its memberwise and `init(_ state: SimulationState)` initialisers per contract C2 and data-model.md inside the `#if SWIFTSKY_INSTRUMENTATION` block of Sources/SwiftSkyRendering/Debug/DebugOverlay.swift (`import SwiftSkySimulation`), plus `public var ship: DebugOverlayShip?` on `DebugOverlay` (not yet written)
- [X] T005 Replace `Renderer.updateDebugOverlay(_:)` with `updateDebugOverlay(_:ship:)` per contract C4 in Sources/SwiftSkyRendering/Renderer.swift, and pass `DebugOverlayShip(state)` from step 3a in Sources/SwiftSkyPlatform/FrameLoop.swift (state before step 4's advance)

**Checkpoint**: `verify.sh` passes; the overlay still shows its six lines.

## Phase 3: User Story 1 — Developer reads the ship's live state (Priority: P1) 🎯 MVP

**Goal**: the five ship lines under the frame statistics.

**Independent Test**: quickstart checks 2 and 3 on the iPhone 17 Pro simulator.

- [X] T006 [US1] Add `static func headingDegrees(_:)` (research R4: −180.00 after rounding → 180) and write the `pos`, `vel`, `speed`, `heading` and `turn` lines after the `ticks` line when `ship` is set, per contract C3 (eight-column `StaticString` labels, `writeSignedHundredths` width 9, units ` u/s`, ` deg`, ` deg/s`; speed from the exact velocity; turn = ω × 180/π), in Sources/SwiftSkyRendering/Debug/DebugOverlay.swift
- [X] T007 [US1] Add ship-line tests to Tests/SwiftSkyRenderingTests/DebugOverlayTests.swift: the at-rest example of C3 (lines 7–11), the in-flight example's ship lines, six lines only when `ship` is `nil`, `headingDegrees` at 0, π (180), −π + 1e-9 (180), −π/2 (−90) and the 179.995° boundary, and a turn of π rad/s → `180.00 deg/s`
- [X] T008 [US1] Run quickstart checks 2 and 3 on the iPhone 17 Pro simulator (launch, `simctl io screenshot`) and record the results in specs/015-debug-overlay-ship-order/quickstart.md

**Checkpoint**: the ship lines are on screen and correct.

## Phase 4: User Story 2 — Developer follows an order on the overlay (Priority: P2)

**Goal**: `order   none` without an order; phase, destination and distance with one.

**Independent Test**: quickstart checks 2, 4 and 5 on the simulator; check 6 on macOS.

- [X] T009 [US2] Write the `order` line (`none`, or the phase as a lower-case `StaticString` from a `switch` over `AutopilotPhase`) and, with an order, the `dest` and `dist` lines per contract C3 in Sources/SwiftSkyRendering/Debug/DebugOverlay.swift
- [X] T010 [US2] Add order-line tests to Tests/SwiftSkyRenderingTests/DebugOverlayTests.swift: `order   none` as the last line with no `dest`/`dist`; the in-flight example of C3 in full; each phase's text; `arrived` keeps `dest` and `dist`; `DebugOverlayShip(state)` from a `SimulationState` with and without an order (fields copied, distance equals `state.distanceRemaining`), and a phase of `nil` with an order treated as no order (data-model.md)
- [X] T011 [US2] Add the capacity and width test to Tests/SwiftSkyRenderingTests/DebugOverlayTests.swift: at the normal-range maxima (positions and destination ±99,999.99, speed components giving < 100,000, an order) every line is ≤ 33 characters, the buffer holds fewer than 384 characters, and nothing overflows; a value beyond the column is written in full
- [X] T012 [US2] Run quickstart checks 4, 5 and 7 on the iPhone 17 Pro simulator (taps with the simulator control tool, screenshots, log stream for `order … world=`) and record the results in specs/015-debug-overlay-ship-order/quickstart.md
- [X] T013 [US2] Leave quickstart check 6 (macOS, clicks by hand) for the user: mark it as pending in specs/015-debug-overlay-ship-order/quickstart.md

**Checkpoint**: both line groups are correct; tests pass.

## Phase 5: User Story 3 — No per-frame cost, absent from Release (Priority: P3)

**Goal**: zero allocations per frame (SC-004); nothing new in Release (SC-005).

**Independent Test**: quickstart checks 9–11.

- [X] T014 [US3] Run quickstart check 9 (011 check 25, optimised instrumented build, iOS simulator, 60 s with orders tapped) on this branch and, for the before/after evidence Principle III requires, on `main` (d6f004e) with the same procedure; record `allocs=`/`allocframes=` and mean/worst frame time for both in specs/015-debug-overlay-ship-order/quickstart.md
- [X] T015 [US3] Run quickstart check 10 on macOS idle (optimised instrumented build launched with `open -n … --args --debug-ship-spin`, 60 s, no order, so the ship lines change every refresh) and record it; leave the run with clicked orders for the user, marked pending, in specs/015-debug-overlay-ship-order/quickstart.md
- [X] T016 [US3] Run quickstart check 11 (plain Release build for macOS; `nm` unstripped and after `strip -rSTx`, `strings`) and record the counts in specs/015-debug-overlay-ship-order/quickstart.md

**Checkpoint**: SC-004 (iOS) and SC-005 confirmed.

## Phase 6: User Story 4 — Verified without a GPU (Priority: P4)

**Goal**: the new tests run headlessly from the single command.

**Independent Test**: `./Scripts/verify.sh`.

- [X] T017 [US4] Run `./Scripts/verify.sh` (quickstart check 1) and confirm the new suites run without a Metal device and the test count rose from T001's; confirm from the diff that the log lines and the six frame-statistic lines are unchanged (FR-012)

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T018 [P] Add spec 015 to CLAUDE.md: the built-so-far list and a key-locations note (`DebugOverlayShip` taken at step 3a from the latest tick, never the drawn pose; `writeSignedHundredths`; the Release strings check skips phase names)
- [X] T019 [P] Run quickstart check 8 (`--no-debug-overlay`, `--debug-text`) on the simulator and record it in specs/015-debug-overlay-ship-order/quickstart.md
- [X] T020 Final `./Scripts/verify.sh` and fill in the Results section of specs/015-debug-overlay-ship-order/quickstart.md

## Dependencies & Execution Order

- Phase 1 → Phase 2 → US1 → US2 → US3 → US4 → Polish. US2 extends the same `write` as US1, so it
  follows it; US3 measures the finished lines.
- Within Phase 2, T002 and T003 can run in parallel; T004 precedes T005.
- T007 needs T006; T010 and T011 need T009.

## Parallel Examples

- Phase 2: T002 (TextBuffer.swift) with T003 (DecimalWritingTests.swift).
- Polish: T018 (CLAUDE.md) with T019 (simulator check).

## Implementation Strategy

MVP is US1: the ship lines alone already answer "what is the ship doing". US2 adds the order block on
the same write path; US3 and US4 are gates. Commit at the end of each phase.
