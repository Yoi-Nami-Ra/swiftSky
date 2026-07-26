# Contract: Frame Loop Lifecycle & Event Marshalling

**Feature**: `001-metal-app-shell` | **Date**: 2026-07-26

Governs FR-020, FR-021, FR-021a–c, FR-027a–c and FR-028–FR-033. This is where the feature's only real
concurrency lives, and where the complexity recorded in the plan's Complexity Tracking table is
confined.

---

## Isolation domains

| Domain | Owns | Must never |
|--------|------|-----------|
| **Main thread** | Window/scene lifecycle, the `CAMetalLayer`'s view, event origination, the FR-024 notice | Block waiting for a frame (FR-029); touch `SimulationState` or `TimeAccumulator` |
| **Loop domain** — one serial `DispatchQueue`, QoS `.userInteractive` (R4) | `SimulationState`, `TimeAccumulator`, the current `RenderSurface`, the `Renderer` | Call back synchronously into main-thread state; read the clock more than once per frame (FR-033) |

Because the queue is serial, the loop's state needs no lock — which is what lets the logic layer stay
free of concurrency constructs entirely (FR-012c).

---

## Per-frame sequence

Invoked by `CAMetalDisplayLink` on the loop's queue (R5). Ordering is normative.

1. **Apply pending events** — drain the event queue and adopt any new `RenderSurface`. This happens
   here and nowhere else, which is what makes FR-031's frame-boundary guarantee hold.
2. **Bail if not renderable** — if the surface has zero width or height, return without drawing.
3. **Read the clock once** — exactly one timestamp per frame (FR-033). No other clock read may occur
   anywhere in the frame.
4. **Advance the simulation** — `ticks = accumulator.consume(elapsed:)`, then
   `state = Simulation.advance(state, ticks: ticks)`. `ticks` may be `0`; the frame still draws
   (FR-021 requires a frame per refresh regardless of change).
5. **Draw** — `renderer.render(state:surface:into:)`. If it returns `false`, no drawable was available:
   count a **skipped frame** and return **without** consuming the accumulator further (FR-027a,
   FR-027b).
6. **Record instrumentation** — frame duration, draw-path allocation count, skipped-frame and
   dropped-frame counters, kept separate per FR-027c. Compiled only under
   `SWIFTSKY_INSTRUMENTATION` (FR-021e) and allocation-free itself (FR-021f).

**Allocation rule**: steps 1–6 must not allocate on the heap (FR-020, SC-004). The event queue must be
pre-sized or use a fixed-capacity structure; the instrumentation must accumulate into preallocated
counters.

---

## Skipped vs dropped frames (FR-027c)

These are distinct and must be counted separately:

| Term | Cause | Loop's response |
|------|-------|-----------------|
| **Skipped frame** | No drawable available — step 5 returned `false`. Common under rapid resize or memory pressure. | Skip silently, retain accumulated time, count it. Never fatal, never user-visible (FR-027a). |
| **Dropped frame** | Work overran the frame budget, so a display deadline was missed. | Nothing to do at runtime; it is a performance signal for SC-003. |

Conflating them would make SC-003 unmeasurable, since SC-003 forbids both during an idle session while
FR-027a mandates skipping under backpressure.

---

## Start / stop lifecycle

```text
                  ┌──────────┐
   create ───────▶│  Stopped │◀──── visibilityChanged(false) ─────┐
                  └────┬─────┘                                   │
                       │ visibilityChanged(true)                  │
                       ▼                                          │
                  ┌──────────┐                                    │
                  │ Running  │────────────────────────────────────┘
                  └────┬─────┘
                       │ willTerminate
                       ▼
                  ┌──────────┐
                  │ Drained  │  (terminal — no frame in flight)
                  └──────────┘
```

- **Stopped**: display link paused, no frames produced. Entered whenever content is not visible —
  backgrounded, minimised, occluded, or scene disconnected (FR-008).
- **Running**: display link active, per-frame sequence executing.
- **Drained**: terminal. Reached only via `stopAndDrain()`. On return, no frame is in flight, so
  graphics resources can be released safely (FR-032). Teardown ordering is explicit, never left to
  deallocation order.

**Accumulator on resume**: resuming from Stopped produces a large elapsed value on the first frame. The
FR-021b clamp handles it — 4 ticks, excess discarded — so no catch-up storm occurs (long-stall edge
case).

---

## Marshalling contract

- Main thread calls `post(_:)`; it enqueues and returns immediately (FR-029).
- The loop consumes events only at step 1 of a frame (FR-031).
- Events are applied in FIFO order.
- `willTerminate` is the sole synchronising case: the main thread calls `stopAndDrain()` and waits for
  the drain, not for a presented frame.
- Every payload is a value type, so transfer safety is structural rather than annotated (FR-030,
  FR-012d).

**Invariant to hold under sanitiser (SC-015, SC-016)**: no data race, and no main-thread stall longer
than one frame interval during ten seconds of continuous resizing.

---

## Failure handling at construction

Renderer initialisation happens **before** the loop starts, on the main thread:

1. Obtain the graphics device. On failure → `RendererError.noGraphicsDevice`.
2. Construct `Renderer` (compiles shaders, creates pipeline state and quad). Any failure throws a
   `RendererError`.
3. On any thrown error: present the FR-024 text-only notice with `userFacingDescription`, emit the
   FR-026 diagnostic, trap in debug builds, and terminate on dismissal. **Never** start the loop, and
   never fall back to a non-pipeline black surface (FR-027).
4. On success: create the loop and post `visibilityChanged(true)`.

This ordering means a running loop always has a working renderer, so the per-frame path has no
initialisation failure modes to handle — only the transient drawable case (FR-027a).
