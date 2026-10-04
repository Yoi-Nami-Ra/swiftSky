# Data Model: Interpolate Rendering Between Simulation Ticks

## ShipPose (NEW, `SwiftSkySimulation`)

| Field | Type | Meaning |
|-------|------|---------|
| `position` | `Vector2` | World units, as `Ship.position` |
| `heading` | `Double` | Radians in (−π, π], as `Ship.heading` |

- `init(_ ship: Ship)` copies the two fields bit for bit.
- `init(position:heading:)` for tests; the heading is stored as given.
- `Equatable`, `Sendable`. 24 bytes, no heap.
- `static func blended(from:to:fraction:) -> ShipPose`: research R3.

## TimeAccumulator (CHANGED)

| Member | Change |
|--------|--------|
| `unconsumed` | Invariant now enforced: clamped to ≥ 0 after whole ticks are taken (R1) |
| `tickFraction` | NEW, read-only: `unconsumed / tickDuration` clamped into `0 ... 1.0.nextDown` |

## Simulation (CHANGED)

| Function | Change |
|----------|--------|
| `advance(_:ticks:previousPose:)` | NEW: as `advance(_:ticks:)`, recording the pose before the last tick (R4) |
| `advance(_:ticks:input:previousPose:)` | NEW: the same for an explicit input |
| `advance(_:ticks:)`, `advance(_:ticks:input:)` | Unchanged behaviour; now call the new variants |

`previousPose` transitions per frame: `ticks == 0` → unchanged; `ticks ≥ 1` → the ship's pose after
`ticks − 1` of the frame's ticks.

## FrameLoop (CHANGED, platform)

| Field | Type | Meaning |
|-------|------|---------|
| `previousPose` | `ShipPose` | The ship's pose one tick before `state`; initial pose before the first tick |
| `debugNoInterpolation` | `Bool` | Instrumented builds only; `--no-interpolation` |

## Drawn pose (per frame, not stored)

`ShipPose.blended(from: previousPose, to: ShipPose(state.ship), fraction: accumulator.tickFraction)`,
or `ShipPose(state.ship)` when `debugNoInterpolation`. Passed to `Renderer.render`.
