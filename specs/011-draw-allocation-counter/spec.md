# Feature Specification: Count Draw-Path Allocations and Verify Zero on iOS

**Feature Branch**: `011-draw-allocation-counter`

**Created**: 2026-10-01

**Status**: Implemented

**Input**: User description: "SKY-3 — Verify zero draw-path allocations on iOS" (`.tickets/3.yaml`).
Quickstart check 25 (SC-004) of `specs/001-metal-app-shell` is not verified; today there is only
structural evidence. Decisions taken when the ticket was started: build the draw-path allocation
counter that 001 FR-021d requires but that was never built, instead of attaching Instruments (whose
recording failed to attach or never finished in 002 check 15, 003 check 13 and 009 check 9); verify on
the iPhone 17 Pro simulator (iOS 27.0); leave the macOS run to SKY-4; record the result in 001's check 25
and write the method down so the later checks that cite "the method of SKY-3" can reuse it.

## Overview

001 promised that Debug and Profiling builds would report, in their log, how many heap allocations the
per-frame draw path makes (FR-021d), and that this count would be the evidence for SC-004: zero
allocations per frame over a sustained run. Only half of that was built. The frame summary reports
timing, skipped and dropped frames, but nothing counts allocations, so check 25 was left "not
verified", and six later checks (002 #15, 003 #13, 004 #8, 006 #11, 008 #12, 010 #10) are waiting on
an Instruments method that has never worked from a session.

This feature builds the missing counter. In builds compiled with the instrumentation (Debug builds
today; research R1), the frame loop counts every
heap allocation made on its own thread while it handles a frame, from draining events to submitting the
draw, and adds the counts to the frame summary it already writes every 120 frames. Allocations made
inside the system's graphics framework while the app submits its work are counted separately: the
renderer already notes that the framework allocates internally when it creates a command buffer and an
encoder (`Renderer.render`), and that cost belongs to the API, not to the app. Frames that apply a
queued event (a resize, a tap) are counted separately too, because 008 and 009 only require frames
*without* an event to be free of allocations.

With the counter in place, the app is run on the iOS simulator for 60 seconds and the summaries are
read back from the log. Zero allocations by the app's own code on every frame without an event is a
PASS for check 25. Anything else is found from the counter, fixed, and re-run.

Out of scope: the macOS run (SKY-4); re-running the later checks that cite this method (002 #15,
003 #13, 004 #8, 006 #11, 008 #12, 010 #10) — each is recorded by its own feature or ticket; a
physical-device run; reducing the graphics framework's own allocations; showing the counts on the debug
overlay; any change to what the app draws; and making the Profiling configuration carry the
instrumentation into the package's layer targets, which it does not today (found while planning,
research R1) — the counter follows the existing `SWIFTSKY_INSTRUMENTATION` condition, so it will
appear in Profiling builds once that is fixed, with no change here.

### Relationship to earlier specs

- **Completed**: 001 FR-021d's "draw-path allocation counts", which was promised and not built.
- **Unchanged and still absolute**: 001 FR-021e (instrumentation in Debug and Profiling builds only,
  absent from Release, output to the log only), FR-021f (the instrumentation itself does not allocate per
  frame), FR-020 (no per-frame allocation), the frame order of 001's frame-loop contract, and every
  layer-boundary rule. Nothing in the logic or rendering layers changes.
- **Extended**: the frame summary line (001 FR-021d, written every 120 frames) gains the allocation
  counts. Its existing fields keep their names, order and meaning.
- **Verified**: 001 SC-004 on iOS, recorded in 001's quickstart check 25.

## Clarifications

### Session 2026-10-01

- Q: Which build decides check 25's PASS, given that an unoptimised Debug build can allocate where the
  shipped code does not? → A: The Profiling build (optimised, with the counter compiled in) decides
  PASS; the Debug build's figures are recorded beside it for information (SC-003). **Revised during
  planning**: the Profiling configuration builds the package's layer targets with their Release settings,
  so `SWIFTSKY_INSTRUMENTATION` reaches only the app module and a Profiling build carries no frame
  instrumentation at all (research R1). The Debug build therefore decides PASS. An unoptimised build
  allocates at least as often as an optimised one, so its zero is the stricter result. **Revised again
  during implementation**: "stricter" turned out to mean "wrong" — an unoptimised build allocates on
  every `for` loop over a range or an inline array (the standard library's unspecialised
  `IndexingIterator.next`), which the shipped code never does (research R12). An optimised build with
  the counter compiled in is made instead by passing the instrumentation condition on the `xcodebuild`
  command line to a Release build, which reaches the package targets too (R12). That build decides
  PASS, as first answered; the Debug figures are recorded for information.
