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
    public internal(set) var phase: AutopilotPhase?   // set by the law in AutopilotLaw.swift

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
`D`, the tolerances, the previous phase. `dt = 1/60`. Constants (research R3–R5, R11): `a′ = 0.9 a`,
`k = 10 s⁻¹`, cone `0.1 rad`, hold fraction `0.5`, hold acceleration `0.05 a`, response time
`τ = 1/15 s`, settle `0.001` u/s.

1. `r = D − p`, `d = |r|`, `r̂ = r/d` (if `d = 0`, `r̂ = 0`), `ĥ = (cos h, sin h)`.
2. **Arrival**: if `d ≤ tol.position` and `|v| < tol.speed`, or the previous phase is arrived and
   `d ≤ tol.position` → phase **arrived** (the law below still runs: station-keeping).
3. **Flip time** `T`: the shortest time to turn from `h` to the heading of `−r̂` and stop, starting at
   the current rate `ω` (`turnTime`, research R2/R11); `T = 0` when `d = 0`; `T = ∞` if the ship
   cannot turn and has an angle to cover.
4. **Desired velocity** `v* = r̂ · s`, `s = min(vStop, k·d)`, `vStop = 2d / (T + √(T² + 2d/a′))`;
   `s = 0` when `a′ = 0` or `T = ∞`. Its slope `s′ = ds/dd` is `1/(T + vStop/a′)` on the `vStop`
   branch and `k` on the tail.
5. **Error** `e = v* − v`. If `|e| ≤ settle` → input `.neutral`; phase by step 8 (coasting).
   Otherwise the **desired acceleration** is `A = e/τ + r̂ · (−(v·r̂) · s′)` — the error term plus the
   profile's own rate of change as the ship closes (feedforward).
6. **Target heading** `ψ = atan2(A.y, A.x)`, unless the **hold rule** applies: committed to braking
   (`ĥ·v < 0`, or the previous phase is flipping or braking), closing (`v·r̂ > 0`), at most slightly
   slow (`e·v̂ < 0.5 s`) and no decisive call to brake (`−A·v̂ < 0.05 a`). Then `ψ = heading(−v)`
   and no thrust. `δ = wrap(ψ − h)` into (−π, π].
7. **Input**:
   - `turn = sign(δ) · min(ωmax, √(2α|δ|), |δ|/dt) / ωmax` (0 if `ωmax = 0`).
   - `thrust = clamp((A·ĥ)/a, 0, 1)` if `|δ| ≤ cone` and not holding and `a > 0`; else 0.
8. **Phase** (unless arrived by step 2):
   - thrusting → **braking** if `ĥ·v < 0`, else **burning**;
   - turning (`|δ| > cone`) towards a target opposing the velocity (`target·v < 0`) → **braking** if
     the previous phase is braking, else **flipping**; towards any other target → **burning** if the
     previous phase is burning, else **aligning**;
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
