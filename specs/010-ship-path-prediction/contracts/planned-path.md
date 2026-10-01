# Contract: Planned Path

**Feature**: `010-ship-path-prediction` | **Module**: `SwiftSkySimulation` (log line: `SwiftSkyPlatform`)

The public surface added by this feature, the prediction behind it and the Debug log fields. Shapes
are in [data-model.md](../data-model.md); the reasons in [research.md](../research.md).

## Public API

```swift
public struct PlannedPath: Sendable, Equatable {
    public static let capacity: Int              // 256 (InlineArray<256, Vector2>.count)
    public static let maxFlightTicks: Int        // 60 * FixedTimestep.tickRate = 3,600

    public static let empty: PlannedPath         // no points; startTick = endTick = 0, spacing 1

    public private(set) var count: Int           // 0…capacity
    public private(set) var startTick: UInt64    // tick of point 0: when the order was given
    public private(set) var spacing: Int         // ticks between points (1, 2, 4, …)
    public private(set) var endTick: UInt64      // tick of the last point
    public private(set) var reachesArrival: Bool

    public var isEmpty: Bool { get }
    public subscript(index: Int) -> Vector2 { get }   // precondition: 0 ≤ index < count
    public var last: Vector2? { get }                 // nil when empty

    public static func == (lhs: PlannedPath, rhs: PlannedPath) -> Bool   // used points only
}

public struct SimulationState {
    // … unchanged members …
    public private(set) var plannedPath: PlannedPath   // empty until an order is accepted

    /// Unchanged signature. On acceptance, also predicts `plannedPath`. On refusal, changes nothing.
    @discardableResult public mutating func setOrder(to destination: Vector2) -> Bool
}
```

Internal (visible to `@testable` tests):

```swift
extension PlannedPath {
    /// A path holding `start` at `tick`, ready to record a flight.
    init(start: Vector2, tick: UInt64)

    /// Records the position after one more tick of the flight (R5's thinning).
    mutating func append(_ position: Vector2)

    /// Ends the flight on the position appended last (or on `start` if none was), and sets `endTick`.
    mutating func finish(reachesArrival: Bool)

    /// Flies copies of `ship` and `autopilot` from `tickCount` (R4). Empty without an order.
    init(predictingFrom ship: Ship, autopilot: Autopilot, tickCount: UInt64)
}

extension Simulation {
    /// One tick, flown by the autopilot: shared by `advance(_:ticks:)` and the prediction (R3).
    static func tick(_ ship: inout Ship, _ autopilot: inout Autopilot)
}
```

## The prediction

Given the ship, the autopilot just after `setOrder` accepted an order, and the tick count `t₀`:

1. **No order** → `.empty`.
2. Start a path with the ship's position at `t₀`.
3. **Already arrived** (`autopilot.phase == .arrived`) → finish with one point, `reachesArrival = true`,
   `endTick = t₀`.
4. Repeat for `k = 1…maxFlightTicks`:
   1. `Simulation.tick(&ship, &autopilot)` on the local copies.
   2. `append(ship.position)`.
   3. If `autopilot.phase == .arrived` → finish with `reachesArrival = true`, `endTick = t₀ + k`.
5. Not arrived after `maxFlightTicks` → finish with `reachesArrival = false`,
   `endTick = t₀ + maxFlightTicks`.

The copies are discarded; the state's ship, autopilot and tick count are untouched (FR-009).

## Thinning (`append` / `finish`)

State: `count`, `spacing` (starts at 1) and `endTick`, which tracks the tick of the latest position
while the flight is recorded; `n = endTick − startTick` is the number of ticks recorded.

- `append`: `endTick += 1`. If `count == capacity`, thin first: keep points `0, 2, 4, …,
  capacity − 2` in order (they become `0…capacity/2 − 1`), `count = capacity / 2`, `spacing *= 2`.
  Then stage the position in slot `count`; if `n` is a multiple of `spacing`, it is a point:
  `count += 1`. Otherwise it stays staged and the next `append` overwrites it.
- `finish`: if `n` is not a multiple of `spacing`, the staged final position becomes the last point
  (`count += 1`); there is always room, because a full buffer is thinned before anything is staged.

Thinning as soon as the flight goes on past a full buffer, rather than when the next point is due,
gives the same path in every case: a point due at the next multiple of the doubled spacing lands in
the same slot either way, and a flight that ends first keeps its final position as the last point
either way. It needs no field beyond the path's own.

Results (data-model invariants): a flight of `n ≤ 255` ticks has `n + 1` points at spacing 1; a
longer one has 128–256 points; at the cap, spacing 16 and 226 points.

## Simulation (changed)

`advance(_:ticks:)` keeps its contract (006 FR-011) and now calls `tick` once per tick.
`advance(_:ticks:input:)` is unchanged. Neither writes `plannedPath` (FR-008).

## Debug order log line (`SwiftSkyPlatform`)

`Instrumentation.recordOrder(_ outcome: MoveOrderOutcome, viewPoint: Vector2, path: PlannedPath)`,
called by the frame loop after applying an order request with `state.plannedPath`. For `.ordered`:

```text
order view=(vx, vy) world=(wx, wy) predicted=(px, py) ticks=N points=P arrives=yes
```

- `predicted` and `ticks` are `path.last` and `path.endTick`, interpolated exactly like the arrival
  line's `world` and `ticks`: `arrived world=(px, py) ticks=N`.
- `points` is `path.count`; `arrives` is `path.reachesArrival` with the `.answer` format (`yes`/`no`).
- The two `order dropped …` lines are unchanged, and nothing is logged on frames without an order
  request. Release: the no-op gains the same parameter.
