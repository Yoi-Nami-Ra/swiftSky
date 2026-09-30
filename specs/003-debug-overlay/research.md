# Research: Live Debug Overlay

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Date**: 2026-09-30

Decision record for `/speckit-plan`. The Technical Context had no open unknowns: the language,
toolchain, text path and measurement already exist from 001 and 002. What needed deciding is where
each piece lives, how the one-second window and the refresh work without allocating, and how Release
stays clean. Each entry gives the decision, why, and what was rejected.

## R1. Which layer owns what (FR-013, FR-015, Principle I)

**Decision**:

| Piece | Layer | Why there |
|-------|-------|-----------|
| `FrameTimeWindow`: mean and worst over the last second | Platform, beside `Instrumentation` | It consumes the frame time the instrumentation measures, and restarts with the instrumentation's budget (FR-008, FR-013) |
| `OverlayRefreshSchedule`: the 4 Hz schedule | Platform, beside `Instrumentation` | It decides when a snapshot is taken, which is a measurement concern, and it runs on the loop's timestamp (FR-008) |
| `DebugOverlayStatistics`: the snapshot value | Rendering, `Debug/` | The consumer defines the value it consumes, exactly as `RenderSurface` is defined in rendering and filled by the platform layer |
| `DebugOverlay`: writes the six lines into the text buffer | Rendering, `Debug/` | It is presentation, next to 002's `DebugTextPattern` |
| Two-decimal number writing | Rendering, `TextBuffer` | It is a text capability like 002's whole-number writing, so it ships in every build (002 FR-016) |
| Opt-out parsing | Platform, `DebugTextMode` | 002 already parses the debug arguments there |

`Instrumentation` gains a method that, once per due refresh, returns a `DebugOverlayStatistics` built
from its own counters and its `FrameTimeWindow`. `FrameLoop` hands that value to the renderer. The
renderer never reads the loop or the instrumentation (FR-015), and the budget, dropped, skipped and
tick values are the very fields `summary()` logs (FR-013).

**Rejected**:
- **Windowing inside the rendering layer, from raw per-frame frame times.** It would make the
  rendering layer keep measurement state, and the budget reset that FR-008 ties the window to lives in
  the instrumentation. The overlay would have to mirror it.
- **Defining `FrameTimeWindow` in rendering so the existing rendering tests reach it.** A
  measurement type in the wrong layer to save one test target. R9 adds the target instead.

## R2. The one-second window (FR-004, FR-008)

**Decision**: four buckets, one per refresh period, each holding a frame count, a sum and a maximum.
Frames are recorded into the open bucket. At each refresh the open bucket is closed into a fixed
four-slot ring, and a new one opens. Mean and worst are read over the four closed buckets. Until four
have closed since the last restart, they are `nil`, which the overlay writes as `--`.

- Four is derived, not written down twice: `bucketCount = windowSeconds / refreshInterval`, and a test
  pins `bucketCount × refreshInterval == windowSeconds`.
- The ring is an `InlineArray<4, FrameTimeBucket>` inside a struct: stored inline, so no heap
  allocation. It costs O(1) per frame and O(4) per refresh (FR-014). `InlineArray` needs the
  iOS 26 / macOS 26 runtime, which is already this project's floor.
- **Restart triggers**: the surface becoming visible again (the loop already receives
  `.visibilityChanged`), and `updateBudget` (FR-008). Both clear the ring and the open bucket.
- **Not a restart trigger: a long gap between frames.** A first draft copied 002's FPS rule, "a gap
  over 0.25 s restarts". That rule is right for FPS, which measures gaps. It is wrong here: frame time
  is the work done *inside* a frame, and a 300 ms frame is followed by a 300 ms gap, so the rule would
  erase exactly the frame the worst line exists to show. The spec's FR-008 and edge cases were
  corrected during planning to restart on hide/show instead.

