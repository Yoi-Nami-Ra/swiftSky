# Contract: Ship and Order Lines on the Debug Overlay

**Feature**: [../spec.md](../spec.md) | **Data model**: [../data-model.md](../data-model.md)

Everything marked *(instrumentation)* exists only when `SWIFTSKY_INSTRUMENTATION` is defined.

## C1 — Signed writer (rendering layer, all builds)

```swift
extension TextBuffer {
    /// `value` rounded half away from zero to two decimals, with a leading `-` when negative and not
    /// rounded to zero, right-aligned in `width` columns (the sign counts), written in full when wider.
    /// NaN → "0.00"; huge magnitudes clamped as in `writeHundredths`. Allocates nothing.
    public func writeSignedHundredths(_ value: Double, width: Int = 0, limit: Int = .max)
}
```

| Input | `width: 9` output |
|-------|-------------------|
| `0` | `     0.00` |
| `-0.004` | `     0.00` |
| `-0.005` | `    -0.01` |
| `12.345` | `    12.35` |
| `-1234.5` | ` -1234.50` |
| `99999.99` | ` 99999.99` |
| `-99999.99` | `-99999.99` |
| `-123456.789` | `-123456.79` (wider, in full) |
| `.nan` | `     0.00` |

`writeHundredths` is unchanged (its table in 003's contract still holds).

## C2 — Snapshot *(instrumentation)*

```swift
public struct DebugOverlayShip: Sendable, Equatable {
    public struct Order: Sendable, Equatable {
        public var phase: AutopilotPhase
        public var destination: Vector2
        public var distance: Double
    }
    public var position: Vector2
    public var velocity: Vector2
    public var heading: Double
    public var angularVelocity: Double
    public var order: Order?

    public init(position:velocity:heading:angularVelocity:order:)
    public init(_ state: SimulationState)
}

extension DebugOverlay {
    /// Degrees for the heading line: radians × 180/π, except that a value rounding to −180.00 is 180.
    static func headingDegrees(_ radians: Double) -> Double
}
```

## C3 — Overlay text *(instrumentation)*

`DebugOverlay` gains `public var ship: DebugOverlayShip?`. When `statistics` is set, `write` writes the
six 003 lines; when `ship` is also set, it continues on the next lines with (9-column signed values):

| Line | Text |
|------|------|
| position | `pos     x` *x* ` y` *y* |
| velocity | `vel     x` *x* ` y` *y* |
| speed | `speed   ` *‖v‖* ` u/s` |
| heading | `heading ` *headingDegrees* ` deg` |
| turn | `turn    ` *ω·180/π* ` deg/s` |
| order | `order   none` / `order   ` + `aligning` · `burning` · `flipping` · `braking` · `arrived` |
| destination *(order only)* | `dest    x` *x* ` y` *y* |
| distance *(order only)* | `dist    ` *d* ` u` |

Example, ship at rest at launch:

```
pos     x     0.00 y     0.00
vel     x     0.00 y     0.00
speed        0.00 u/s
heading      0.00 deg
turn         0.00 deg/s
order   none
```

Example, in flight:

```
pos     x   -12.50 y    40.00
vel     x    30.00 y   -40.00
speed       50.00 u/s
heading    -53.13 deg
turn         0.00 deg/s
order   burning
dest    x   300.00 y  -200.00
dist       394.03 u
```

Nothing is written without `statistics` (003). Every write is capped at the remaining capacity.

## C4 — Hand-over *(instrumentation)*

```swift
// Renderer, replacing updateDebugOverlay(_:):
public func updateDebugOverlay(_ statistics: DebugOverlayStatistics, ship: DebugOverlayShip)
```

`FrameLoop` step 3a, on a due refresh only:

```swift
if let statistics = instrumentation.overlayStatistics(at: now) {
    renderer.updateDebugOverlay(statistics, ship: DebugOverlayShip(state))
}
```

`state` here is the state before step 4's advance: the latest completed tick (R1). Inside the counted
stretch; allocates nothing.
