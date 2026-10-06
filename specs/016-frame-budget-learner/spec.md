# Feature Specification: Frame Budget That Does Not Lock Onto Stray Gaps

**Feature Branch**: `016-frame-budget-learner`

**Created**: 2026-10-07

**Status**: Draft

**Input**: User description: "SKY-47 — Stop the frame budget locking onto stray gaps" (`.tickets/47.yaml`,
part of SKY-22). The frame loop learns the display's frame budget from the gaps between the display
link's target timestamps. A gap shorter than the current budget becomes a candidate, and a later gap
within 5% of it confirms it; the budget becomes the smaller of the two and only ever shrinks until the
backing scale changes. Three wrong budgets were observed on 2026-10-06: on the loaded iPhone 17 Pro
simulator the budget fell from 16.67 ms to 14.84 ms about six minutes into a run; on macOS, after the
window moved from the 120 Hz built-in display to a 60 Hz external one, the budget was relearned at
8.33 ms and never rose; and on a 120 Hz Mac a live resize dropped it to 4.17 ms, so a 5.13 ms frame
counted as dropped. Causes: the candidate never expires, the method assumes every gap is a whole number
of display intervals, and the budget never rises. Scope: accept a candidate only when the very next
plausible gap agrees with it; move the learner into a small, pure, allocation-free, headlessly tested
part of the platform layer; learn only gaps the display can really produce; update the comments that
state the old premise. Out of scope: how dropped frames are defined or counted, and the main-thread
stall at the end of live resize (SKY-37). Done when headless tests cover seven named series, the
verification command passes, and a 10-minute Debug run on the loaded iOS simulator keeps
`budget=16.666667ms` in every summary.

## Overview

Debug and Profiling builds judge every frame against a **frame budget**: the display's refresh
interval (001 SC-003: "16.6 ms, or the display's native rate"). A frame over budget counts as
**dropped**; the budget, the dropped count and the worst frame appear in the periodic log summary and on
the debug overlay (003). The budget is not known in advance; it is learned from the spacing of the
display's scheduled presentation times while the app runs, and changing it restarts every counter
(budget, dropped, skipped, worst, allocation and main-thread figures) so each summary belongs to one
budget.

Today the learner can be convinced by two stray short gaps that need not be adjacent, accepts gaps
shorter than any interval the display can produce, and never lets the budget rise again within one
display. One wrong confirmation therefore lasts the rest of the run and quietly changes what "dropped"
means. This feature makes the learned budget trustworthy: it adopts a shorter interval only on evidence
that a real display would produce, and it never goes below the fastest interval the current display can
refresh at.

Only the instrumentation is affected. The simulation clock, the tick rate, drawing and Release builds
are untouched.

### Relationship to earlier specs

- **Corrected**: 001's budget learning (the rationale behind FR-021d / SC-003's "native rate"): the
  premise that every gap is a whole number of display intervals, and that a spurious short gap never has
  a partner, is withdrawn.
- **Unchanged**: what a dropped frame is, how frames are timed and counted, the summary and overlay
  formats (003), the restart of all counters when the budget changes, and the forgetting of the learned
  interval when the surface's backing scale changes.

## Clarifications

### Session 2026-10-07

- Q: How is "learn only gaps the display can really produce" met: a floor at the display's fastest
  interval, a settling period after a backing-scale change or resize, or both? → A: A floor only
  (FR-005); no settling period.
- Q: A plausible gap shorter than the budget that disagrees with the waiting candidate: does it replace
  the candidate or only clear it? → A: It replaces it (FR-001).
- Q: A confirmed interval that lies just below the floor, within the 5% tolerance: is it adopted as
  measured or clamped? → A: Clamped to the floor (FR-003).
- Q: A surface change reports a floor above the current budget (the surface is now on a slower
  display): keep the budget or relearn? → A: Forget and relearn, as on a backing-scale change (FR-004).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers building swiftSky, who read the summaries and the debug
overlay to decide whether a build holds its frame budget. Players see nothing.

### User Story 1 - The budget stays at the display's real interval for a whole run (Priority: P1)

A developer runs a Debug build for many minutes on a loaded machine (the iOS simulator at well under
60 fps on a 60 Hz link). Late frames and catch-up frames come and go. Every summary still reports the
display's real interval, so the dropped count means the same thing from the first summary to the last.

