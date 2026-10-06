# Data Model: Ship and Order Lines on the Debug Overlay

## DebugOverlayShip *(rendering layer, instrumentation only)*

A plain value: what the ship and its order were at the overlay's last refresh.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| `position` | `Vector2` | `state.ship.position` | world units |
| `velocity` | `Vector2` | `state.ship.velocity` | world units per second |
| `heading` | `Double` | `state.ship.heading` | radians, (−π, π] |
| `angularVelocity` | `Double` | `state.ship.angularVelocity` | radians per second, counter-clockwise positive |
| `order` | `DebugOverlayShip.Order?` | `nil` when `state.autopilot.order` is `nil` | |

`DebugOverlayShip.Order`:

| Field | Type | Source |
|-------|------|--------|
| `phase` | `AutopilotPhase` | `state.autopilot.phase` |
| `destination` | `Vector2` | `state.autopilot.order.destination` |
| `distance` | `Double` | `state.distanceRemaining` |

**Validation**: an order is present exactly when the autopilot holds one; its phase is then never `nil`
(006). If the phase were `nil` with an order, the snapshot treats it as no order. Speed is not stored: it
is the length of `velocity`, computed when written (spec clarification).

**Lifecycle**: built at each due refresh (4 Hz) from the state at step 3a; replaces the previous one;
never mutated.

## Overlay lines

The six 003 lines, then, when `ship` is set: `pos`, `vel`, `speed`, `heading`, `turn`, `order`, and with
an order `dest` and `dist`. Exact texts in [contracts/debug-overlay-ship-order.md](./contracts/debug-overlay-ship-order.md).
