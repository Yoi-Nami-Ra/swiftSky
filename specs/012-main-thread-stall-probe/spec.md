# Feature Specification: Measure Main-Thread Stalls and Verify Continuous Resize Under Thread Sanitizer

**Feature Branch**: `012-main-thread-stall-probe`

**Created**: 2026-10-01

**Status**: Draft

**Input**: User description: "SKY-5 — Verify continuous resize under Thread Sanitizer" (`.tickets/5.yaml`).
Quickstart check 29 (SC-015, SC-016) of `specs/001-metal-app-shell` is only partial: a 30 s Thread
Sanitizer run showed zero data races, but the continuous-resize half was never run, because it needs a
window corner dragged for 10 seconds and the session cannot drive the UI. Decisions taken when the
ticket was started: nothing measures main-thread stalls today, so build a main-thread stall probe in
the instrumentation (option B) instead of relying on a coarse hang detector; the developer drags the
corner by hand, because Accessibility permission is not granted; record the result in 001's check 29
and its open-checks row.

## Overview

001 check 29 asks two things of a continuous macOS window resize: that it causes no data races, and
that it never stalls the main thread for longer than one frame interval. Resize is the path most likely
to break either, because it is the one that crosses from the main thread, where the window system
delivers size changes, to the frame loop's thread, which owns the surface and draws.

The race half can be judged today: the Thread Sanitizer reports every race it sees. The stall half
cannot. The frame statistics that 001 logs are measured on the frame loop's own thread, which keeps
drawing even when the main thread is busy, so a main thread that blocks for 50 ms during a drag leaves
no trace in them. A system hang detector would notice only stalls of a quarter of a second or more,
thirty times coarser than the one-frame limit (8.3 ms on a 120 Hz display).

This feature adds the missing measurement. In builds compiled with the instrumentation, the app
measures how long the main thread stays busy without returning to wait for its next event, and adds
the worst such stretch, and how many stretches went over the frame interval, to the frame summary it
already writes every 120 frames. With the probe in place, the developer drags a window corner
continuously for 10 seconds in two builds: the Thread Sanitizer build, which decides the race half, and
an optimised build with the instrumentation compiled in, which decides the stall half. Both results are
recorded in 001's check 29.

Out of scope: automating the drag (it needs Accessibility permission, which the session does not
have); iOS (check 29 is a macOS window resize; iOS rotation and Split View are covered by other
checks); fixing stalls in the window system's own work outside the app's code; showing the probe's
figures on the debug overlay; the iPad Split View check (SKY-6); and making the Profiling configuration
carry the instrumentation (SKY-36) — the probe follows the existing instrumentation condition, so it
will appear in Profiling builds once that is fixed, with no change here.

### Relationship to earlier specs

- **Verified**: 001 SC-015 (zero data races under the Thread Sanitizer, now including a continuous
  resize) and SC-016 (no main-thread stall beyond one frame interval during a continuous resize),
  recorded in 001's quickstart check 29.