- Q: How is the counter's overhead (SC-005) measured? → A: Profiling builds of `main` and of this branch
  on the same simulator, 30 s idle each; the after run's mean frame time is within 10% or 0.1 ms of the
  before run's, whichever is larger, and both report `dropped=0` outside launch (SC-005). **Revised during
  planning**, for the same reason: Debug builds of `main` and of this branch, as the only builds that
  carry the instrumentation. **Revised again during implementation**: the optimised instrumented build
  of R12, of `main` and of this branch.

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers of swiftSky, who need a repeatable way to prove that a
change keeps the frame path free of allocations (constitution Principle III). Players see nothing.

### User Story 1 - Read the frame path's allocations from the log (Priority: P1)

A developer runs a Debug build on either platform and reads the frame summaries from the
log. Each summary now says how many heap allocations the app's own code made on the frame loop's thread
since the previous summary, how many the graphics framework made while the frame was submitted, how
many frames allocated at all, and how many of the counted allocations came from frames that applied a
queued event.

**Why this priority**: It is the missing piece of 001 FR-021d, and every later allocation check depends
on it. Without it, story 2 cannot be measured.

**Independent Test**: Run the project's single test command: headless tests check that the counter
counts a known number of allocations made on the counted thread, ignores allocations on other threads,
counts nothing when nothing is allocated, and keeps the app's and the framework's counts apart. Then
launch a Debug build and read one summary line with `/usr/bin/log`.

**Acceptance Scenarios**:

1. **Given** a Debug build, **When** the app runs for at least 4 seconds, **Then** the log holds frame
   summary lines that carry the existing fields, unchanged, followed by the allocation counts.
2. **Given** the counter running on a thread, **When** that thread makes a known number of allocations
   inside a counted frame, **Then** the app-side count goes up by exactly that number; **When** another
   thread allocates at the same time, **Then** the count does not change.
3. **Given** an allocation made from inside a call into the graphics framework, **When** it is counted,
   **Then** it goes to the framework count and not to the app-side count.
4. **Given** a Release build, **When** its product is inspected as 001 SC-004a does, **Then** none of the
   counter is present, and the summary line is not written.

---

### User Story 2 - Verify zero draw-path allocations on iOS (Priority: P2)

A developer runs the iOS optimised instrumented build on the iPhone 17 Pro simulator for 60 seconds with the
default launch arguments (ship and debug overlay shown) and gives no input. Every summary after the first reports zero
app-side allocations. The result is recorded as PASS in 001's quickstart check 25. If a summary reports
an allocation, the developer uses the counter to find it, fixes it, and runs again.

**Why this priority**: It is what the ticket asks for, and it closes 001's last open allocation check on
iOS. It comes second because it needs story 1's counter.

**Independent Test**: Build and launch the iOS optimised instrumented app on the booted simulator, wait 60 seconds,
read the summaries with `/usr/bin/log`, and compare them with the targets in SC-003.

**Acceptance Scenarios**:

1. **Given** the iOS optimised instrumented app running idle on the simulator, **When** 60 seconds have passed, **Then**
   every summary after the first reports zero app-side allocations and zero frames that allocated
   (SC-003).
2. **Given** the same run, **When** the framework count is read, **Then** it is recorded in the
   quickstart beside the result, as a reference for later runs (SC-004).
3. **Given** a summary that reports an app-side allocation, **When** the developer finds its source,
   **Then** the allocation is removed and the run is repeated until story 2's first scenario holds.

---

### User Story 3 - Reuse the method in later checks (Priority: P3)

A developer working on SKY-4 or on one of the later checks that cite "the method of SKY-3" follows a
short written method: which build to use, how long to run, which log command reads the summaries, and
which numbers decide PASS. They need no Instruments session.

**Why this priority**: The ticket asks for it, and seven checks wait on it. It comes last because it
only writes down what stories 1 and 2 establish.

