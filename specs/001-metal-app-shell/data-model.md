# Data Model: Metal App Shell

**Feature**: `001-metal-app-shell` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

No persistence exists in this feature. Everything below is in-memory, and all of it is value types
(FR-012c). "Entity" here means a boundary object the layer split depends on, not a stored record.

---

## Ownership and isolation map

| Entity | Defined in | Held by | Crosses a concurrency boundary? |
|--------|-----------|---------|--------------------------------|
| `SimulationState` | Simulation | Frame loop | No — created and consumed inside the loop's domain |
| `TimeAccumulator` | Simulation | Frame loop | No |
| `FixedTimestep` (constants) | Simulation | — (static) | N/A |
| `RenderSurface` | Rendering | Frame loop, produced by platform layer | **Yes** — main thread → loop domain (FR-030) |
| `SurfaceEvent` | Platform | Marshalled main → loop | **Yes** (FR-029) |

The loop's serial queue is the only isolation domain that touches simulation state, so no lock exists
anywhere (FR-012c). Transfer safety comes from value semantics, not annotations (FR-012d).

---

## `SimulationState`

The logic layer's snapshot and the single typed hand-off the renderer consumes (FR-012, FR-012a).

| Field | Type | Meaning |
|-------|------|---------|
| `tickCount` | unsigned 64-bit integer | Total fixed-timestep ticks advanced since launch |

**Invariants**

- Monotonically non-decreasing across the app's lifetime (SC-020).
- Contains **no presentation concept** — no colour, no size, no view reference (FR-012b). The quad's
  black colour belongs to the render layer.
- Value type with no reference members, so passing it to the renderer is a copy.

**Rationale for holding only a tick count**: it is the minimum that makes the hand-off real rather than
a declared-but-unused type, while remaining something the logic layer legitimately owns. It must not
affect visible output (FR-012b).

---

## `TimeAccumulator`

Carries unconsumed real time between frames and decides how many ticks a frame advances (FR-021a).

| Field | Type | Meaning |
|-------|------|---------|
| `unconsumed` | seconds, floating point | Real time not yet converted into ticks |

**Behaviour** — `consume(elapsed:)` returns a whole tick count and mutates `unconsumed`:

1. Add `elapsed` to `unconsumed`.
2. Compute `ticks = floor(unconsumed / FixedTimestep.tickDuration)`.
3. If `ticks > FixedTimestep.catchUpClamp`, set `ticks = catchUpClamp` and **discard** the excess by
   setting `unconsumed` to its remainder modulo the tick duration (FR-021b).
4. Otherwise subtract `ticks * tickDuration` from `unconsumed`.
5. Return `ticks`.

**Invariants**

- `unconsumed` is always `>= 0` and, after `consume`, always `< tickDuration` when the clamp fires.
- Returns `0` when less than one tick of time has accumulated — a legal, common outcome, since the
  simulation is 60 Hz while the display may be faster.
- Never returns more than `catchUpClamp`.
- Deterministic: identical elapsed-time sequences produce identical tick sequences (SC-013).
- No clock access of its own — elapsed time is always injected, which is what makes it testable
  synchronously with synthetic values.

**Edge behaviour worth stating explicitly**: a 10-second stall yields exactly `4` ticks, not `600`. The
simulation loses time rather than stalling the frame budget trying to reclaim it. This is documented
behaviour, not a defect (SC-013, and the long-stall edge case in the spec).

---

## `FixedTimestep` (constants)

Named constants in one place, not scattered literals (FR-021b).

| Constant | Value | Source |
|----------|-------|--------|
| `tickRate` | 60 Hz | FR-021a |
| `tickDuration` | `1.0 / 60.0` seconds | Derived |
| `catchUpClamp` | 4 ticks | FR-021b |

Independent of any display refresh rate (FR-021a) — a 120 Hz display does not double the simulation
rate.

---

## `RenderSurface`

Describes the drawable region the renderer presents into. Produced by the platform layer, consumed by
the render layer, which knows nothing about what kind of window or view it belongs to (FR-014).

| Field | Type | Meaning |
|-------|------|---------|
| `widthPixels` | unsigned integer | Drawable width in device pixels |
| `heightPixels` | unsigned integer | Drawable height in device pixels |
| `backingScale` | floating point | Points-to-pixels factor of the hosting display |

**Invariants**

- A surface with `widthPixels == 0 || heightPixels == 0` is **not renderable**; the loop skips drawing
  rather than attempting it (zero-area edge case).
- Aspect ratio is unconstrained — any ratio is legal, including portrait-shaped sizes under iPad
  multitasking despite the app being landscape-only (FR-006b).
- Value type, so it transfers safely across the FR-030 boundary by copy.

**State transitions**: replaced wholesale, never mutated in place. A new surface takes effect at a
frame boundary (FR-031), never mid-draw.

---

## `SurfaceEvent`

The marshalling payload from main thread to loop domain (FR-029). A closed set of cases:

| Case | Payload | Loop's response |
|------|---------|-----------------|
| `resized` | `RenderSurface` | Adopt at next frame boundary (FR-031) |
| `backingScaleChanged` | `RenderSurface` | Adopt at next frame boundary |
| `visibilityChanged` | Boolean | Start or stop the loop (FR-008, FR-021) |
| `willTerminate` | — | Stop and drain, then signal completion (FR-032) |

**Invariants**

- Delivery is non-blocking from the main thread's perspective (FR-029) — enqueue and return.
- Events are applied in order, at frame boundaries only.
- `willTerminate` is the only case the main thread waits on, and it waits for the drain to finish, not
  for a frame to be presented.

---

## Not modelled in this feature

- **Frame Tick** appears in the spec's Key Entities as a concept but needs no type: it is a count, and
  its size is the `FixedTimestep.tickDuration` constant. Introducing a wrapper type would be
  speculative structure (Principle V).
- No entity carries colour, geometry, assets, input, or persisted data.
