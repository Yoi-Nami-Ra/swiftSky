# Research: Main-Thread Stall Probe

Decision record for `specs/012-main-thread-stall-probe`. Apple silicon Mac (M1 Pro), macOS 26.7,
Xcode 27.0, 120 Hz built-in display.

## R1 — What a "busy stretch" is, and how it is seen

**Decision**: Two `CFRunLoopObserver`s on the main run loop. One fires on `kCFRunLoopAfterWaiting` (the
thread woke for work) with the lowest order, so it runs before anything else in that pass; the other on
`kCFRunLoopBeforeWaiting` (the thread is about to sleep) with the highest order, so it runs after
everything else. A busy stretch is the time from an after-waiting to the next before-waiting.

**Rationale**: The run loop's own wait is the definition of "idle": a main thread that is in it can take
the next event at once, and one that is not cannot. Measuring between those two points measures exactly
what FR-001 and FR-003 ask for, and costs two clock reads per pass. It needs no second thread, no
timer, and no change to how events are delivered.

**Alternatives considered**:
- *A watchdog thread pinging the main queue*: measures the latency of one ping, quantised by the ping
  rate, and adds a thread that wakes 120 times a second. More work, less exact.
- *A main-queue timer measuring its own lateness*: does not fire during live resize unless added to the
  tracking mode, and measures timer slack, not busy time.
- *`xctrace` Hangs*: reports only hangs of 250 ms or more (the ticket's analysis, option A).
- *The frame loop's statistics*: measured on the loop thread, which is unaffected by a busy main thread.

## R2 — Live resize and menus: common modes

**Decision**: Add both observers to `CFRunLoopMode.commonModes`.

**Rationale**: During a live resize AppKit runs a nested run loop in `NSEventTrackingRunLoopMode`, and a
menu does the same; modal panels use `NSModalPanelRunLoopMode`. On macOS all three are members of the
common modes, so an observer added there fires in all of them (FR-002). The nested loop's waits end and
start busy stretches like the outer loop's, so a drag reads as many short stretches, not one long one.

**Fails safe**: if a mode were missed, its nested loop's waits would be invisible and the whole drag would
read as **one** stretch from the outer after-waiting to the outer before-waiting — about 10 seconds, a
loud FAIL, never a silent pass. Quickstart check 2 confirms the drag reads as many short stretches.

## R3 — Nested run loops

**Decision**: The tracker keeps one start time. After-waiting sets it; before-waiting ends the stretch if
one is open and clears it. Entry and exit of a nested run loop are not observed.

**Rationale**: A nested loop starts while the outer pass is busy. Its first before-waiting is the moment
the main thread really waits, so it correctly ends the stretch the outer after-waiting began. When the
nested loop exits, the outer pass resumes busy work with no wait in between; the stretch started by the
nested loop's last after-waiting runs on until the outer before-waiting, which is exactly the busy time.
A before-waiting with no open stretch (the first pass after install) records nothing.

## R4 — Handing the figures across threads: one packed atomic

**Decision**: The main thread folds each stretch into one `Atomic<UInt64>` from the Synchronization
module, packing the worst stretch in microseconds (high 40 bits) and the count over the interval (low 24
bits), with a compare-and-exchange loop. The frame loop takes both with a single `exchange(0)` when it
writes the summary, and on a restart. The interval is published by the frame loop in a second
`Atomic<UInt64>` (nanoseconds), read by the main thread with a relaxed load at the end of each stretch.

**Rationale**: One word means one summary always gets a worst and a count that belong together; two
separate atomics could put a stretch's worst in one summary and its count in the next. Atomics are
lock-free, never block either thread (FR-007), allocate nothing, and are race-free by construction, so
the Thread Sanitizer run cannot report the probe itself (FR-004). 40 bits of microseconds is 12 days and
24 bits of count is 16.7 million per summary, both far beyond a summary's few seconds. A value that would
overflow saturates.

**Alternatives considered**: the existing `Mutex` (as `pendingEvents`): a lock the main thread could
contend on, against FR-007's "MUST NOT lock". Two atomics: the split above.

## R5 — Where the stretch ends up: FR-005 for free

A stretch is folded in only when it ends. A stretch still running when the summary is taken lands in the
next summary, whole. No extra state.

## R6 — Restart with the budget

**Decision**: `Instrumentation.updateBudget(seconds:)` already restarts every figure when the frame budget
is relearned (001). It now also publishes the new interval to the probe and takes (discards) its figures
(FR-006). A stretch that ends after the restart is judged against the new interval (spec edge case).

## R7 — The live-resize markers

**Decision**: `MetalSurfaceView` (macOS) overrides `viewWillStartLiveResize` and `viewDidEndLiveResize`
and, in builds with the instrumentation, writes `live resize began` and `live resize ended` with
`Logger(subsystem: "com.swiftsky.app", category: "frame")` at `notice` level (FR-013). Both run on the
main thread, once per drag.

**Rationale**: the view already receives every size change; AppKit brackets a drag with these two calls.
Logging from the main thread is safe (`Logger` is thread-safe) and happens twice per drag, never per
frame.

## R8 — A deliberate stall, for SC-002

**Decision**: a launch argument, `--debug-main-stall`, in builds with the instrumentation: 5 seconds
after launch, a one-shot main-queue block spins for 50 ms (a busy loop on the clock, not a sleep, so the
run loop does not wait).

**Rationale**: SC-002 needs a known stall in a real app to show the probe sees one. A sleep would also
work (the thread is not in the run loop's wait), but a spin is unambiguous. It follows the existing
`--debug-*` arguments: parsed once at setup, absent from Release.

## R9 — Field names and position

**Decision**: `mainworst=<ms>ms mainover=<n>` at the end of the summary line, after `gfxallocs=` (or after
`allocs=unavailable` when the allocation counter is not ready). Milliseconds with the same formatting as
`worst=`. Existing fields keep their names, order and meaning (FR-004).

## R10 — Tests

**Decision**: the stretch tracker (R1, R3) and the packed figures (R4) are plain types compiled in every
build, like `FrameAllocationCounts`, and tested headlessly in `SwiftSkyPlatformTests`: sequences of
after/before-waiting with given timestamps; nesting; a before-waiting with no open stretch; the worst and
the count; an interval change between stretches; saturation. The probe's `record`, `take` and
`restart` are tested too, driven directly without installing the observers (a stretch recorded after a
take lands in the next one; a restart discards and switches the interval). The observers
themselves need a run loop and are covered by quickstart checks 1–3, as 011 covered its install.

## R11 — iOS

The observers and the tracker are platform-neutral, so the probe runs on iOS too with no separate path
(FR-009's MAY). The live-resize markers are macOS only: iOS has no live resize.
