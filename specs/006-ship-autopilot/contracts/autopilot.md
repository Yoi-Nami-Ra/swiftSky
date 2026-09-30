# Contract: Autopilot

**Feature**: `006-ship-autopilot` | **Module**: `SwiftSkySimulation`

The public surface added by this feature and the per-tick law behind it. Shapes are in
[data-model.md](../data-model.md); the reasons in [research.md](../research.md).

## Public API

```swift
public struct MoveOrder: Sendable, Equatable {
    public let destination: Vector2
    public init?(destination: Vector2)          // nil if either component is non-finite
}

public enum AutopilotPhase: Sendable, Equatable {
    case aligning, burning, flipping, braking, arrived
}

public struct ArrivalTolerances: Sendable, Equatable {
    public let position: Double                 // world units
    public let speed: Double                    // world units per second
    public init(position: Double, speed: Double) // negative / non-finite → 0
    public static let `default`: ArrivalTolerances  // 1, 1
}

public struct Autopilot: Sendable, Equatable {
    public let tolerances: ArrivalTolerances
    public private(set) var order: MoveOrder?
    public private(set) var phase: AutopilotPhase?

    public init(tolerances: ArrivalTolerances = .default)

    /// Replaces the order and evaluates the phase against `ship` at once.
    public mutating func setOrder(_ order: MoveOrder, for ship: Ship)

    /// This tick's input for `ship`, and the phase it implies. `.neutral` and no phase change
    /// without an order. Updates `phase`.
    public mutating func control(for ship: Ship) -> ControlInput
}

public struct SimulationState {                              // existing struct, additions only
    public var autopilot: Autopilot                          // new stored property; Autopilot() at launch
    @discardableResult
    public mutating func setOrder(to destination: Vector2) -> Bool  // false, no change, if refused
    public var distanceRemaining: Double? { get }
}

extension Simulation {
    /// Autopilot-driven: each tick's input is `autopilot.control(for: ship)` from that tick's
    /// starting state; neutral without an order. n ticks at once == n single ticks.
    public static func advance(_ state: SimulationState, ticks: Int) -> SimulationState

    /// Explicit: `input` drives every tick (004 behaviour); the order and phase are untouched.
    public static func advance(_ state: SimulationState, ticks: Int, input: ControlInput) -> SimulationState
}
```

`ticks ≤ 0` returns the state unchanged in both overloads, as before.

## The per-tick law

Inputs: the ship (`p`, `v`, heading `h`, rate of turn `ω`, limits `a`, `ωmax`, `α`), the destination
`D`, the tolerances, the previous phase. `dt = 1/60`. Constants: `a′ = 0.9 a`, `k = 10 s⁻¹`,
cone `0.1 rad`, hold fraction `0.5`, settle `0.001` u/s.

1. `r = D − p`, `d = |r|`, `r̂ = r/d` (if `d = 0`, `r̂ = 0`), `ĥ = (cos h, sin h)`.
2. **Arrival**: if `d ≤ tol.position` and `|v| < tol.speed`, or the previous phase is arrived and
   `d ≤ tol.position` → phase **arrived** (the law below still runs: station-keeping).
3. **Flip time** `T`: rest-to-rest time to turn from `h` to the heading of `−r̂`
   (`θ = |wrap(heading(−r̂) − h)|`; `2√(θ/α)` if `θ ≤ ωmax²/α`, else `θ/ωmax + ωmax/α`); `T = 0`
   when `d = 0`. If the ship cannot turn (`ωmax = 0` or `α = 0`) and `θ > 0`, `T = ∞`.
4. **Desired velocity** `v* = r̂ · min(vStop, k·d)` with `vStop = 2d / (T + √(T² + 2d/a′))`;
   `vStop = 0` when `a′ = 0` or `T = ∞`.
5. **Error** `e = v* − v`. If `|e| ≤ settle` → input `.neutral`; phase by step 8 (coasting).
6. **Target heading** `ψ = atan2(e.y, e.x)`, unless the **hold rule** applies
   (`ĥ·v < 0` and `v·r̂ > 0` and `0 < e·v̂ < 0.5·|v*|`): then `ψ = heading(−v)` and no thrust.
   `δ = wrap(ψ − h)` into (−π, π].
7. **Input**:
   - `turn = sign(δ) · min(ωmax, √(2α|δ|), |δ|/dt) / ωmax` (0 if `ωmax = 0`).
   - `thrust = clamp((e·ĥ)/(a·dt), 0, 1)` if `|δ| ≤ cone` and not holding and `a > 0`; else 0.
8. **Phase** (unless arrived by step 2):
   - thrusting → **braking** if `ĥ·v < 0`, else **burning**;
   - turning (`|δ| > cone`) → **flipping** if `ψ̂·v < 0` and the previous phase is not braking;
     **braking** if `ψ̂·v < 0` and the previous phase is braking; else **aligning**;
   - otherwise (coasting / holding / settled) → **braking** if `ĥ·v < 0`, else **burning**.

All quantities are finite for any finite ship, any sanitised limits and any accepted order (FR-013):
every division is guarded as written above.

## Guarantees (mapped to the spec)

| Guarantee | Spec |
|-----------|------|
| Only the returned `ControlInput` affects the ship; 004's `step` is unchanged | FR-004 |
| New order replaces the old; non-finite refused | FR-002 |
| `phase == nil ⇔ order == nil` | FR-003 |
| Burn direction from `e = v* − v` cancels cross-track velocity | FR-006 |
| Flip point from `vStop(d, T)`, before halfway from rest | FR-007 |
| `a′ = 0.9a` margin: no overshoot from the profile | SC-003 |
| Arrival latch + law keeps running = station-keeping; settle → neutral, spin stops | FR-009, SC-008 |
| Pure; constant work; no allocation | FR-012, FR-015 |
| Everything needed is in `SimulationState` | FR-014 |