**Independent Test**: Read the method in this feature's quickstart and follow it on macOS without any
other guidance; it yields a summary line and a PASS or FAIL against the same targets.

**Acceptance Scenarios**:

1. **Given** the method, **When** a developer follows it on either platform, **Then** they get the
   counts and a PASS or FAIL decision without opening Instruments.
2. **Given** a quickstart check that cites "the method of SKY-3", **When** a reader looks it up, **Then**
   001's check 25 points to the method.

### Edge Cases

- **Start-up**: the first frames create pipelines, textures and caches once, and may allocate. The first
  summary of a run, and the first after the frame budget is relearned, may
  report allocations; only the summaries after it decide PASS (FR-007).
- **Event frames**: draining the event queue may allocate when there is an event (a resize, a rotation,
  a tap). Those frames are reported separately (FR-004) and do not decide PASS for an idle run; 008's
  and 009's checks read them.
- **Skipped frames**: a frame skipped for want of a drawable or a renderable surface is still counted up
  to the point where it returns.
- **Other threads**: allocations on the main thread (UI, gesture recognisers, logging) are not on the
  frame path and are not counted (FR-002).
- **The summary itself**: the frame that writes the summary formats a log message; that work happens
  outside the counted stretch, so it never counts against the frame path (FR-006).
- **Overflow and wrap**: the counts are reset after each summary; a summary covers at most a few seconds,
  so no count can overflow.
- **Instruments attached**: running under an allocation profiler as well must not break the counter or
  the app; their numbers need not match, because the profiler sees every thread.

## Requirements *(mandatory)*

### Functional Requirements

**Counting**

- **FR-001**: In every build compiled with the instrumentation (001 FR-021e's condition; Debug builds today,
  research R1), the app MUST count every heap allocation made on the frame
  loop's thread while it handles a frame: from the start of the frame callback until the draw has been
  submitted (001's frame-loop contract, steps 1 to 5).
- **FR-002**: Allocations made on any other thread, or on the frame loop's thread outside a frame, MUST
  NOT be counted.
- **FR-003**: Allocations made inside the graphics framework's own calls while the frame's work is
  created, encoded, presented and committed MUST be counted separately from the app's own (the
  framework count), so that SC-004's zero applies to the app's code. Every other allocation in the
  counted stretch is the app's.
- **FR-004**: Allocations made on a frame that applied at least one queued event MUST be counted
  separately from those on frames that applied none.
- **FR-005**: The counter MUST also count the frames without an event on which at least one app-side
  allocation was made, so a summary says whether allocations are spread across frames or come from one.

**Reporting**

- **FR-006**: The frame summary MUST report, for the frames since the previous summary: app-side
  allocations on frames without an event, app-side allocations on frames with an event, frames that
  made an app-side allocation, and framework allocations. The new fields MUST follow the existing fields,
  which keep their names, order and meaning. The counts MUST then restart, so each summary covers only
  its own frames. Formatting and writing the summary MUST happen outside the counted stretch.
- **FR-007**: The counts MUST restart whenever the existing measurement restarts (the frame budget is
  relearned, 001), so the summary that follows a restart can be told apart as a start-up summary.

**Cost and builds**

- **FR-008**: Counting MUST NOT itself allocate, lock or use thread-local storage (001 FR-021f). Its work
  MUST be bounded: on any thread other than the counted one, one check and return; on the counted thread,
  at most a fixed number of stack frames compared against a fixed number of address ranges per counted
  allocation; and no work beyond two calls on a frame that allocates nothing. The effect on frame time is
  evidenced by SC-005.
- **FR-009**: The counter MUST be compiled under the same condition as the rest of the instrumentation only and MUST be absent from
  Release builds, confirmed by inspecting the built product as 001 SC-004a does (001 FR-021e).
- **FR-010**: The counter MUST work on both iOS and macOS, simulator and device, with no change to the
  logic or rendering layers (Principle I). It lives with the rest of the instrumentation in the platform
  layer.

**Testability**

- **FR-011**: The counter's behaviour — counting on one thread, ignoring others, keeping the framework
  count apart, restarting — MUST be verifiable by automated tests that need no graphics device and no
  running app, run by the project's single checked-in test command (Principle II).

**Verification and method**

- **FR-012**: The iOS result MUST be recorded in 001's quickstart check 25 — PASS, or the allocation
  found and fixed and then PASS — with the date, the destination, the build, the run length and the
  summary figures.
