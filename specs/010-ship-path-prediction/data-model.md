# Data Model: Predict the Ship's Planned Path

**Feature**: `010-ship-path-prediction` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

All types live in `SwiftSkySimulation` and are `Sendable`, `Equatable` value types (FR-010, FR-011,
FR-012). Existing types from 004 and 006 (`Vector2`, `Ship`, `ControlInput`, `MoveOrder`,
`Autopilot`) are unchanged.

## PlannedPath

| Field | Type | Notes |
|-------|------|-------|
| `points` | `InlineArray<256, Vector2>` (private, `typealias Points`) | World units. Only `0..<count` are meaningful. |
| `count` | `Int` | `0` when empty; otherwise `1…256`. |
| `startTick` | `UInt64` | The tick count at which the order was given; the tick of point 0. |
| `spacing` | `Int` | Ticks between consecutive points: 1, 2, 4, 8 or 16 (a power of two, R5). `1` when empty. |
| `endTick` | `UInt64` | The tick count of the last point: the predicted arrival, or `startTick + 3,600` at the cap. |
| `reachesArrival` | `Bool` | `true` when the prediction stopped on an `arrived` state; `false` at the cap and when empty. |

Constants, each written once:
- `capacity` = `Points.count` = 256 (FR-005).
- `maxFlightTicks` = `60 * FixedTimestep.tickRate` = 3,600 (FR-006).

**Invariants**
- Empty ⇔ `count == 0` ⇔ the state has no order (FR-001).
- `count ≤ capacity` always.
- Point `i < count − 1` is the predicted position at tick `startTick + i · spacing`; the last point is
  the position at `endTick`, and `endTick − startTick` lies in
  `((count − 2) · spacing, (count − 1) · spacing]` when `count ≥ 2` (FR-004).
- `endTick − startTick ≤ maxFlightTicks` (SC-004).
- A flight of `n ≤ 255` ticks gives `count == n + 1` and `spacing == 1`; a longer one gives
  `128 ≤ count ≤ 256` (FR-005).
- `count == 1` ⇔ the order was already arrived when given: `startTick == endTick`, `reachesArrival`.
- Equality compares `count`, `startTick`, `spacing`, `endTick`, `reachesArrival` and points
  `0..<count` only (R7).

**Lifecycle**

```text
 (empty) ──setOrder accepted──▶ predicted ──setOrder accepted──▶ predicted (replaced whole)
    ▲                               │
    │                               ├── advance (any ticks, any input) ──▶ unchanged (FR-008)
 launch                             └── setOrder refused ──▶ unchanged (FR-007)
```

There is no transition back to empty: 006 has no way to cancel an order.

## SimulationState (changed)

| Field | Type | Change |
|-------|------|--------|
| `tickCount` | `UInt64` | unchanged |
| `ship` | `Ship` | unchanged |
| `autopilot` | `Autopilot` | unchanged |
| `plannedPath` | `PlannedPath` | **new**; `public private(set)`, empty at launch and in every initialiser |

- `setOrder(to:)` — unchanged signature and result. On acceptance it now also predicts
  `plannedPath` from the ship, the autopilot (after its `setOrder`) and `tickCount`; on refusal it
  changes nothing (FR-007, FR-009).
- Size grows from 114 to 4,249 bytes (`PlannedPath` is 4,129 bytes, measured with `MemoryLayout`).
  Still a plain value, no heap; copied once per `advance` call and when handed to the renderer (R2, R10).
