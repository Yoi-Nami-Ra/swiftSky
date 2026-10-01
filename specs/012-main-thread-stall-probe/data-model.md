# Data Model: Main-Thread Stall Probe

All types live in `Sources/SwiftSkyPlatform/`. None is persisted.

## BusyStretchTracker (struct, every build)

Turns run-loop activity into busy stretches (research R1, R3). Main thread only.

| Field | Type | Meaning |
|-------|------|---------|
| `openedAt` | `UInt64?` | Clock (nanoseconds) of the after-waiting that opened the current stretch; `nil` while waiting |

| Operation | Effect |
|-----------|--------|
| `afterWaiting(at:)` | `openedAt = t` (a later after-waiting with no wait in between replaces it — cannot happen in a real run loop, and keeping the later time never over-reports) |
| `beforeWaiting(at:) -> UInt64?` | If open: returns `t − openedAt` (0 if the clock went backwards), clears `openedAt`. If not open: returns `nil` |

## MainThreadStallFigures (struct, every build)

The two figures of one summary interval, packed into one `UInt64` (research R4).

| Field | Bits | Meaning | Summary field |
|-------|------|---------|---------------|
| `worstMicroseconds` | high 40 | Longest busy stretch ended in the interval | `mainworst=` (as ms) |
| `overCount` | low 24 | Busy stretches longer than the interval current when each ended | `mainover=` |

| Operation | Rule |
|-----------|------|
| `init(packed:)`, `packed` | Lossless both ways |
| `recording(stretchNanoseconds:intervalNanoseconds:) -> Self` | `worst = max(worst, stretch/1000)`, saturating at 2⁴⁰−1; `over += 1` if `stretch > interval`, saturating at 2²⁴−1. A stretch exactly equal to the interval is **not** over (SC-016: "longer than") |
| `.zero` | Both 0 |

## MainThreadStallProbe (final class, `Sendable`, instrumented builds only)

Owns the cross-thread state and the observers.

| Field | Type | Written by | Read by |
|-------|------|-----------|---------|
| `figures` | `Atomic<UInt64>` (packed `MainThreadStallFigures`) | main (CAS loop per stretch) | loop (`exchange(0)` at summary / restart) |
| `intervalNanoseconds` | `Atomic<UInt64>` | loop (restart) | main (relaxed load per stretch) |
| `tracker` | `BusyStretchTracker` | main only | main only |
| observers | two `CFRunLoopObserver` | created / removed on main | — |

| Operation | Thread | Effect |
|-----------|--------|--------|
| `install()` | main | Adds both observers to the main run loop's common modes (R2). Idempotent |
| `uninstall()` | main | Removes them |
| `record(stretchNanoseconds:)` | main (tests: any) | Folds one ended stretch into `figures` against the current interval (CAS loop). Called by the before-waiting observer; internal, so tests drive it without observers |
| `take() -> MainThreadStallFigures` | loop | `exchange(0)`: the interval's figures; the next interval starts empty |
| `restart(intervalSeconds:)` | loop | Publishes the interval, then `take()` and discard (R6) |

**Lifecycle**: created by `FrameLoop.init`, installed in `FrameLoop.start()` (main thread), uninstalled in
`stopAndDrain()`. Held by `Instrumentation`, which calls `take()` in `summary()` and `restart` in
`updateBudget`.

## Frame summary (extended)

```text
frames=… skipped=… dropped=… mean=…ms worst=…ms budget=…ms ticks=… allocs=… allocframes=… eventallocs=… gfxallocs=… mainworst=…ms mainover=…
```

## Live-resize markers (macOS, instrumented builds)

`live resize began`, `live resize ended` — same subsystem and category as the summary (FR-013).
