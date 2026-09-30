# Feature Specification: Live Debug Overlay

**Feature Branch**: `003-debug-overlay`

**Created**: 2026-09-30

**Status**: Draft

**Input**: User description: "SKY-29 — Add the live debug overlay. A debug overlay in the top-left corner (inside the safe area on iOS), compiled into Debug and Profiling builds only and provably absent from Release, like the 001 instrumentation (FR-021e, SC-004a). Drawn with the Metal text renderer (SKY-28). Spec 002 has to relax FR-021e's 'never on the rendered surface' for this overlay in those builds only — see SKY-22. Shows, refreshed a few times per second so it stays readable: frame stats already collected by Instrumentation (mean and worst frame time, budget, dropped and skipped frames, tick count); the ship (once SKY-24 lands): position, velocity, speed, heading, angular velocity; the active order (once SKY-25 lands): autopilot phase, destination, distance remaining. Frame stats can ship first; the ship and order lines follow as their tickets land. Done when the overlay shows live values on both platforms in Debug, is absent from a Release build (symbol check as in check 27), and adds no per-frame allocation. Default refresh rate: 4 Hz."

## Overview

swiftSky already measures every frame: how long it took, whether it missed its deadline, whether it
was skipped for want of a drawable, and how far the simulation has advanced (001 FR-021d). Today
those numbers only reach the log, a few lines every couple of seconds, which a developer has to go
and read in a separate tool. Spec 002 made it possible for the game to draw its own text.

This feature puts those numbers on screen while the game runs. A small block of text in the
top-left corner of the surface shows the live frame statistics in every Debug and Profiling build,
refreshed four times a second so the values can be read rather than flicker. Release builds contain
none of it.

The ticket also lists ship and order lines. The ship (SKY-24) and the autopilot (SKY-25) do not exist
yet, so those lines are out of scope here and are added by follow-up work once their data exists.

Out of scope: the ship and active-order lines (SKY-24, SKY-25), any player-facing heads-up display,
a background panel behind the text, interaction with the overlay (tapping, dragging, toggling at
run time), configurable content, position, size or colour, graphs, and any change to what the log
reports.

### Relationship to earlier specs

