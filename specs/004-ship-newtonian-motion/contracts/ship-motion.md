# Contract: Ship Motion (SwiftSkySimulation public API)

**Feature**: [spec.md](../spec.md) | **Data model**: [data-model.md](../data-model.md)

The logic layer's public surface after this feature. Consumers are `SwiftSkyPlatform` (the frame
loop), `SwiftSkyRendering` (receives the state) and, later, SKY-25 / SKY-26 / SKY-27. Signatures are
shown without bodies.

## Changed

```swift
public enum Simulation {
    /// Advances `state` by `ticks` fixed timesteps, every tick driven by `input`.
    /// `ticks <= 0` returns `state` unchanged, ship included.
    public static func advance(
        _ state: SimulationState,
        ticks: Int,
        input: ControlInput = .neutral
    ) -> SimulationState
}

public struct SimulationState: Sendable, Equatable {
    public var tickCount: UInt64
    public var ship: Ship                                   // NEW
    public init()                                           // launch ship
    public init(tickCount: UInt64)                          // launch ship
    public init(tickCount: UInt64, ship: Ship)              // NEW
}
```

Source compatibility: `Simulation.advance(state, ticks: ticks)` in `FrameLoop.swift` and every 001
test compile and behave as before (FR-010).

## New

```swift
public struct Vector2: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double)
    public static let zero: Vector2
    public static func + (lhs: Vector2, rhs: Vector2) -> Vector2
    public static func += (lhs: inout Vector2, rhs: Vector2)
    public static func * (lhs: Vector2, rhs: Double) -> Vector2
}

public struct ShipLimits: Sendable, Equatable {
    public let maxThrustAcceleration: Double    // units/s²
    public let maxAngularSpeed: Double          // rad/s
    public let maxAngularAcceleration: Double   // rad/s²
    public init(maxThrustAcceleration: Double, maxAngularSpeed: Double, maxAngularAcceleration: Double)
    public static let `default`: ShipLimits     // 200 units/s², π rad/s, 2π rad/s²
}

public struct ControlInput: Sendable, Equatable {
    public let thrust: Double                   // 0…1
    public let turn: Double                     // -1…1, positive counter-clockwise
    public init(thrust: Double, turn: Double)
    public static let neutral: ControlInput
}

public struct Ship: Sendable, Equatable {
    public var position: Vector2
    public var velocity: Vector2
    public var heading: Double                  // radians, (−π, π]
    public var angularVelocity: Double          // rad/s
    public let limits: ShipLimits
    public init(limits: ShipLimits = .default)
    public init(position: Vector2, velocity: Vector2, heading: Double,
                angularVelocity: Double, limits: ShipLimits = .default)
    public mutating func step(_ input: ControlInput)
}
```

## Behaviour of `Ship.step(_:)` — one tick, `dt = FixedTimestep.tickDuration`

In this order (research R4):

| # | Update | Requirement |
|---|--------|-------------|
| 1 | `target = input.turn × limits.maxAngularSpeed` | FR-008 |
| 2 | `maxStep = limits.maxAngularAcceleration × dt` | FR-008 |
| 3 | If `|target − angularVelocity| ≤ maxStep`: `angularVelocity = target`; else `angularVelocity ± maxStep` toward `target` | FR-008 |
| 4 | `heading = Ship.wrapped(heading + angularVelocity × dt)`: untouched if in (−π, π]; otherwise `remainder(dividingBy: 2π)` with `−π` mapped to `π`; a non-finite value becomes `0` | FR-004, FR-005, R5 |
| 5 | If `input.thrust > 0`: `velocity += (cos heading, sin heading) × (input.thrust × limits.maxThrustAcceleration × dt)` | FR-009 |
| 6 | `position += velocity × dt` | FR-009 |

Guarantees:

- **Neutral input at rest is the identity**, bit for bit (SC-001): step 3 leaves `0` at `0`, step 4
  adds `0`, step 5 is skipped, step 6 adds `0 × dt`.
- **|angularVelocity| never exceeds `maxAngularSpeed`** once a tick has run from a state within it
  (SC-003).
- **`advance(s, ticks: n, input: i)` is bit-identical to n calls of `advance(s, ticks: 1, input: i)`**
  (FR-011): it is implemented as a loop of `step(i)`.
- **Pure** (FR-012): no clock, no randomness, no global state. `cos` and `sin` from the C library are
  the only external calls (research R3).
- **No allocation** (FR-013).

## Sanitisation

| Input | Result |
|-------|--------|
| `ControlInput(thrust: -0.5, turn: 2)` | `thrust 0, turn 1` |
| `ControlInput(thrust: .nan, turn: -.infinity)` | `thrust 0, turn 0` |
| `ShipLimits(maxThrustAcceleration: -1, maxAngularSpeed: .infinity, maxAngularAcceleration: 5)` | `0, 0, 5` |
