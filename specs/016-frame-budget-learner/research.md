# Research: Frame Budget That Does Not Lock Onto Stray Gaps

## R1 — Consecutive confirmation

- **Decision**: A candidate is confirmed only by the very next plausible gap (within 5%). Any other
  plausible gap clears it; one that is itself shorter than the budget becomes the new candidate.
  Implausible gaps (outside 20–250 Hz, or below the floor) are skipped entirely.
- **Rationale**: Today's candidate survives every gap that is not shorter than the budget, so two stray
  gaps minutes apart confirm each other (the 14.84 ms lock on the loaded simulator). Requiring adjacency
  turns "two stray gaps anywhere in the run" into "two adjacent agreeing stray gaps", which jitter rarely
  produces; a real display produces adjacent equal gaps all the time.
- **Alternatives**: N agreeing gaps in a row (N > 2) — slower to learn, not needed for the done-when
  series; a median over a window — needs storage and still accepts a sustained burst (live resize).

## R2 — Floor at the display's fastest interval, no settling period

- **Decision**: The floor is `1 / maximumFramesPerSecond` of the screen the view is on (no floor beyond
  the 250 Hz plausible bound when the rate is unknown or 0). A gap below `floor × 0.95` is not plausible;
  an adopted interval is `max(min(candidate, gap), floor)`.
- **Rationale**: Covers both observed sustained bursts: 4.17 ms gaps during a live resize on a 120 Hz
  display (floor 8.33 ms) and 8.33 ms gaps after moving to a 60 Hz display (floor 16.67 ms). A settling
  period would need a duration guessed from logs, a clock, and still fail on a burst after it.
  Clamping keeps a real 120 Hz display at exactly 1/120 even when rounding puts a gap just under it.
- **Alternatives**: settling period after a backing-scale change or resize (rejected above); both
  (YAGNI).

## R3 — How the rate reaches the loop

- **Decision**: New `SurfaceEvent.displayRateChanged(maximumFramesPerSecond: Int)`. `MetalSurfaceView`
  reads `window?.screen.maximumFramesPerSecond` (iOS) / `window?.screen?.maximumFramesPerSecond` (macOS)
  in `surfaceGeometryChanged`, and posts the event **before** the geometry event when it differs from the
  last value it posted.
- **Rationale**: The one ordered queue (008 R1) already guarantees the loop sees the rate before any
  frame after the change; posting before the geometry event means a backing-scale forget runs with the
  new floor already in place. `RenderSurface` is the rendering layer's description of the drawable and
  does not need the rate.
- **Alternatives**: a field on `RenderSurface` (changes a rendering type for a platform concern); an
  atomic written by the main thread (a second channel with its own ordering).

## R4 — Relearning on a slower display

- **Decision**: When a new floor is set and a learned interval is below `floor × 0.95`, the learner
  forgets (budget back to 1/60 s, candidate cleared) and reports the change.
- **Rationale**: Covers a move to a slower display that arrives as a resize rather than a backing-scale
  change. A move with neither (same scale, no resize) is not detected (spec Assumptions).
- **Alternatives**: setting the budget straight to the floor — the floor is the fastest rate, not
  necessarily the running one; relearning is what a backing-scale change already does.

## R5 — Shape of the learner

- **Decision**: `struct DisplayIntervalLearner` (internal), stored `interval: Double` (starts 1/60),
  `isLearned: Bool`, `candidate: Double?`, `floor: Double`. `mutating func observe(gap:) -> Double?`,
  `mutating func forget() -> Double`, `mutating func setMaximumFramesPerSecond(_:) -> Double?`. Returns
  the new budget when it changes (`observe` returns non-nil only if the adopted interval differs from the
  current budget), so `FrameLoop` calls `updateBudget` exactly then. Compiled in every build, as today's
  learner is.
- **Rationale**: Mirrors `FrameTimeWindow`: a value the loop owns, tested directly. Returning the change
  keeps `Instrumentation` out of the learner.
- **"Known" interval**: as today, the first confirmed interval may be longer than 1/60 s (a display
  capped to 30 Hz); once learned, only shorter intervals are considered.

## R6 — Comments and log

- **Decision**: The learner's doc comment states the new rules and withdraws the "whole number of
  intervals / never has a partner" premise (FR-009); `FrameLoop`'s `displayInterval` comment moves with
  it. No new log field: the summary's `budget=` already shows the outcome.
