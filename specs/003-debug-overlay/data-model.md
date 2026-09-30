# Data Model: Live Debug Overlay

**Feature**: [spec.md](./spec.md) | **Research**: [research.md](./research.md)

Every entity below except the decimal writer exists only in Debug and Profiling builds, behind
`#if SWIFTSKY_INSTRUMENTATION` (FR-009, research R8). All are fixed-size values or single long-lived
objects. None allocates after it is created.

## FrameTimeBucket *(new, platform layer, value type)*

One refresh period's worth of frame times.

| Field | Type | Meaning |
|-------|------|---------|
| `frames` | `UInt32` | Frames recorded in the period |
| `totalSeconds` | `Double` | Sum of their frame times |
| `worstSeconds` | `Double` | Largest of them, `0` when empty |

## FrameTimeWindow *(new, platform layer, value type)*

The last second of frame times, as four closed buckets plus an open one (research R2).

| Field | Type | Meaning |
|-------|------|---------|
| `open` | `FrameTimeBucket` | The period being recorded now |
| `closed` | `InlineArray<4, FrameTimeBucket>` | The last four closed periods, a ring |
| `next` | `Int` | Ring slot the next closed bucket goes into |
| `closedCount` | `Int` | Closed buckets since the last restart, capped at 4 |

| Operation | Effect |
|-----------|--------|
| `record(frameSeconds:)` | Adds one frame to `open` |
| `closeBucket()` | Moves `open` into `closed[next]`, advances `next`, starts an empty `open` |
| `restart()` | Empties `open` and every closed slot, and sets `closedCount = 0` |
| `mean` | `nil` while `closedCount < 4`. Otherwise the sum of the closed totals divided by the sum of the closed frame counts. `nil` also when that count is 0, because no frame was drawn |
| `worst` | `nil` while `closedCount < 4`, otherwise the largest closed `worstSeconds` |

**Invariants**: `bucketCount (4) × OverlayRefreshSchedule.interval == windowSeconds (1.0)`, which is
pinned by a test. `closedCount ≤ 4`.

## OverlayRefreshSchedule *(new, platform layer, value type)*

The 4 Hz grid of refresh times (research R3).

| Field | Type | Meaning |
|-------|------|---------|
| `nextDue` | `Double?` | Timestamp of the next refresh. `nil` means the next frame is due at once |

| Constant | Value |
|----------|-------|
| `refreshRate` | `4` refreshes per second (FR-006) |
| `interval` | `1.0 / refreshRate` = 0.25 s |

| Operation | Effect |
|-----------|--------|
| `isDue(at: t) -> Bool` | If `nextDue` is `nil`: set it to `t + interval` and return `true`. If `t < nextDue`: return `false`. Otherwise advance `nextDue` by `interval`, and if it is still `≤ t`, re-anchor it at `t + interval`. Return `true` |
| `restart()` | `nextDue = nil` |

## Instrumentation *(extended, platform layer)*

Adds, in the `SWIFTSKY_INSTRUMENTATION` branch only:

| Member | Meaning |
|--------|---------|
| `window: FrameTimeWindow` | Fed by `recordPresented`, cleared by `updateBudget` |
| `schedule: OverlayRefreshSchedule` | When the next snapshot is due |
| `overlayStatistics(at: timestamp) -> DebugOverlayStatistics?` | On a due refresh, closes a window bucket and returns a snapshot. Otherwise `nil`. The anchoring refresh (the first after a restart) closes no bucket, so the first value needs four full periods |
| `restartOverlayWindow()` | Called when the surface becomes visible, and by `updateBudget`: restarts the window and the schedule |

`recordPresented` also calls `window.record(frameSeconds:)`. `updateBudget` also calls
`restartOverlayWindow()`. `summary()` and every existing counter are unchanged (FR-013, research R11). The
Release stub is unchanged.

## DebugOverlayStatistics *(new, rendering layer, `Sendable` value type)*

The snapshot handed to the renderer at each refresh (FR-004, FR-015).

| Field | Type | Source |
|-------|------|--------|
| `meanFrameSeconds` | `Double?` | `window.mean`, `nil` until a full second has been measured |
| `worstFrameSeconds` | `Double?` | `window.worst` |
| `budgetSeconds` | `Double` | `Instrumentation.budgetSeconds` |
| `droppedFrames` | `UInt64` | `Instrumentation.droppedFrames` |
| `skippedFrames` | `UInt64` | `Instrumentation.skippedFrames` |
| `tickCount` | `UInt64` | `Instrumentation.lastTickCount` |

Seconds throughout, as the instrumentation stores them. `DebugOverlay` converts to milliseconds when
it writes them.

## DebugOverlay *(new, rendering layer, `final class`)*

Owned by `Renderer` when the mode is `.overlay`.

| Member | Meaning |
|--------|---------|
| `statistics: DebugOverlayStatistics?` | The last snapshot. `nil` before the first one arrives, in which case nothing is drawn |
| `write(into: TextBuffer, surface: RenderSurface)` | Writes nothing when `statistics` is `nil`. Otherwise `begin` 8 points in from the safe area's top-left, then the six lines of research R6. Called every frame, after the renderer has cleared the buffer, exactly as 002's `DebugTextPattern.write` is |

**Invariants**: in the normal range (frame times under 1,000 ms, counts under 10⁷), each line is at
most 33 characters and the whole overlay is under 128 characters (FR-005). Never overflows the
buffer.

## TextBuffer *(extended, rendering layer, all builds)*

| Member | Meaning |
|--------|---------|
| `writeHundredths(_ value: Double, width: Int = 0, limit: Int = .max)` | Writes `value` rounded to two decimal places, left-padded with spaces to `width`, and never cut short. Negative and NaN write as `0.00`, and huge values are clamped (research R5). Allocation-free |
| `writePadded(_ text: StaticString, width: Int, limit: Int = .max)` | Writes a literal right-aligned in `width` columns: the `--` placeholder |

## DebugTextMode *(extended, platform layer)*

| Case | Selected by | Renderer gets |
|------|-------------|---------------|
| `.overlay` | no debug argument (the default) | `debugOverlay = DebugOverlay()` |
| `.none` | `--no-debug-overlay` | nothing, so the surface is black |
| `.testString` | `--debug-text` | `debugTextPattern` (002) |
| `.fill` | `--debug-text-fill` | `debugTextPattern` (002) |

Precedence: `.fill` > `.testString` > `.none` > `.overlay` (research R7).

## Relationships

```text
FrameLoop (platform, loop thread)
  ├─ instrumentation.recordPresented(frameSeconds:tickCount:) ──▶ window.record
  ├─ .visibilityChanged(true) ──▶ instrumentation.restartOverlayWindow()
  └─ instrumentation.overlayStatistics(at: now) ──(due)──▶ renderer.updateDebugOverlay(stats)
                                                              └─▶ DebugOverlay.statistics
Renderer.prepareText (every frame)
  └─ debugTextPattern?.write(…)  or  debugOverlay?.write(into: textBuffer, surface:)
```