**Why this priority**: A wrong budget silently changes what every later dropped-frame figure means; the
loaded-simulator lock was the first observed failure and invalidates long performance runs.

**Independent Test**: Feed the budget learner recorded-style gap series without a GPU and check the
budget it settles on.

**Acceptance Scenarios**:

1. **Given** a steady series of 8.33 ms gaps, **When** the learner has seen it, **Then** the budget is
   8.33 ms.
2. **Given** a steady 60 Hz series with one doubled (33.3 ms) gap, **When** the learner has seen it,
   **Then** the budget stays 16.67 ms.
3. **Given** a 60 Hz series in which two matching short gaps appear separated by ordinary 16.67 ms gaps,
   **When** the learner has seen it, **Then** the short gap is not adopted and the budget stays 16.67 ms.
4. **Given** a 60 Hz series with simulator-like jitter (a late gap followed by a short catch-up gap,
   repeatedly), **When** the learner has seen it, **Then** the budget stays 16.67 ms.
5. **Given** a run whose first plausible gap is a single short outlier followed by steady 60 Hz gaps,
   **When** the learner has seen it, **Then** the outlier is ignored and the budget is 16.67 ms.

---

### User Story 2 - Moving to another display and resizing do not leave a false budget (Priority: P2)

A developer drags the window from a 120 Hz display to a 60 Hz display, or live-resizes the window on a
120 Hz display. Afterwards the summaries report the interval of the display the window is now on.

**Why this priority**: Both were observed in ordinary macOS sessions, not only under artificial load; a
resize alone was enough.

**Independent Test**: Feed the learner a display change followed by gap series, and a steady series with
a burst of half-interval gaps, without a GPU.

**Acceptance Scenarios**:

1. **Given** the learner has settled on 8.33 ms on a 120 Hz display, **When** the surface moves to a
   60 Hz display and the learner then sees a few 120 Hz gaps followed by steady 60 Hz gaps, **Then** the
   budget ends at 16.67 ms.
2. **Given** a steady 120 Hz series with the budget at 8.33 ms, **When** a burst of 4.17 ms gaps arrives
   (a live resize), **Then** the budget stays 8.33 ms.

---

### User Story 3 - The learner is checked without a device and costs nothing per frame (Priority: P3)

A developer changes the learner and runs the single verification command; the scenarios above run
headlessly, and the frame loop still allocates nothing per frame.

**Why this priority**: The previous learner lived inside the frame loop and could only be observed in a
running app, which is how the defect survived.

**Independent Test**: Run the verification command; run the existing per-frame allocation check.

**Acceptance Scenarios**:

1. **Given** the repository, **When** the verification command runs, **Then** the learner's tests run
   without creating a GPU device and pass.
2. **Given** an optimised instrumented build, **When** the allocation summary is read, **Then** the
   learner adds no per-frame allocation.

### Edge Cases

- **First frame, paused-then-resumed loop, stalled display**: gaps outside the plausible range (faster
  than 250 Hz or slower than 20 Hz) teach nothing and do not clear or confirm a candidate.