- **Unchanged and still absolute**: 001 FR-021e (instrumentation in builds compiled with it only,
  absent from Release, output to the log only), FR-021f (the instrumentation does not allocate per
  frame), FR-020 (no per-frame allocation, now measured by 011's counter), the frame order of 001's
  frame-loop contract, and every layer-boundary rule. Nothing in the logic or rendering layers changes.
- **Extended**: the frame summary line (001 FR-021d, extended by 011) gains the main-thread figures.
  Its existing fields keep their names, order and meaning.

## Clarifications

### Session 2026-10-01

- Q: How are the summaries that cover the drag identified? → A: Builds with the instrumentation log one
  line when a window's live resize starts and one when it ends; the summaries covering the drag are those
  written after the start line up to and including the first one written after the end line (FR-013).
- Q: What if a stretch over the frame interval comes entirely from the window system's own work, with
  none of the app's code involved? → A: The gate stays absolute: any stretch over the interval is a FAIL.
  Its source is found from a sampled main-thread stack; a cause wholly inside the system is recorded in
  check 29 as a FAIL with that evidence and a follow-up ticket, never waived (FR-011).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers of swiftSky, who need to know whether a change makes the
app's main thread unresponsive (constitution Principles III and IV). Players see nothing.

### User Story 1 - Read the main thread's worst stall from the log (Priority: P1)

A developer runs a build with the instrumentation on macOS and reads the frame summaries from the log.
Each summary now says, for the time since the previous summary, the longest stretch the main thread
spent busy without going back to wait for an event, and how many such stretches lasted longer than the
current frame interval.

**Why this priority**: Without it, the stall half of check 29 cannot be measured at all, and story 2
cannot run.

**Independent Test**: Run the project's single test command: headless tests feed the measurement a
known sequence of busy and waiting stretches and check the reported worst stretch, the count over the
interval, and the restart after each summary. Then launch a Debug build and read one summary line with
`/usr/bin/log`.

**Acceptance Scenarios**:

1. **Given** a build with the instrumentation, **When** the app runs for at least 4 seconds, **Then**
   the log holds frame summary lines that carry the existing fields, unchanged, followed by the
   main-thread figures.
2. **Given** a main thread that is made to stay busy for a known time (for example 50 ms) once,
   **When** the next summary is written, **Then** its worst stretch is at least that long and its count
   over the frame interval is at least 1.
3. **Given** an idle app whose main thread only waits for events, **When** a summary is written,
   **Then** its worst stretch is below the frame interval and its count over the interval is 0.
4. **Given** a Release build, **When** its product is inspected as 001 SC-004a does, **Then** none of
   the probe is present.

---

### User Story 2 - Verify a continuous resize: no races, no main-thread stall (Priority: P2)

The developer launches the Thread Sanitizer build and drags a window corner continuously for 10
seconds, growing and shrinking the window. The sanitizer reports no race. They then do the same with
the optimised build that carries the instrumentation, and every summary written during the drag shows
no main-thread stretch longer than the frame interval. Both results are recorded as check 29's PASS. A
reported race or stall is found, fixed, and the drag repeated.

**Why this priority**: It is what the ticket asks for, and it closes 001 check 29. It comes second
because it needs story 1's probe.

**Independent Test**: Follow this feature's quickstart: build both apps, launch each, drag for 10
seconds, read the sanitizer output and the summaries, and compare with SC-003 and SC-004.

**Acceptance Scenarios**:

1. **Given** the Thread Sanitizer build, **When** a window corner is dragged continuously for 10
   seconds, **Then** the sanitizer reports zero data races and the app keeps drawing (SC-003).
2. **Given** the optimised build with the instrumentation, **When** the same drag is made, **Then**
   every summary covering the drag reports a worst main-thread stretch no longer than the frame
   interval and a count over the interval of 0 (SC-004).
3. **Given** a race or a stall reported during the drag, **When** the developer finds its source,
   **Then** it is fixed and the drag repeated until scenarios 1 and 2 hold.

### Edge Cases

- **Start-up**: launching the app, creating the window and the first surface keep the main thread
  busy once. The first summary of a run, and the first after the frame budget is relearned, may report
  a long stretch; only the summaries after it decide PASS (FR-006).
- **Waiting is not stalling**: a main thread that sleeps because it has nothing to do is responsive.
  Only time spent busy counts, never time spent waiting for the next event.
- **Live resize**: while a corner is dragged, the window system runs the main thread in its own
  tracking mode. The probe MUST keep measuring in that mode, or a drag would read as perfectly idle
  (FR-002).
- **Menus and modal panels**: opening a menu also runs the main thread in a tracking mode; the probe
  measures it the same way. A check that holds a menu open reads the figures for that time.
- **No summaries**: summaries are written by the frame loop every 120 frames. If the frame loop stops
  drawing (window hidden, minimised or fully covered), no summary is written; the probe's figures carry
  over to the next one, which therefore covers a longer time. A check reads only summaries whose
  frames were drawn while it ran.
- **The frame interval changes**: when the window moves to a display with a different refresh rate,
  the frame budget is relearned (001). The count over the interval uses the interval current at the
  moment a stretch ends.
- **Thread Sanitizer slow-down**: the sanitizer makes the app several times slower, so a sanitizer
  build's main thread can overrun the frame interval with no defect in the app. That build decides only
  the race half; its stall figures are recorded for information (SC-004).
- **Cross-thread hand-off**: the probe measures on the main thread and the summary is written on the
  frame loop's thread. Handing the figures over MUST itself be free of races, or the Thread Sanitizer
  run would report the probe (FR-004).

## Requirements *(mandatory)*

### Functional Requirements

**Measuring**

- **FR-001**: In every build compiled with the instrumentation (001 FR-021e's condition; Debug builds
  today, 011 research R1), the app MUST measure, on the main thread, each stretch of time the main
  thread spends busy between returning from a wait for its next event and starting the next wait.
- **FR-002**: The measurement MUST cover every mode the main thread runs in, including the tracking
  modes used during a window's live resize and while a menu is open.
- **FR-003**: Time the main thread spends waiting for an event MUST NOT be counted as busy.

**Reporting**

- **FR-004**: The frame summary MUST report, for the time since the previous summary: the longest busy
  stretch of the main thread, in milliseconds, and the number of busy stretches longer than the frame
  interval current when each ended. The new fields MUST follow the existing fields, which keep their
  names, order and meaning. The figures MUST then restart, so each summary covers only its own time.
  Passing the figures from the main thread to the frame loop's thread MUST be free of data races.
- **FR-005**: A busy stretch still running when a summary is written MUST be counted in the summary in
  which it ends, so a long stall is never split across two summaries and reported as two short ones.
- **FR-006**: The figures MUST restart whenever the existing measurement restarts (the frame budget is
  relearned, 001), so the summary that follows a restart can be told apart as a start-up summary.

**Cost and builds**

- **FR-007**: The probe MUST NOT allocate, lock, or block either thread. On the main thread its work per
  busy stretch MUST be bounded: reading the clock twice and updating a fixed number of values. On the
  frame loop's thread it MUST add no work to a frame other than the one that writes the summary. Zero
  app-side allocations per frame MUST still hold, as measured by 011's counter (SC-006).
- **FR-008**: The probe MUST be compiled under the same condition as the rest of the instrumentation
  only and MUST be absent from Release builds, confirmed by inspecting the built product as 001 SC-004a
  does (001 FR-021e).
- **FR-009**: The probe MUST live with the rest of the instrumentation in the platform layer, with no
  change to the logic or rendering layers (Principle I). It is required on macOS; it MAY run on iOS if
  that needs no separate code path.

**Testability**

- **FR-010**: The measurement's behaviour — the worst stretch, the count over the interval, the
  restart, a stretch that ends after a summary, an interval change — MUST be verifiable by automated
  tests that need no graphics device and no running app, run by the project's single checked-in test
  command (Principle II).

**Verification**

- **FR-011**: The result MUST be recorded in 001's quickstart check 29 and its open-checks row: the date,
  the Mac and display, the builds, the drag's length and how it was made, the sanitizer's verdict, and
  the stall figures of every summary covering the drag. A race or stall found MUST be fixed and the drag
  repeated before PASS is recorded. A stall whose sampled main-thread stack shows the time spent wholly
  in system code, with none of the app's code on it, is still a FAIL: it is recorded with that evidence
  and a follow-up ticket, and is not waived.
- **FR-012**: This feature's quickstart MUST describe the drag procedure — the two builds, how to read
  the sanitizer output and the summaries, and the PASS rule — so it can be repeated by hand for later
  resize work.

- **FR-013**: In builds compiled with the instrumentation, the app MUST write one log line when a
  window's live resize starts and one when it ends, in the same log category as the frame summary, so the
  summaries covering a drag can be found from the log alone. A summary covers the drag when it is written
  after the start line, up to and including the first summary written after the end line.

### Key Entities

- **Busy stretch**: a stretch of time the main thread spends handling work between two waits for an
  event; its length in milliseconds.
- **Main-thread figures**: per summary interval, the longest busy stretch and the number of busy
  stretches longer than the frame interval. Restarted after each summary.
- **Frame interval**: the display's frame interval the frame loop has learned (001), the budget field
  already in the summary.
- **Live-resize markers**: the two log lines written when a window's live resize starts and ends; they
  bracket the summaries that cover a drag.
- **Frame summary**: the existing log line written every 120 frames, extended with the main-thread
  figures.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In the automated tests, a sequence of busy stretches with known lengths reports exactly
  the longest of them and exactly the number longer than the interval; a summary taken mid-stretch
  leaves that stretch to the next summary; after a restart the figures start from zero. Each result holds
  on 10 consecutive test runs.
- **SC-002**: A Debug build on macOS writes frame summary lines that carry the main-thread figures after
  the existing fields; when its main thread is deliberately kept busy for 50 ms once, the next summary
  reports a worst stretch of at least 50 ms and a count over the interval of at least 1; idle, every
  summary after the first reports a count over the interval of 0. A Release build contains none of the
  probe's symbols or strings.
- **SC-003**: The Thread Sanitizer build of the macOS app, with a window corner dragged continuously for
  at least 10 seconds through a range of sizes, reports zero data races, and the app keeps drawing
  throughout (summaries keep being written). This is the race half of 001 check 29 (SC-015).
- **SC-004**: The optimised build with the instrumentation compiled in (011 research R12), with the
  same drag, reports in every summary covering the drag (FR-013) a worst main-thread stretch no longer than the
  frame interval and a count over the interval of 0. This is the stall half of 001 check 29 (SC-016).
  The sanitizer build's stall figures are recorded beside it for information.
- **SC-005**: Optimised instrumented builds of `main` (before) and of this branch (after), run idle for
  30 seconds each on the same Mac, are recorded side by side: the after run's mean frame time is within
  10% or 0.1 ms of the before run's, whichever is larger, and both report `dropped=0` outside launch.
- **SC-006**: The optimised instrumented build, run idle for 60 seconds by 011's method, still reports
  zero app-side allocations and zero allocating frames in every summary after the first.
- **SC-007**: The project's single verification command passes, with every existing test still passing
  and the new tests running headlessly and deterministically.

## Assumptions

- **The developer drags by hand.** The session cannot drive the UI (AppleScript to System Events
  returns `-1743`; Accessibility permission is not granted), so the drag is made by a person. "Continuous"
  means the corner is kept moving for the whole 10 seconds, growing and shrinking the window, without
  releasing the mouse button.
- **Two builds, two halves.** The Thread Sanitizer slows the app down several times, so it decides the
  race half only. The stall half is decided by the optimised build with the instrumentation (011 R12),
  as the allocation check is, because that is the code that ships.
- **"One frame interval" is the learned budget.** On the development Mac's 120 Hz display it is 8.33 ms,
  the `budget=` field of the summary.
- **"Stall" means a busy stretch, not a late event.** The probe measures how long the main thread stays
  busy at a time. That bounds how late any event can be handled, which is what makes the app feel
  unresponsive; it does not time individual events.
- **Summary interval unchanged.** The figures are reported on the existing 120-frame summary, so
  reporting adds no formatting to ordinary frames.
- **No overlay change.** The figures go to the log only (001 FR-021e).

## Dependencies

- **001-metal-app-shell**: the frame loop, its contract, the instrumentation and its summary line, the
  frame budget, and checks 27 and 29. Merged to `main`.
- **011-draw-allocation-counter**: the allocation counter and "The method", used for SC-005 and SC-006,
  and the optimised instrumented build (R12). Merged to `main`.
- **Unblocks**: nothing directly; later checks that drag, resize or open menus can read the same figures.
