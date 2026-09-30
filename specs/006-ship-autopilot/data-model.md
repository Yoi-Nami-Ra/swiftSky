# Data Model: Ship Autopilot

**Feature**: `006-ship-autopilot` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

All types live in `SwiftSkySimulation`, are `Sendable`, `Equatable` value types, and hold only
`Double`s and enums (FR-012, FR-015, FR-016). Existing types from 004 (`Vector2`, `Ship`,
`ShipLimits`, `ControlInput`) are unchanged.

## MoveOrder

| Field | Type | Notes |
|-------|------|-------|
| `destination` | `Vector2` | World units. Both components finite. |

- Created with a failable initialiser: a non-finite component gives `nil` (FR-002).
- Immutable (`let`).

## AutopilotPhase

`enum`: `aligning`, `burning`, `flipping`, `braking`, `arrived` (FR-005). Classification rules in
[research.md](./research.md) R6 and the contract.

## ArrivalTolerances

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `position` | `Double` | 1 | World units. Negative or non-finite → 0 (FR-010). |
| `speed` | `Double` | 1 | World units per second. Same sanitising. |

`static let default` is the only place the defaults are written.

## Autopilot

| Field | Type | Notes |
|-------|------|-------|
| `tolerances` | `ArrivalTolerances` | `let`, fixed for the autopilot's lifetime. |
| `order` | `MoveOrder?` | `nil` until the first accepted order. Replaced whole by each new order. |
| `phase` | `AutopilotPhase?` | `nil` exactly when `order` is `nil`. The phase of the last evaluation. |

**Invariants**
- `order == nil ⇔ phase == nil`.
- Setting an order sets `phase` from an immediate evaluation against the current ship, so the
  read-out is valid straight away (story 4).
- The only memory between ticks is `phase` (R6). Everything else is recomputed from the ship.

**State transitions** (per tick, under an order; see R6):

```text
            ┌──────────────── new order (any phase) ───────────────┐
            ▼                                                      │
 (none) → aligning → burning → flipping → braking → arrived ───────┘
              ▲  ▲ └───────────── moving starts / turn-backs: phases may repeat ──┘
              │  └── station-keeping drift beyond position tolerance leaves arrived
```

From rest only the forward path occurs; `aligning` is skipped when the ship already faces the burn
direction, and an order within both tolerances goes straight to `arrived`.

## SimulationState (changed)

| Field | Type | Change |
|-------|------|--------|
| `tickCount` | `UInt64` | unchanged |
| `ship` | `Ship` | unchanged |
| `autopilot` | `Autopilot` | **new**; `Autopilot()` with default tolerances and no order at launch |

- `mutating func setOrder(to destination: Vector2) -> Bool` — `@discardableResult`; `false` and no
  change when refused.
- `var distanceRemaining: Double?` — `nil` without an order, else `|destination − ship.position|`.
- Still a plain value, copied when handed to the renderer (001 FR-012c). Size grows by the
  autopilot: 2 + 2 `Double`s plus two small enum/optional tags — well under 64 bytes, no heap.
