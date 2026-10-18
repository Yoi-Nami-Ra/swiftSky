# Tasks: iOS GPU Frame Capture Check

**Input**: Design documents from `/specs/021-ios-gpu-frame-capture/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, quickstart.md

**Tests**: None requested. The feature changes no code; `./Scripts/verify.sh` must stay green.

**Organization**: One phase per user story. Amended 2026-10-18: no task is manual; the observation is
made by `specs/021-ios-gpu-frame-capture/probe.sh` (spec FR-002) and summarised in
`specs/021-ios-gpu-frame-capture/capture-notes.md`.

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

**Checkpoint**: the notes file exists (its template was replaced for the lldb method on 2026-10-18).

---

## Phase 2: User Story 1 — The full-surface draw in a captured frame (Priority: P1) 🎯 MVP

**Goal**: Close check 4 on iOS (SC-019, FR-002a).

**Independent Test**: The probe output, read per quickstart.md, shows one quad draw per frame, the
sampled pipeline and buffer labels, the 4-vertex triangle strip at (−1, −1)…(1, 1), and no viewport
change.

- [x] T003 [US1] Run `specs/021-ios-gpu-frame-capture/probe.sh` (booted simulator) and fill the Header, Counts and Sample 1 sections of `specs/021-ios-gpu-frame-capture/capture-notes.md` from its output, per quickstart.md "Read the output"; if lldb cannot attach or break, stop and report (spec Edge Cases)
- [x] T004 [US1] Judge check 4 against spec FR-003 and research R2 from `specs/021-ios-gpu-frame-capture/capture-notes.md`; write `**Check 4 — PASS|FAIL on iOS, <simulator|device> (<date>, SKY-18).**` with build, destination and observations into `specs/001-metal-app-shell/quickstart.md`, after the last existing check record and before the summary section, in the shape data-model.md describes
- [x] T005 [US1] If check 4 failed: file a bug ticket with `/tickets` (title naming what the capture showed, phase MVP, platform ios) and add its key to the check 4 record in `specs/001-metal-app-shell/quickstart.md`; otherwise mark this task done with "not needed" — not needed (check 4 passed)

**Checkpoint**: check 4's iOS result is recorded.

---

## Phase 3: User Story 2 — Pipeline and geometry built once (Priority: P2)

**Goal**: Close check 5 on iOS (FR-002b).

**Independent Test**: The probe output shows zero creation calls and equal pipeline and buffer addresses
in the two samples.

- [ ] T006 [US2] From the same `probe.sh` output as T003, fill the Sample 2 section of `specs/021-ios-gpu-frame-capture/capture-notes.md`, including whether its pipeline and buffer addresses equal sample 1's
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
- T006 reads the same probe output as T003: the two samples come from one app run.

### User Story Dependencies

- **US1**: none beyond Setup.
- **US2**: T006 follows T003 in the same run; T007 is independent of T004.
- **US3**: needs T004 and T007 written.

### Within Each User Story

- Probe output → notes → judge and record → ticket only on FAIL.

### Parallel Opportunities

- T004 and T007 write adjacent paragraphs of one file, so they are not [P].
- T003 and T006 share one probe run: keep its output for both.

---

## Parallel Example: User Story 1

```text
Phase 2: T003 (run probe.sh, keep its output in the phase's notes), T004, T005
Phase 3: T006 from the same output (passed on in the hand-off notes), T007, T008
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phase 1, then T003 (the probe).
2. Record check 4 (T004–T005). This alone closes SC-019's iOS half.

### Incremental Delivery

1. Check 4 → check 5 → summary → verify and close the ticket.

---

## Notes

- No task is manual. If `probe.sh` cannot attach or break, the phase stops and reports `blocked`;
  the hand capture in Xcode is the developer's fallback.
- Commit after each phase.