- **Superseded, in Debug and Profiling builds only**:
  - 001 FR-021e ("instrumentation … MUST emit to the log — never to the rendered surface") is relaxed
    for this overlay. The instrumentation still emits to the log exactly as before (FR-013).
  - 001 FR-002 ("a uniformly black surface") and 002 FR-015 / SC-006 ("a Debug build launched
    without the opt-in … shows a uniformly black surface") are relaxed: a Debug or Profiling build now
    shows the overlay by default, and shows the uniformly black surface when launched with the
    overlay opt-out (FR-011).
  - 001 FR-012b ("the tick count MUST NOT affect visible output") is relaxed for the overlay's tick
    line only. Nothing else visible may depend on the tick count.
- **Unchanged and still absolute**: in Release builds every one of the rules above holds exactly as
  written. 001 FR-001 and FR-007 (every visible pixel comes from the rendering pipeline; the platform
  layer draws no content), 001 FR-020 / FR-021f / SC-004 (no per-frame allocation), 001 SC-004a (no
  instrumentation in Release), 001 FR-033 (one clock read per frame), 002 FR-016 (the text capability
  ships in Release, unused), and every layer-boundary rule.
- **Reused**: 002's text drawing, its 13-point white monospaced text, its placement convention
  (8 points in from the safe area's top-left corner, 002 FR-006b) and its allocation-free number
  writing, which this feature extends to decimals (FR-007).

## Clarifications

### Session 2026-09-30

- Q: Is the overlay shown by default in Debug and Profiling builds, or only on request? → A: By
  default. A launch opt-out hides it for the whole run, so 001's and 002's black-surface checks can
  still be run on a Debug build (FR-001, FR-011).
- Q: Over what span are the mean and worst frame times taken? → A: The most recent one second of
  drawn frames. Dropped and skipped stay running totals, as in the log (FR-004).
- Q: Does the one-second window restart when the frame budget changes? → A: Yes, as it does when the
  surface is shown again after being hidden, because frames judged against the old display's budget
  do not belong with the new one (FR-008).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers building swiftSky. Players see nothing new: Release
builds are unchanged.

### User Story 1 - Developer reads live frame stats on macOS (Priority: P1)

A developer runs a Debug build on a Mac and, without passing any argument, sees a few lines of text in
the top-left corner of the window: the mean and worst frame time over the last second, the frame
budget, how many frames were dropped and skipped, and the simulation's tick count. The values change
a few times a second as the game runs. When they drag the window to a display with a different
refresh rate, the budget line changes to match it.

**Why this priority**: This is the feature. macOS is where development happens, and frame stats are
the part of the overlay whose data already exists.

**Independent Test**: Launch a Debug build on a Mac with no arguments, watch the overlay for ten
seconds, and compare its values with the instrumentation's log lines from the same run.

**Acceptance Scenarios**:

1. **Given** a Debug build launched with no arguments, **When** the window appears, **Then** the
   overlay is drawn 8 points in from the top-left corner of the safe area and shows every line of
   FR-004 with its label (SC-001).
2. **Given** the overlay is showing, **When** the game runs for ten seconds, **Then** the tick count
   rises steadily, and the displayed values refresh four times a second (FR-006, SC-002).
3. **Given** the overlay is showing, **When** the budget, dropped, skipped and tick values it shows
   are compared with the instrumentation's log line nearest in time, **Then** they agree, allowing
   for the refresh interval (FR-013, SC-003).
4. **Given** the window is moved to a display with a different refresh rate, **When** the frame loop
   has relearned the display's interval, **Then** the budget line shows the new display's interval,
   and the counts restart with it, as the log's do.
5. **Given** the window is resized, **When** it redraws, **Then** the overlay keeps its size in points
   and its position in the top-left corner of the safe area.

---

### User Story 2 - Developer reads live frame stats on iOS (Priority: P2)

A developer runs a Debug build on an iPhone or iPad and sees the same overlay, fully visible inside
the safe area in every orientation, never under the camera cutout or a rounded corner.

**Why this priority**: iOS is a first-class platform, and frame-time problems on a phone are the ones
most worth seeing. It comes second only because the drawing path is shared, so US1 retires most of the
risk.

**Independent Test**: Launch a Debug build on an iOS device or simulator with no arguments, rotate it
through both landscape orientations, and capture a screenshot in each.

**Acceptance Scenarios**:

1. **Given** a Debug build on an iOS device, **When** the app launches, **Then** the overlay shows
   every line of FR-004, updating live.
2. **Given** the device is rotated so the camera cutout is on the left, **When** the surface redraws,
   **Then** the overlay stays fully visible 8 points in from the top-left corner of the safe area.
3. **Given** iPad Slide Over, the narrowest surface the app gets (about 320 points), **When** the
   overlay is drawn, **Then** no line is cut off at the right edge (FR-005).

---

### User Story 3 - The overlay does not disturb what it measures (Priority: P3)

A developer relies on the overlay to judge the frame budget, so the overlay itself must not cost an
allocation per frame or a meaningful share of the frame time. They run a sustained session with the
overlay showing and measure it.

**Why this priority**: An overlay that allocates or eats the budget would corrupt the very numbers it
shows. Checking this needs US1 or US2 first.

**Independent Test**: Run the allocation check used by SKY-3, SKY-4 and 002 SC-003 for 60 seconds with
the overlay showing. Measure frame time with the overlay hidden (opt-out) and showing, on the same
device.

**Acceptance Scenarios**:

1. **Given** the overlay is showing, **When** allocations on the per-frame path are measured over a
   sustained 60-second run, **Then** there are zero, including on the frames where the values refresh.
2. **Given** the same device, **When** frame time is measured with the overlay hidden and showing,
   **Then** both stay within the frame budget, and the difference is recorded as the before/after
   evidence Principle III requires.

---

### User Story 4 - Release builds contain no overlay (Priority: P4)

A developer building for release confirms that the shipped product contains no trace of the overlay:
nothing is drawn, and inspecting the built product finds none of its code or text.

**Why this priority**: This is a gate rather than a feature, and it can only be checked once the
overlay exists.

**Independent Test**: Build Release, launch it with and without the overlay opt-out, and inspect the
built product's symbols and strings as 001 check 27 does.

**Acceptance Scenarios**:

1. **Given** a Release build, **When** it launches, with or without any debug argument, **Then** the
   surface is uniformly black (001 FR-002).
2. **Given** a Release build, **When** its symbols and strings are inspected, **Then** none of the
   overlay's code, labels or format text is present (SC-005).

---

### User Story 5 - Developer verifies overlay formatting without a GPU (Priority: P5)

A developer changes how the overlay formats a value or lays out its lines, and checks the change by
running the project's single test command, with no graphics device and no running app.

**Why this priority**: Decimal formatting, the refresh timing and the one-second window are real
logic with edge cases, and the constitution requires tests for them (Principle II). Nothing visible
depends on this story, so it comes last.

**Independent Test**: Run the checked-in test command headlessly and confirm the overlay's tests run
and pass.

**Acceptance Scenarios**:

1. **Given** frame times such as 0, 0.004 ms, 8.333 ms, 16.667 ms and 1,234.5 ms, **When** they are
   formatted, **Then** the tests confirm the written text for each, including rounding (FR-007).
2. **Given** a sequence of frame timestamps, **When** the refresh timing is driven by them, **Then**
   the tests confirm that the displayed values change at most four times a second, and that a long
   gap between frames neither bursts refreshes nor restarts the window (FR-006, FR-008).
3. **Given** frame times recorded over more than one second, **When** the mean and worst are read,
   **Then** the tests confirm that only the last second's frames contribute (FR-004).

### Edge Cases

- **Before the first second has been measured** (launch, or right after the app is shown again or the
  budget changes):
  the mean and worst lines show `--` instead of a number. The counts and the tick count are shown
  from the first frame (FR-004).
- **The app is hidden and shown again** (backgrounded on iOS, minimised on macOS): no frame is drawn
  while hidden (001 FR-008). On return, the one-second window starts again, so frames from before
  the pause are not reported as the last second's (FR-008).
- **The budget changes mid-run** (window moved to a display with a different refresh rate): the
  instrumentation restarts its counts, as it does today, and the one-second window restarts with
  them (FR-008). The overlay shows the restarted values, not a mix of old and new (FR-013).
- **A very slow frame** (a breakpoint, a hitch of over a second): it is shown as it is, in full,
  never cut short (FR-007), and it stays on the worst line for the next second. The long gap it
  leaves before the next frame does not restart the window (FR-008). A value too wide for its line pushes the line wider rather than being
  truncated.
- **Counts grow large over a long session**: the dropped, skipped and tick counts are written in
  full up to the largest 64-bit value. The layout does not depend on their width.
- **Text renderer unavailable** (002 FR-018: character images could not be prepared): the overlay is
  simply not drawn. The app keeps running, and the log still carries the measurements.
- **002's test-string opt-ins are given** (`--debug-text`, `--debug-text-fill`): the test string is
  drawn instead of the overlay, never both, because both use the same corner and the fill opt-in
  needs the whole text capacity (FR-012).
- **The overlay opt-out is given together with a 002 opt-in**: the 002 test string is drawn, and the
  overlay is not.
- **Zero-area surface**: nothing is drawn, as for every frame (001 FR-008, FR-027a).
- **Skipped frames**: a frame skipped for want of a drawable is not drawn, so it cannot show itself.
  It is counted, and the next drawn frame shows the updated count at the next refresh.

## Requirements *(mandatory)*

### Functional Requirements

**Where and when it appears**

- **FR-001**: In Debug and Profiling builds, the overlay MUST be drawn on every frame the game draws,
  by default, with no launch argument needed.
- **FR-002**: The overlay MUST be drawn by the game's own rendering pipeline, in the same frame as the
  rest of the surface and on top of it, using 002's text drawing. No platform text view, label or
  window may be used (001 FR-001, FR-007).
- **FR-003**: The overlay MUST be placed 8 points in from the top-left corner of the safe area on both
  platforms and in every orientation, at 002's fixed 13-point size and colour (002 FR-006b,
  FR-007). It MUST keep that size and position when the surface is resized or rotated.

**Content**

- **FR-004**: The overlay MUST show the following frame statistics, each on a labelled line, in this
  order:
  1. **Mean frame time**: the mean of the frame times measured over the most recent one second of
     drawn frames, in milliseconds.
  2. **Worst frame time**: the largest frame time in that same one second, in milliseconds.
  3. **Frame budget**: the budget each frame is judged against, in milliseconds. It is the one the
     instrumentation currently uses, which follows the display's refresh interval.
  4. **Dropped frames**: the number of frames that overran the budget, since the instrumentation
     last started counting.
  5. **Skipped frames**: the number of frames not drawn for want of a drawable, over the same span.
  6. **Tick count**: the simulation's tick count as of the most recent refresh.

  "Frame time" means the same per-frame measurement the instrumentation already takes and logs. The
  mean and worst lines read `--` until one full second has been measured.
- **FR-005**: No overlay line may be longer than 33 characters while its numbers stay within the
  normal ranges of this feature (frame times under 1,000 ms, counts under ten million), so the whole
  overlay fits across the narrowest surface the app gets (002 FR-014). Wider numbers are written in
  full and may be clipped at the surface edge.
- **FR-006**: The displayed values MUST refresh four times a second. Between refreshes the overlay
  MUST keep showing the values from the last refresh, drawn every frame. The refresh rate MUST be one
  named value in one place, changed by editing it, not at run time.
- **FR-007**: Frame times MUST be written in milliseconds with exactly two decimal places, rounded to
  the nearest hundredth. Values of 1,000 ms or more are written in full, never cut short, and never
  in exponent notation. Counts are written as whole numbers in full. All of this MUST be written
  without allocating memory (002 FR-013).
- **FR-008**: The refresh timing and the one-second window MUST be driven only by the timestamp the
  frame loop already reads once per frame (001 FR-033), with no second clock read. The one-second
  window MUST start again when the surface is shown after being hidden, so frames from before the
  pause do not linger, and whenever the frame budget changes, so the mean and worst never mix frames
  judged against two different budgets. It MUST NOT restart merely because frames were far apart:
  the gap after a very slow frame would otherwise erase that frame from the worst line.

**Builds, opt-out and the log**

- **FR-009**: The overlay MUST be compiled into Debug and Profiling builds only. A Release build
  MUST contain none of its code, labels or format text, and MUST draw nothing new, with or without
  any launch argument (001 FR-021e, SC-004a).
- **FR-010**: The overlay's content MUST NOT be exposed to assistive technology. It is
  developer-facing debug content, and the surface's accessible description (001 FR-009) is
  unchanged.
- **FR-011**: A launch opt-out, limited to Debug and Profiling builds, MUST hide the overlay for the
  whole run, so that 001's and 002's visible-output checks can still be run on a Debug build and
  find a uniformly black surface. In Release builds it MUST have no effect.
- **FR-012**: When either of 002's test-string opt-ins is given (002 FR-015, FR-015a), the test string
  MUST be drawn and the overlay MUST NOT be, so the test string's checks and its full-capacity
  measurement are unchanged.
- **FR-013**: The instrumentation's log output MUST be unchanged: the same lines, at the same
  interval, with the same values. The overlay's budget, dropped, skipped and tick values MUST come
  from the same measurement that feeds the log, so the screen and the log cannot disagree about
  them.

**Cost**

- **FR-014**: Showing the overlay, including refreshing its values, MUST NOT allocate memory on the
  per-frame path (001 FR-020, FR-021f).
- **FR-015**: The overlay's statistics MUST be kept by the layer that measures them and handed to the
  rendering layer as plain values, one frame at a time. The rendering layer MUST NOT reach into the
  frame loop or the platform layer to read them (Principle I, 001 FR-012).

**Testability**

- **FR-016**: The overlay's number formatting, refresh timing, one-second window and line
  composition MUST be verifiable by automated tests that need no graphics device and are run by the
  project's single checked-in test command (Principle II).

### Key Entities

- **Frame statistics**: the values the overlay shows (FR-004): mean and worst frame time over the last
  second, budget, dropped and skipped counts, and tick count. Kept by the measuring layer and handed
  to the renderer as a plain value.
- **One-second window**: the frame times of the most recent second of drawn frames, summarised as a
  mean and a maximum. Restarts when the surface is shown again after being hidden, or the budget
  changes.
- **Refresh schedule**: when the displayed values next change, derived from the per-frame timestamp at
  four times a second.
- **Overlay text**: the labelled lines, rewritten from the latest refreshed statistics and placed at
  the safe-area anchor, within 002's text capacity.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On macOS and on iOS, a Debug build launched with no arguments shows all six labelled
  lines from FR-004 from its first visible frame, with numbers on every line within one second of it
  (mean and worst read `--` until then), fully inside the safe area in
  every orientation, confirmed by screenshots on each platform.
- **SC-002**: Over a 10-second observation with the app visible, the overlay refreshes at least 38
  and at most 42 times (four a second, allowing for frame-interval rounding), confirmed by the tick
  count shown, which increases at every refresh and at no other time.
- **SC-003**: At any moment, the budget, dropped, skipped and tick values on screen match the
  instrumentation's log line nearest in time, allowing for the refresh interval (FR-013).
- **SC-004**: With the overlay showing, zero heap allocations occur on the per-frame path over a
  sustained 60-second run on each platform, measured with the same check as SKY-3, SKY-4 and 002
  SC-003. Mean and worst frame time with the overlay showing stay within the frame budget, and are
  recorded next to the same measurement with the overlay hidden, on the same device.
- **SC-005**: A Release build contains no overlay symbols, labels or format strings, confirmed by
  inspecting the built product as 001 check 27 does, and shows a uniformly black surface on both
  platforms with and without any debug launch argument.
- **SC-006**: A Debug build launched with the overlay opt-out shows a uniformly black surface and
  passes 001's visible-output checks unchanged. A Debug build launched with a 002 test-string opt-in
  passes 002's checks unchanged.
- **SC-007**: The overlay's formatting, refresh and window tests pass headlessly and
  deterministically on 10 consecutive runs of the single test command, with no graphics device
  available.

## Assumptions

- **Default on**: the ticket and SKY-22 describe the overlay as present in debug builds with no
  mention of an opt-in, so it is on by default and the opt-out exists only to keep the black-surface
  checks runnable (FR-011). The argument is `--no-debug-overlay`, in the style of 002's `--debug-text`
  (plan research R7).
- **Window versus totals**: mean and worst are over the last second, because a live display is for
  judging the present; a launch-time hitch should not pin the worst line for the rest of the run.
  Dropped and skipped are running totals, as in the log, because a single dropped frame is worth
  seeing after the fact.
- **Frame time**: the overlay shows the same per-frame measurement the instrumentation logs today.
  Its drawing happens inside that measurement, so the overlay's own cost is included in what it
  shows. GPU time is not measured, as in 001.
- **No FPS line**: the ticket's list does not include one. 002's test string still shows FPS, and
  the budget line already reveals the display's refresh rate.
- **No backdrop**: the surface is black today, so white text is readable without a panel behind it.
  When world content arrives (SKY-23, SKY-27), readability over it is revisited then (Principle V).
- **No Dynamic Type**: as in 002, Principle IV's Dynamic Type and VoiceOver requirements cover
  player-facing UI. The overlay is developer-only.
- **Ship and order lines**: added by follow-up work once SKY-24 and SKY-25 exist. The overlay's
  frame-stat lines use about 100 of 002's 1,024 characters, which leaves ample room for them.
- **Test devices**: as in 002, frame-time evidence uses whichever device 001's performance checks
  use, since the formal baseline devices are still being acquired (SKY-31, SKY-32).

## Dependencies

- **002-metal-text-rendering (SKY-28)**: the text drawing, placement convention and allocation-free
  number writing this feature builds on. Merged to `main`.
- **001-metal-app-shell**: the frame loop, the instrumentation whose values the overlay shows, and the
  Release symbol check (check 27) this feature reuses. Merged to `main`.
- **SKY-3 and SKY-4**: the method for measuring per-frame allocations, reused by SC-004.
- **SKY-24 and SKY-25**: not required. They unblock the ship and order lines, which are out of scope
  here.
