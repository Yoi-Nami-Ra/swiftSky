# Data Model: Ship State and Newtonian Motion

**Feature**: [spec.md](./spec.md) | **Plan**: [plan.md](./plan.md) | **Date**: 2026-09-30

All types live in `SwiftSkySimulation`, are `struct`s, and conform to `Sendable` and `Equatable`
(001 FR-012c). Every stored property is a `Double` or a nested value of `Double`s, except the tick
count. Angles are in radians (research R2).

## Vector2

A point or displacement in the world plane.

| Field | Type | Notes |
|-------|------|-------|
| `x` | `Double` | World units (or units/s for a velocity) |
| `y` | `Double` | Positive y is "up" for the heading convention (FR-004) |

Operations: `+`, `+=`, `* Double` (scale), and `static let zero`. Nothing else (Principle V).

## ShipLimits

The ship's fixed performance limits (FR-003). Immutable: every stored property is `let`.

| Field | Type | Default | Invariant |
|-------|------|---------|-----------|
| `maxThrustAcceleration` | `Double` | `200` units/s² | finite, ≥ 0 |
| `maxAngularSpeed` | `Double` | `π` rad/s (180 °/s) | finite, ≥ 0 |
| `maxAngularAcceleration` | `Double` | `2π` rad/s² (360 °/s²) | finite, ≥ 0 |

- `static let default` is the one place the defaults are written (FR-003).
- `init(maxThrustAcceleration:maxAngularSpeed:maxAngularAcceleration:)` sanitises: a non-finite or
  negative value becomes `0` (research R6).

## ControlInput

What the ship is asked to do on each tick of one `advance` call (FR-006, FR-007). Immutable.

| Field | Type | Range | Meaning |
|-------|------|-------|---------|
| `thrust` | `Double` | `0…1` | Fraction of `maxThrustAcceleration`, along the heading only |
| `turn` | `Double` | `-1…1` | Target rate of turn as a fraction of `maxAngularSpeed`; positive is counter-clockwise |

- `static let neutral` = `(thrust: 0, turn: 0)`.
- `init(thrust:turn:)` sanitises: non-finite → `0`, then clamp to the range.

## Ship

The one body the simulation moves (FR-001).

| Field | Type | Initial | Invariant |
|-------|------|---------|-----------|
| `position` | `Vector2` | `.zero` (FR-002) | — |
| `velocity` | `Vector2` | `.zero` | — |
| `heading` | `Double` | `0` (along +x) | in (−π, π] (FR-005) |
| `angularVelocity` | `Double` | `0` | \|value\| ≤ `limits.maxAngularSpeed` after any tick (FR-008) |
| `limits` | `ShipLimits` | `.default` | `let`: fixed for the ship's lifetime (FR-003) |

- `init(limits: ShipLimits = .default)` — the launch ship: at the origin, at rest, heading 0, not
  turning.
- `init(position:velocity:heading:angularVelocity:limits:)` — for tests that start mid-flight. The
  heading is wrapped into (−π, π] on construction by `Ship.wrapped(_:)`, which maps a non-finite
  heading to `0`; the angular velocity is taken as given (a test may deliberately start above a
  lowered target).
- `mutating func step(_ input: ControlInput)` — advances one fixed tick by the rule in
  [contracts/ship-motion.md](./contracts/ship-motion.md).

### Per-tick state transition

```text
                 ┌──────────── one tick, dt = 1/60 s ────────────┐
input.turn ──▶ target ω ──▶ ω (≤ maxStep toward target, snaps) ──▶ heading (+ω·dt, wrap)
                                                                        │
input.thrust ─────────────────────────────────▶ velocity (+ a·dt along heading, if thrust > 0)
                                                                        │
                                                            position (+ velocity·dt)
```

## SimulationState (changed)

| Field | Type | Initial | Change |
|-------|------|---------|--------|
| `tickCount` | `UInt64` | `0` | unchanged |
| `ship` | `Ship` | `Ship()` | **new** |

- `init()` and `init(tickCount:)` are kept and give the launch ship, so every existing caller and test
  compiles unchanged.
- `init(tickCount:ship:)` is new, for tests that start mid-flight.

## Relationships

```text
SimulationState 1 ──▶ 1 Ship 1 ──▶ 1 ShipLimits
Simulation.advance(state, ticks, input: ControlInput) ──▶ SimulationState
```

`ControlInput` is not stored anywhere (research R1).
