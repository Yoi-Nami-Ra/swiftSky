# Data Model: Count Draw-Path Allocations and Verify Zero on iOS

All of it exists only when `SWIFTSKY_INSTRUMENTATION` is defined (Debug builds; see research R1 on
Profiling). Nothing here is part of the simulation state or crosses into the rendering layer.

## C side — `SwiftSkyAllocationCounter`

Process-wide state, private to `AllocationCounter.c`. Written as described; never allocated.

| Field | Type | Written by | Meaning |
|-------|------|-----------|---------|
| `installed` | atomic bool | install / uninstall (loop thread) | The callback is in `malloc_logger`. |
| `previousLogger` | function pointer | install | The logger that was there before, called first from ours (R7). |
| `graphicsRanges` | up to 32 `[start, end)` address pairs, plus a count | install, before publishing | `__TEXT` of each graphics image (R4). Read-only once installed. |
| `countedThread` | atomic `pthread_t` | `frame_begin` | The thread whose allocations count (R3). |
| `counting` | atomic bool | `frame_begin` / `frame_end` | A stretch is open. |
| `stackLimit` | address | `frame_begin` | The frame of `frame_begin`'s caller; the walk stops there (R4). |
| `appCount`, `graphicsCount` | `uint64_t` | the callback, on `countedThread` only | This stretch's counts; zeroed by `frame_begin`. |

**Rules**
- The callback ignores every event without the allocate bit (`0x2`), and every event while `counting`
  is false or on another thread.
- Exactly one of `appCount` and `graphicsCount` goes up per counted allocation.
- A stretch is opened and closed on the same thread; stretches do not nest.

**Result of a stretch** — `SkyFrameAllocations { uint64_t app; uint64_t graphics; }`, returned by
`frame_end`.

## Swift side — `FrameAllocationCounts` (platform layer)

A plain struct held by `Instrumentation`, one per summary interval.

| Field | Type | Meaning (summary key) |
|-------|------|----------------------|
| `appAllocations` | `UInt64` | App-side allocations on frames that applied no event (`allocs=`). |
| `eventAppAllocations` | `UInt64` | App-side allocations on frames that applied an event (`eventallocs=`). |
| `allocatingFrames` | `UInt64` | Frames that applied no event and made at least one app-side allocation (`allocframes=`). |
| `graphicsAllocations` | `UInt64` | Graphics framework allocations, all frames (`gfxallocs=`). |

**Operations**
- `record(app:graphics:appliedEvent:)` — adds one frame: `app` to `eventAppAllocations` when
  `appliedEvent`, else to `appAllocations`; `allocatingFrames += 1` when `app > 0` and not `appliedEvent`; `graphics` to
  `graphicsAllocations`.
- `reset()` — all four to zero. Called after each summary and by `updateBudget(seconds:)`.

**Instrumentation additions**
- `allocationCounterReady: Bool` — the self-test's result (R8). When false, the summary writes
  `allocs=unavailable` instead of the four fields.
- `recordFrameAllocations(_:appliedEvent:)` — feeds `FrameAllocationCounts.record`.

## Frame loop

No new state. The counted body moves into a private method returning `(outcome: FrameOutcome,
appliedEvent: Bool)`, where `FrameOutcome` is `notRenderable`, `skipped` or `presented`, so step 6 keeps
today's skip accounting exactly; `applyPendingEvents()` returns whether it applied at least one event.
