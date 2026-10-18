# Research: Ship Autopilot — Turn, Burn, Flip and Brake

**Feature**: `006-ship-autopilot` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

The decision record behind [plan.md](./plan.md). Each entry gives the decision, why, and what was
rejected. The per-tick law itself is written out in [contracts/autopilot.md](./contracts/autopilot.md).

---

## R1 — Closed-loop velocity tracking, not a precomputed schedule

**Decision**: Every tick the autopilot computes a **desired velocity** `v*` — pointing at the
destination, with a magnitude the ship can still brake from in the distance left — and the
**velocity error** `e = v* − v`. The ship turns to face `e` and thrusts along it once aligned. The
phases are *read off* this law (R6), not driven by a script.

**Rationale**:
- One rule covers every start (FR-006): from rest `e` points at the destination; with sideways
  drift `e` leans against the drift, so the burn cancels it instead of carrying it into an orbit.
- A new order is just a new destination in the next tick's `v*` (story 3), and rounding or an
  explicit-input interlude is absorbed the same way (spec Assumptions, "closed loop").
- Bounded work per tick (FR-015): a handful of `sqrt`, one `atan2`, one `cos`/`sin`.

**Alternatives rejected**:
- *Precomputed bang-bang schedule (burn until tick N, flip, brake until tick M)*: open loop, drifts
  with rounding, needs recomputation on every disturbance, and has no answer for sideways drift.
- *Optimal-control solver (minimum-time with rotation)*: iterative, unbounded work, far beyond what
  SC-002's 10 % + 0.5 s allowance requires (Principle V).
- *PID on position*: overshoots or crawls, and ignores the "can only push forward" constraint.

## R2 — The desired-speed profile accounts for the flip time

**Decision**: `|v*| = min(vStop(d, T), k·d)` where `d` is the distance left, `T` is the time the ship
needs to turn from its current heading to the braking attitude (facing away from the destination),
and

    vStop(d, T) = 2d / (T + √(T² + 2d / a′))

is the largest speed `s` with `s·T + s² / (2a′) ≤ d`: coast `T` seconds while turning, then brake at
`a′`. This is the algebraically stable form of `a′·(−T + √(T² + 2d/a′))`.

**Rationale**: FR-007. While burning towards the destination the ship faces it, so `T` is the full
flip time (1.5 s at the default limits) and `vStop` is reached *before* the halfway point — that
crossing is where `e` turns backwards and the flip starts. During the flip `T` shrinks as the ship
comes round while coasting shrinks `d`, keeping `s·T + s²/(2a′) = d` consistent. Once flipped
`T = 0` and the profile is the familiar `√(2a′d)`.

**T estimate**: the rest-to-rest minimum turn time through angle `θ`:
`2√(θ/α)` if `θ ≤ ω²max/α`, else `θ/ωmax + ωmax/α`. For θ = π at the defaults this is exactly 1.5 s.
It ignores the current rate of turn. At the start of a flip the ship is not turning, so it is exact
there; during the flip it overestimates, which only makes `v*` smaller — the safe direction, since
the ship is not thrusting while it turns anyway.

**Alternatives rejected**: `vStop` without `T` (flips at the halfway mark and overshoots by
`s·T` — exactly the defect the ticket names); a fixed flip distance (wrong for every speed but one).

## R3 — Braking margin `a′ = 0.9 a` guarantees no overshoot

**Decision**: The profile assumes braking at 90 % of the ship's thrust acceleration; the ship itself
brakes at up to 100 %.

**Rationale**: SC-003. A ship on the profile at speed `√(2a′d)` stops in `d·a′/a = 0.9 d` at full
thrust, so discrete-tick lag, the heading still settling within the thrust cone (R5) and the
rest-to-rest estimate can never carry it past the destination. The cost is about 5 % longer braking,
inside SC-002's 10 % allowance (worked through in [quickstart.md](./quickstart.md), check 4).