**Rejected**:
- **A ring of every frame time in the last second.** Exact, but it needs a buffer sized for the
  fastest plausible display (250 Hz, 001's bound) and a scan per refresh, for a precision a display
  refreshed four times a second cannot show.
- **Mean and worst since the last restart.** Rejected in clarification: a launch hitch would pin the
  worst line for the whole run.

## R3. The refresh schedule (FR-006, SC-002)

**Decision**: a fixed grid of due times, 0.25 s apart, anchored at the first frame after a restart.
The first frame is due immediately, so the overlay is populated on the first drawn frame (SC-001).
When a frame's timestamp reaches the next due time, the snapshot is taken and the due time advances by
one interval. If it is still in the past, the frame was late by more than a whole interval, so the
grid re-anchors at `timestamp + interval` rather than firing a burst of catch-up refreshes.

- The refresh interval is `1.0 / refreshRate` with `refreshRate = 4`, one named constant (FR-006).
- A grid, rather than "`interval` since the last refresh", keeps the long-run rate at exactly four a
  second: at 60 Hz a "since last" rule refreshes on the first frame *after* each 0.25 s mark and
  drifts, which could fall out of SC-002's 38 to 42 over ten seconds.
- It restarts with the window on becoming visible (R2), so the first frame after a hide is due at
  once.

## R4. Getting the snapshot to the renderer (FR-015, FR-013)

**Decision**: in the frame loop, after the clock read and before `render`:

```swift
#if SWIFTSKY_INSTRUMENTATION
if let statistics = instrumentation.overlayStatistics(at: now) {
    renderer.updateDebugOverlay(statistics)
}
#endif
```

`overlayStatistics(at:)` returns a value only on a due refresh. `Renderer.updateDebugOverlay(_:)`
stores it in the renderer's `DebugOverlay`, if there is one. Both are on the loop thread, so nothing
crosses a thread boundary. The value is a plain `Sendable` struct of six numbers.

The snapshot is taken *before* this frame's render, so it describes frames up to the previous one.
That is unavoidable, since a frame's time is known only after it has been drawn, and it is invisible
at 4 Hz.

**Rejected**: **a new `render` parameter.** `render` is the same in every build. An
instrumentation-only argument would need a Release variant or a dummy type there.

## R5. Two-decimal numbers without allocating (FR-007, 002 FR-013)

**Decision**: `TextBuffer.writeHundredths(_ value: Double, width: Int = 0, limit: Int = .max)`.

1. Clamp: a negative or NaN value writes as `0.00`. Anything at or above `Double(UInt64.max) / 100`
   is clamped to that. Frame times are never either, but a formatter must not trap.
2. `hundredths = UInt64((value * 100).rounded(.toNearestOrAwayFromZero))`.
3. Write `hundredths / 100` with the existing whole-number path, then `.`, then `hundredths % 100` with
   `minimumDigits: 2`.
4. `width` left-pads with spaces so the number ends at a fixed column, and a wider number is written
   in full (FR-007).

A width-aware space pad needs the digit count first, which is one loop of divisions on a local
integer. No string is formed. The same `width` logic writes the `--` placeholder right-aligned, so it
lives in a small shared helper.

**Rejected**: `String(format:)` and `Double.formatted()` allocate. A general `fractionDigits:`
parameter is speculative (Principle V): the only caller needs two.

## R6. The overlay's text (FR-004, FR-005)

**Decision**: six lines. The labels are `StaticString`s padded to eight columns, so the values start
in one column. Frame times are right-aligned in a six-column field, which holds `999.99`, followed by
` ms`:

```text
mean      1.23 ms
worst     2.34 ms
budget    8.33 ms
dropped 0
skipped 0
ticks   12345
```

The longest line in the normal range is 17 characters, well inside FR-005's 33. The six lines use at
most about 100 characters of the 1,024, leaving room for SKY-24 and SKY-25's lines. It is placed 8
points in from the safe area's top-left, as 002's pattern is (FR-003), and rewritten into the text
buffer every frame from the last snapshot, as 002 does. That is required anyway: after a
backing-scale change, instances already written are not re-laid-out (002 research R8).

**Rejected**: **writing the buffer only on refresh.** It saves about 100 character writes per frame,
which cost nothing measurable, and it would leave stale pixel positions after a scale change.

## R7. The opt-out, and precedence with 002 (FR-011, FR-012)

**Decision**: `--no-debug-overlay`, parsed by `DebugTextMode`, which gains an `.overlay` case and
makes it the default:

| Arguments | Mode |
|-----------|------|
| none | `.overlay` |
| `--no-debug-overlay` | `.none` |
| `--debug-text` (with or without `--no-debug-overlay`) | `.testString` |
| `--debug-text-fill` (with anything) | `.fill` |

One mode means the renderer holds at most one of the pattern and the overlay, so they cannot both
draw (FR-012). It is a double-dash argument, like 002's, so AppKit's `-Key value` argument domain
never reads it and nothing persists between launches. The Xcode schemes need no change, because the
default is on.

## R8. Absent from Release (FR-009, SC-005)

**Decision**: every new type and member is inside `#if SWIFTSKY_INSTRUMENTATION`: `FrameTimeWindow`,
`OverlayRefreshSchedule`, the new `Instrumentation` members, `DebugOverlayStatistics`, `DebugOverlay`,
`Renderer.debugOverlay` and `updateDebugOverlay`, the `.overlay` case and the argument string, and the
`FrameLoop` call site. The Release `Instrumentation` stub is unchanged. `writeHundredths` and
`writePadded` are the exceptions, deliberately: they are text capability, like 002's
whole-number writer (002 FR-016), and they contain no overlay text.

The Release check extends 001 check 27. After `strip -rSTx`, there are zero symbols matching
`DebugOverlay`, `FrameTimeWindow` or `OverlayRefreshSchedule`, and zero strings matching
`no-debug-overlay`, `dropped ` or `skipped `. The labels are compiled out with the type, so a
`strings` hit would mean the condition leaked.

## R9. Tests (FR-016, SC-007, Principle II)

**Decision**: a new `SwiftSkyPlatformTests` target, depending on `SwiftSkyPlatform` only, with
`@testable import` for the internal types. It covers `FrameTimeWindow` and `OverlayRefreshSchedule`,
and the `Instrumentation` snapshot's agreement with its own counters. The existing
`SwiftSkyRenderingTests` gains decimal-writing tests and `DebugOverlay` composition tests. Both run
under `swift test` in `Scripts/verify.sh`, which is a Debug build, so `SWIFTSKY_INSTRUMENTATION` is
defined for them. The script's headless guard already covers everything under `Tests/`.

The platform tests construct no view, window, layer or `FrameLoop`: only the pure measurement structs.
Linking AppKit is fine, and nothing is instantiated from it.

**Rejected**: **no platform tests, with the logic moved into rendering.** See R1.

## R10. Cost and memory (FR-014, SC-004, Principle III)

- **Per frame**: one `recordPresented` update of the open bucket (three arithmetic operations), one
  due-time comparison, and the overlay's roughly 100 glyph writes. 002 measured 1,024 glyph writes
  per frame inside the budget.
- **Per refresh**: closing a bucket and summing four, plus one 48-byte struct copy.
- **Memory**: under 200 bytes of new state. No texture, buffer or pipeline is added.
- **Allocations**: none on the per-frame path by construction. Every store is a fixed-size value, and
  every write goes through the non-allocating `StaticString` and integer paths. The check is SC-004's
  60-second run, with the overlay on, measured as 002 check 15 was.
- **Measured before and after**: frame time with `--no-debug-overlay` and without it, on the same
  device, recorded in the quickstart (SC-004).

## R11. The log stays unchanged (FR-013)

`summary()`, `reportInterval` and every existing counter are untouched. The window and the schedule
are additions beside them, and `updateBudget` additionally clears the window. The one behavioural
link is deliberate: the log and the overlay restart together on a budget change, so they never
disagree about which frames they describe.
