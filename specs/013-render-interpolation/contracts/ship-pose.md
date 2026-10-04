# Contract: Ship pose, tick fraction and the drawn pose

## C1 — `ShipPose` (logic layer, public)

```swift
public struct ShipPose: Equatable, Sendable {
    public var position: Vector2
    public var heading: Double
    public init(position: Vector2, heading: Double)
    public init(_ ship: Ship)
    public static func blended(from previous: ShipPose, to current: ShipPose, fraction: Double) -> ShipPose
}
```

- `fraction` is expected in `[0, 1)`; values outside are clamped into it.
- `fraction == 0` → `previous`, bit for bit.
- Equal position components / equal headings → that component of `previous`, bit for bit.
- Position: linear per component. Heading: shortest signed arc, `−π` treated as `+π`
  (counter-clockwise), result in `(−π, π]`.
- Pure, allocation-free.

## C2 — `TimeAccumulator.tickFraction` (logic layer, public)

```swift
public var tickFraction: Double { get }   // always in [0, 1)
```

## C3 — `Simulation.advance` with the previous pose (logic layer, public)

```swift
public static func advance(_ state: SimulationState, ticks: Int, previousPose: inout ShipPose) -> SimulationState
public static func advance(_ state: SimulationState, ticks: Int, input: ControlInput, previousPose: inout ShipPose) -> SimulationState
```

- Returned state: byte-identical to the overload without `previousPose`.
- `ticks <= 0`: `previousPose` unchanged.
- `ticks >= 1`: `previousPose` = the ship's pose immediately before the last tick.

## C4 — `Renderer.render` (rendering layer, public, CHANGED)

```swift
public func render(state: SimulationState, shipPose: ShipPose, surface: RenderSurface,
                   drawable: any CAMetalDrawable, timestamp: Double) -> Bool
```

The ship sprite is placed from `shipPose` (007's whole-pixel rounding applied); every other use of the
state is unchanged. `shipPose` is never written anywhere.

## C5 — `--no-interpolation` (Debug and Profiling builds)

Parsed into `DebugShipOptions.interpolates == false`; the frame loop then passes
`ShipPose(state.ship)` as the drawn pose. Release builds do not recognise the argument.