- **FR-013**: This feature's quickstart MUST describe the method — build, launch arguments, run length,
  the `/usr/bin/log` command that reads the summaries, and the PASS rule — so it can be followed for
  SKY-4 and for the later checks that cite it. 001's check 25 MUST point to it.

### Key Entities

- **Frame allocation counts**: per summary interval, the app-side allocations on frames without an event,
  the app-side allocations on frames with an event, the number of frames without an event that made an
  app-side allocation, and the framework allocations. Restarted after each summary.
- **Counted stretch**: the part of a frame, on the frame loop's thread, in which allocations are counted.
  An allocation in it is the framework's when it is made from inside a call into the graphics framework,
  and the app's otherwise.
- **Frame summary**: the existing log line written every 120 frames, extended with the counts.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In the automated tests, a counted stretch that makes exactly N allocations (N in {0, 1, 10,
  1,000}) on the counted thread reports exactly N; the same allocations made on another thread at the
  same time report 0; allocations inside a marked framework stretch appear only in the framework count.
  Each result holds on 10 consecutive test runs.
- **SC-002**: A Debug build on iOS and on macOS writes frame summary lines that carry the four new
  fields after the existing ones; a Release build contains none of the counter's symbols or strings and
  writes no summary.
- **SC-003**: On the iPhone 17 Pro simulator (iOS 27.0), a 60-second idle run of the optimised instrumented build
  (research R12) with the default launch arguments reports, in every summary after the first, zero app-side allocations on frames
  without an event and zero frames that made an app-side allocation. This is the PASS for 001 check 25
  (001 SC-004), recorded in its quickstart. The Debug build's figures are recorded beside it for
  information.
- **SC-004**: The framework count over the same run is recorded beside the result as allocations per
  frame (lowest and highest summary after the first), so later runs can tell a framework change from an
  app change. It is a reference, not a gate.
- **SC-005**: Optimised instrumented builds (research R12) of `main` (before) and of this branch (after), run idle for 30 seconds
  each on the same simulator, are recorded side by side in the quickstart: the after run's mean frame
  time is within 10% or 0.1 ms of the before run's, whichever is larger, and both report `dropped=0`
  outside launch.
- **SC-006**: The project's single verification command passes, with every existing test still passing
  and the new counter tests running headlessly and deterministically.
- **SC-007**: A developer following only the written method on macOS (SKY-4) gets a summary line and a
  PASS or FAIL decision without opening Instruments.

## Assumptions

- **"Draw path" means the app's code on the frame loop's thread.** 001 SC-004 asks for zero heap
  allocations in the per-frame draw path, and the renderer already records that the graphics framework
  allocates inside its command-buffer and encoder calls, which cannot be avoided while still submitting
  work. The framework's allocations are therefore measured and recorded, not required to be zero.
  The later checks' wording, "zero allocations on our side", reads the same way.
- **Idle run, default arguments.** The run that decides check 25 gives no input and uses the default
  launch arguments, so the ship and the debug overlay are drawn: it exercises 007's and 003's draw work
  as well as 001's. It is evidence those later checks can cite, but it does not by itself record them.
- **Simulator, not device.** Allocations are a property of the code path, not of the GPU, so the
  simulator is accepted for this ticket (decided when the ticket was started). The baseline devices of
  001 were dropped (SKY-1, SKY-2), and the connected iPhone 14P is offline.
- **Start-up allowance.** One-off allocations while pipelines and caches are created are not a per-frame
  cost; the first summary of a run is excluded from the PASS rule.
- **Summary interval unchanged.** Counts are reported on the existing 120-frame summary, not per frame,
  so reporting adds no formatting to ordinary frames.
- **No overlay change.** The counts go to the log only (001 FR-021e); showing them on the debug overlay
  is not needed by anything yet (Principle V).

## Dependencies

- **001-metal-app-shell**: the frame loop, its contract, the instrumentation and its summary line, and
  checks 25 and 27. Merged to `main`.
- **003-debug-overlay, 007-ship-sprite-rendering**: the overlay and ship drawn in the default run.
  Merged to `main`.
- **Unblocks**: SKY-4 (the macOS run), and the allocation halves of 002 #15, 003 #13, 004 #8, 006 #11,
  008 #12 and 010 #10.