**Alternatives rejected**: `a′ = a` (no margin: a single late tick overshoots); a larger margin such
as 0.7 (safe but spends most of SC-002's allowance).

## R4 — Linear tail near the destination

**Decision**: Close in, the profile is capped at `k·d` with `k = 10 s⁻¹`.

**Rationale**: `√(2a′d)` has an infinite slope at `d = 0`, which in discrete time makes the last few
ticks chatter between thrust and coast. The linear cap turns the final approach into an exponential
settle with time constant 0.1 s (`k·dt ≈ 0.17`, comfortably stable at 60 Hz). It takes over below
`d = 2a′/k² = 3.6` units at the defaults. Feasibility is not an issue: at that junction full-thrust
braking stops the ship in 0.9 d (R3).

## R5 — Turn law, thrust cone and hold rule

**Decision**:
- **Target heading** `ψ = atan2(e)`. Heading error `δ = wrap(ψ − heading)` into (−π, π]; an exact π
  stays +π, so "exactly behind" always turns counter-clockwise (FR-012, Edge Cases).
- **Desired rate of turn** (see R11 for the shipped target and thrust rule) `ω* = sign(δ) · min(ωmax, √(2α|δ|), |δ|/dt)`, sent as
  `turn = ω*/ωmax`. The ship's own step (004 FR-008) then moves its rate towards `ω*` at `α`. The
  `√(2α|δ|)` term brakes the rotation in time; `|δ|/dt` lands the last tick without overshooting.
- **Thrust cone**: thrust only when `|δ| ≤ 0.1 rad` (≈ 5.7°), at
  `thrust = clamp((e · ĥ) / (a·dt), 0, 1)` — deadbeat: it removes the along-heading error in one
  tick when it can, and never pushes past it.
- **Hold rule**: when the ship faces against its motion (`ĥ · v < 0`), is still closing
  (`v · r̂ > 0`), and `e` points *forward* along `v` by less than half of `|v*|` — it is only slightly
  slower than the profile — it does not turn round. It holds the braking attitude (`ψ = heading of
  −v`) and coasts; the shrinking profile catches up within a few ticks.
- **Settled**: when `|e| ≤ 0.001` units/s, the input is neutral (no thrust, turn 0 — which stops any
  spin exactly, 004 FR-008).

**Rationale**: Without the hold rule, the final approach — where `e` alternates sign around zero —
would make the ship flip round to add a fraction of a unit per second and flip back, costing 3 s a
time. Half of `|v*|` keeps real re-accelerations (a new, farther order given while braking) working.
The settled threshold gives station-keeping a genuine rest state (SC-008).

**Alternatives rejected**: target heading straight from `e` with no hold (chatter above); a phase
state machine with explicit transition guards (more state, more cases, same behaviour).

## R6 — Phases are a classification of each tick, with two pieces of memory

**Decision**: The phase is computed from what the tick does:

1. **arrived** if within both tolerances, or if the previous phase was arrived and the ship is still
   within the position tolerance (the latch that makes station-keeping part of arrived, FR-009).
2. **braking** if it thrusts and the thrust opposes the velocity (`ĥ · v < 0`); **burning** if it
   thrusts otherwise.
3. **flipping** if it turns towards a target that opposes the velocity (`ψ̂ · v < 0`), unless the
   previous phase was braking (then it is an attitude correction and stays **braking**);
   **aligning** if it turns otherwise.
4. Coasting or holding: **braking** if facing against the velocity, else **burning**.

**Rest** (020, SKY-46): rules 2–4 treat a speed of at most `settleSpeed` (0.001 u/s) as rest, with no
direction, so never against the motion. Station keeping leaves up to that much velocity and calls it
settled, so the settle speed is the law's own "no motion". It is phase naming only: the hold rule's own
direction test is unchanged, so a flight the autopilot flies throughout has bit-identical inputs. The hold
rule also reads the previous phase, so after explicit-input ticks a phase named from rest can change a
later input (020 contracts/phase-rule.md).

The previous phase is the only memory; it is stored in the state (FR-014).

**Rationale**: FR-005 wants the phase re-evaluated every tick; the clarification allows repeats but
requires a forward-only sequence from rest. The braking latch in rule 3 is what stops a small lateral
correction during braking from reading as a second flip. No other memory is needed, so a copy of
the state reproduces the flight exactly (SKY-26).

## R7 — Where it lives and how `advance` changes

**Decision**:
- New file `Sources/SwiftSkySimulation/Autopilot.swift` with `MoveOrder`, `AutopilotPhase`,
  `ArrivalTolerances` and `Autopilot` (order, phase, tolerances); new `AutopilotLaw.swift` with the
  per-tick law, which needs `Darwin` for `atan2`, `cos`, `sin` (as `ShipMotion.swift` does).
- `SimulationState` gains `autopilot: Autopilot` and `mutating func setOrder(to:) -> Bool`
  (discardable result; `false` and no change for a non-finite destination, FR-002).
- `Simulation.advance(_:ticks:input: = .neutral)` becomes two overloads:
  `advance(_:ticks:)` — autopilot input per tick when there is an order, else neutral — and
  `advance(_:ticks:input:)` — explicit input for every tick, order untouched (FR-011, clarification).

**Rationale**: The frame loop's call `Simulation.advance(state, ticks:)` compiles unchanged and,
with no order ever given, behaves bit-for-bit as before (FR-011, SC-007). Existing 004 tests that
pass an explicit input keep their meaning.

**Alternatives rejected**: a separate `Autopilot` system outside the state (breaks FR-014 and
SKY-26's copy-and-run); making the input parameter optional (`input: ControlInput? = nil`) — works,
but two overloads say the two behaviours out loud.

## R8 — Tolerances and constants live in one place

**Decision**: `ArrivalTolerances.default` = 1 unit, 1 unit/s (sanitised like `ShipLimits`: negative
or non-finite → 0). The law's tuning constants (`a′` factor 0.9, `k` = 10 s⁻¹, cone 0.1 rad, hold
fraction 0.5, settle 0.001 u/s) are `static let`s in `AutopilotLaw.swift`, each documented with the
research entry behind it. They are not configurable (Principle V).

## R9 — Tests

**Decision**: New `Tests/SwiftSkySimulationTests/AutopilotTests.swift` with a small flight helper
that runs a state until arrival (or a tick cap) recording phases, maximum overshoot along the start
→ destination line, bearing sweep around the destination and destination passes. Suites mirror the
stories: arrival from rest (SC-001–003), moving starts (SC-004), re-orders (SC-006), read-out and
edge cases, station-keeping (SC-008), determinism (SC-005, using `StateBits`). The SC-002 reference
time is computed in the test from the ship's limits, as the spec defines it.

**Rationale**: Principle II; the grids of SC-001 and SC-004 are parameterised tests, so a failure
names its case.

## R10 — Performance evidence

**Decision**: Reuse 004's headless before/after benchmark (quickstart check 11) with an autopilot
flight instead of a fixed input, plus the structural argument: the law touches stored `Double`s only.

**Rationale**: Principle III requires before/after numbers for a hot-path change; the autopilot runs
on every tick once SKY-10/11 issue orders.

## R11 — What tuning changed during implementation (T011)

Flying the grid showed three defects in the law as first written; each was fixed inside the
contract's shape, and the contract now describes what shipped.

- **Aim at an acceleration, not at the velocity error.** Once the ship tracks the profile, the
  velocity error is tiny and its direction is dominated by fractions of a unit per second of lateral
  drift, so the target heading swung and the ship lost most of its braking thrust to wobble — and
  overshot by up to 8 units. The target is now `A = e/τ + feedforward`, with `τ = 1/15 s` and the
  feedforward the profile's own deceleration as the ship closes (`−(v·r̂)·ds/dd` along `r̂`). Thrust is
  `A·ĥ/a`. Lateral drift now tilts the heading by a degree or so instead of swinging it.
- **Turn time from the current rate.** The rest-to-rest estimate of R2 overestimates the remaining
  flip time badly for a ship already swinging round (0.25 s estimated vs 0.04 s real near the end), so
  the desired speed jumped as the flip finished. `turnTime(angle, rate:)` accounts for the current rate
  of turn (stop first if turning away; credit the stopping time if too fast to stop in time).
  `restToRestTurnTime` remains for SC-002's reference pilot.
- **Commitment and latches.** Mid-flip, a slightly optimistic desired speed made the ship turn back
  towards the destination for a tick. The hold rule now applies whenever the ship is committed to
  braking (facing against the motion, or already flipping or braking), and it also holds when `A`
  gives no decisive call to brake (`−A·v̂ < 0.05 a`), where its direction is meaningless. For the phase
  read-out, a correction turn mid-burn stays **burning**, as one mid-brake stays **braking**.

- **Hold only when closing straight in.** The moving-start grid (US2) showed a ship drifting mostly
  sideways, and latched as braking, flip-flopping between its braking attitude and the direction it
  needed, never thrusting. The hold rule now also requires the velocity to point within about 25° of
  the destination (`v·r̂ ≥ 0.9 |v|`); otherwise the ship always aims at `A`.

- **Station-keeping only cancels velocity.** As first written, the arrived ship kept tracking the
  profile towards the exact destination, which moved a resting ship that was already within tolerance
  — against the spec's "already there" edge case. While arrived, the desired velocity is now zero; a
  drift out of the position tolerance still resumes the manoeuvre (FR-009).

Measured at the default limits: 1,000 units ahead arrives in 5.4 s (bound 5.69 s), 1,000 units
behind in 6.9 s (bound 7.34 s), no overshoot.