- **Gap equal to or longer than the current budget**: it clears any waiting candidate (it is the "very
  next plausible gap" and does not agree) and leaves the budget unchanged.
- **Gap that agrees with the current budget's display but is slightly under its floor through rounding**
  (e.g. 8.3332 ms on a 120 Hz display): treated as at the floor, within the same 5% tolerance, so a real
  120 Hz display still settles on its interval.
- **Surface reported on a slower display without a backing-scale change** (a resize after the move): the
  new floor is above the budget, so the budget is forgotten and relearned (FR-004).
- **Display's fastest rate unknown** (no screen yet, or the platform reports none): no floor beyond the
  plausible range; the consecutive-agreement rule still applies.
- **Low Power Mode or a capped variable-refresh display**: the floor is the display's fastest rate, not
  its current one; a display capped to 60 Hz simply never produces the shorter gaps. A budget already
  learned at the faster rate does not rise on its own within one display (unchanged behaviour; see
  Assumptions).
- **Two genuine jitter gaps that agree and are adjacent on a variable-refresh display**: still adopted if
  they are at or above the display's fastest interval. This residual risk is accepted (see Assumptions).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The budget learner MUST keep at most one candidate interval, and a candidate MUST be
  confirmed only by the **very next** plausible gap. Any plausible gap that does not agree with the
  candidate (within 5%) MUST clear it, including a gap equal to or longer than the current budget.
  A plausible gap that does not agree but is itself shorter than the budget MUST become the new
  candidate.
- **FR-002**: Gaps outside the plausible range (shorter than 1/250 s or longer than 1/20 s) MUST be
  ignored: they neither confirm, clear nor become a candidate.
- **FR-003**: On confirmation, the budget MUST become the smaller of the candidate and the confirming
  gap, but never less than the floor of FR-005, and the frame loop MUST restart its counters exactly as
  it does today on a budget change. A confirmation that does not change the budget MUST NOT restart them.
- **FR-004**: Within one display, the learned budget MUST only shrink, as today; it is forgotten (reset
  to 1/60 s with the candidate cleared) when the surface's backing scale changes, as today, and also
  when a surface change reports a floor (FR-005) longer than the current budget.
- **FR-005**: The learner MUST NOT adopt an interval shorter than the current display's fastest refresh
  interval (1 / its maximum frames per second), allowing the same 5% tolerance. A gap below that floor
  MUST be treated as not plausible for learning (FR-002 behaviour). The floor MUST follow the display the
  surface is on, updated whenever the platform reports a surface change (resize or backing-scale
  change), before any gap from the new display is learned.
- **FR-006**: The learner MUST be a small, pure value in the platform layer, with no dependency on the
  GPU, the display link or the screen, so that its behaviour is tested headlessly; the frame loop MUST
  call it once per frame with the gap and apply the budget it reports.
- **FR-007**: The learner MUST NOT allocate memory on the per-frame path, and the frame loop's per-frame
  allocation count (011 check 25) MUST stay at zero.
- **FR-008**: Headless tests MUST cover, at least: a steady 120 Hz series settles on 8.33 ms; a 60 Hz
  series with one doubled gap stays at 16.67 ms; two matching short gaps separated by normal ones are not
  adopted; simulator-like jitter (a late gap followed by a catch-up gap) does not lower the budget; a
  single startup outlier is ignored; after a display change, a few 120 Hz gaps followed by steady 60 Hz
  gaps end on 16.67 ms; on a steady 120 Hz series, a burst of 4.17 ms gaps does not lower the budget.
- **FR-009**: Code comments that state the old premise (every gap is a whole number of intervals; a
  spurious gap never has a partner) MUST be replaced by the rules above.
- **FR-010**: Release builds MUST behave as today: no budget learning and no instrumentation output.

### Key Entities

- **Gap**: the time between two consecutive scheduled presentation timestamps, in seconds.
- **Budget (learned interval)**: the display interval every frame is judged against; starts at 1/60 s.
- **Candidate**: a shorter gap waiting for the very next plausible gap to agree with it.
- **Floor**: the current display's fastest refresh interval; the budget never goes below it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: All seven gap series of FR-008 end on the expected budget, in headless tests run by the
  single verification command, which passes.
- **SC-002**: A 10-minute Debug run on the iOS simulator under load reports `budget=16.666667ms` in
  every summary.
- **SC-003**: On a 120 Hz Mac, a live resize leaves the budget at the display's interval in every
  following summary, and after moving the window to a 60 Hz display every following summary reports
  that display's interval.
- **SC-004**: The per-frame allocation count stays at zero (011 check 25) with the new learner.

## Assumptions

- The display's maximum frames per second is available from the platform for the screen the surface is
  on, on both iOS and macOS, and a move to another display is reported to the frame loop as a surface
  change (on macOS today: a backing-scale change, as observed in the 2026-10-06 run). A move between two
  displays with the same backing scale and no resize is not newly detected by this feature.
- Letting the budget rise again within one display (for example after Low Power Mode caps the rate) is
  not required by the ticket's done-when and is left out (YAGNI); the floor and the consecutive rule
  remove the observed false locks.
- Adjacent agreeing jitter gaps at or above the floor on a variable-refresh display remain possible but
  are far rarer than non-adjacent ones; this residual risk is accepted.
- The 5% agreement tolerance and the 20–250 Hz plausible range stay as they are.

## Dependencies

- 001 (frame loop, instrumentation, SC-003), 003 (budget line on the overlay), 011 (allocation counter,
  check 25), 012 (counters restarted with the budget).
