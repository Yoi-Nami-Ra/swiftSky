# Tasks: iOS GPU Frame Capture Check

**Input**: Design documents from `/specs/021-ios-gpu-frame-capture/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: None requested. The feature changes no code; `./Scripts/verify.sh` must stay green.

**Organization**: One phase per user story. Tasks marked **MANUAL** are done by the developer in Xcode
(this session cannot drive the GPU debugger, spec FR-002); every other task is done by the session
from the developer's notes in `specs/021-ios-gpu-frame-capture/capture-notes.md`.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)

## Path Conventions

- Feature docs: `specs/021-ios-gpu-frame-capture/`
- The record: `specs/001-metal-app-shell/quickstart.md`
- Read-only evidence subject: `Sources/SwiftSkyRendering/{FullscreenQuad,Renderer}.swift`, `Shaders.metal`

---

## Phase 1: Setup

**Purpose**: A baseline and a place for the developer's observations.

- [x] T001 Run `./Scripts/verify.sh` on branch `021-ios-gpu-frame-capture` and confirm it passes before anything changes
- [x] T002 Create `specs/021-ios-gpu-frame-capture/capture-notes.md` with a header holding T001's verify result and empty fields for Xcode version, build, arguments and destination, then one empty section per observation in data-model.md's "Captured frame" table (draws in the pass, pipeline label, buffer label, geometry, pixel history ×5, creation calls ×2 captures, object identity ×2 captures)

**Checkpoint**: the notes file exists; the developer can fill it while capturing.

---

## Phase 2: User Story 1 — The full-surface draw in a captured frame (Priority: P1) 🎯 MVP

**Goal**: Close check 4 on iOS (SC-019, FR-002a).

**Independent Test**: The first capture, read per quickstart.md "Check 4", shows the quad draw with its
labels, 4-vertex triangle strip at (−1, −1)…(1, 1), and in the pixel history of all four corners and
the centre.

- [ ] T003 [US1] **MANUAL** Capture frame 1 of the Debug iOS app with `--no-ship --no-debug-overlay` per `specs/021-ios-gpu-frame-capture/quickstart.md` Setup and "Check 4", in the simulator (device only if the simulator cannot be captured, research R1), and fill the check 4 sections of `specs/021-ios-gpu-frame-capture/capture-notes.md`
- [ ] T004 [US1] Judge check 4 against spec FR-003 and research R2 from `specs/021-ios-gpu-frame-capture/capture-notes.md`; write `**Check 4 — PASS|FAIL on iOS, <simulator|device> (<date>, SKY-18).**` with build, destination and observations into `specs/001-metal-app-shell/quickstart.md`, after the last existing check record and before the summary section, in the shape data-model.md describes
- [ ] T005 [US1] If check 4 failed: file a bug ticket with `/tickets` (title naming what the capture showed, phase MVP, platform ios) and add its key to the check 4 record in `specs/001-metal-app-shell/quickstart.md`; otherwise mark this task done with "not needed"

**Checkpoint**: check 4's iOS result is recorded.

---

## Phase 3: User Story 2 — Pipeline and geometry built once (Priority: P2)

**Goal**: Close check 5 on iOS (FR-002b).

**Independent Test**: Two captures in one run, read per quickstart.md "Check 5", show no creation calls,
one object of each label, and the same identities.

- [ ] T006 [US2] **MANUAL** In the same run as T003, wait at least five seconds, capture frame 2, and fill the check 5 sections of `specs/021-ios-gpu-frame-capture/capture-notes.md` for both captures (creation calls, object counts, identities) per quickstart.md "Check 5"
- [ ] T007 [US2] Judge check 5 against spec FR-004 and research R3 from `specs/021-ios-gpu-frame-capture/capture-notes.md`; write the `**Check 5 — …**` record into `specs/001-metal-app-shell/quickstart.md` directly after the check 4 record
- [ ] T008 [US2] If check 5 failed: file a bug ticket as in T005 and add its key to the check 5 record in `specs/001-metal-app-shell/quickstart.md`; otherwise mark this task done with "not needed"

**Checkpoint**: check 5's iOS result is recorded.

---

## Phase 4: User Story 3 — The summary says what is still open (Priority: P3)

**Goal**: 001's quickstart summary matches the new records (FR-006).

**Independent Test**: The open-checks table and the paragraph above it in 001's quickstart agree with
the check 4 and 5 records.

- [ ] T009 [US3] Check whether SKY-19 has recorded the macOS half of checks 4 and 5 (`python3 -I ~/.claude/skills/tickets/scripts/tickets.py desc 19` and a search for "Check 4 — " in `specs/001-metal-app-shell/quickstart.md`)
- [ ] T010 [US3] In the summary of `specs/001-metal-app-shell/quickstart.md`: add a sentence above the open-checks table saying the iOS half of checks 4 and 5 closed on the date (SKY-18), and change the table's rows for 4 and 5 to say macOS only (SKY-19) with the reason, or remove them if T009 found the macOS half recorded; on a FAIL, keep the row and name the bug ticket

**Checkpoint**: the quickstart is consistent.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [ ] T011 Run `./Scripts/verify.sh` and confirm it passes and that `git diff --stat main` lists no file under `Sources/` (spec FR-008, SC-004)
- [ ] T012 Check that `git diff --stat main` adds no image, `.gputrace` or other binary file and that `specs/021-ios-gpu-frame-capture/capture-notes.md` holds only text observations (spec FR-005)
- [ ] T013 Set SKY-18 to `done` with `python3 -I ~/.claude/skills/tickets/scripts/tickets.py set 18 status=done` when both checks passed, or leave it `in-progress` and report if either failed

---

## Dependencies & Execution Order

### Phase Dependencies

- Setup (Phase 1) → US1 (Phase 2) → US2 (Phase 3) → US3 (Phase 4) → Polish (Phase 5).
- US2's capture (T006) must be in the same app run as US1's (T003): the identities are compared
  across the two.

### User Story Dependencies

- **US1**: none beyond Setup.
- **US2**: T006 follows T003 in the same run; T007 is independent of T004.
- **US3**: needs T004 and T007 written.

### Within Each User Story

- MANUAL capture → judge and record → ticket only on FAIL.

### Parallel Opportunities

- T004 and T007 write adjacent paragraphs of one file, so they are not [P].
- The MANUAL tasks T003 and T006 are one sitting for the developer: do them back to back, then hand
  the notes over.

---

## Parallel Example: User Story 1

```text
Developer: T003 then T006 (one Xcode session, one app run)
Session:   T004, T005, then T007, T008 from the filled notes
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1, then T003 by hand.
2. Record check 4 (T004–T005). This alone closes SC-019's iOS half.

### Incremental Delivery

1. Check 4 → check 5 → summary → verify and close the ticket.

---

## Notes

- **MANUAL** tasks cannot be done by an automated phase agent. After Phase 1, the developer does T003
  and T006 in one sitting and fills `capture-notes.md`; only then do phases 2 and 3 run. A phase agent
  marks a MANUAL task `[x]` when its sections of `capture-notes.md` are filled, and reports `blocked`
  when they are not.
- Commit after each phase.
