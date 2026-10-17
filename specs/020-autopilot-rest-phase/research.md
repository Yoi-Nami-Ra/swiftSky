# Research: A Re-order From Rest Starts in Aligning (020)

All findings below come from reading `Sources/SwiftSkySimulation/AutopilotLaw.swift` and from a throwaway
probe test run on 2026-10-18 (deleted afterwards, nothing committed). The probe flew from launch to three
destinations, kept station for 600 ticks, and then gave a new order 1,000 units away, in two directions
measured from the leftover velocity: 180° (straight behind) and 120°.

## R1 — The bug has two forms, and both are reproducible

**Finding**: After 600 ticks of station keeping, the leftover velocity is non-zero and below the settle speed
on all three flights. For the flight to (1000, 0) it is `(0.0009974385557949639, -3.859627003769714e-05)`,
speed 0.000998. The ship faces almost exactly against it (heading 3.103 rad), because it last braked.

- **Order straight behind the velocity (180°)**: the ship already faces the burn direction, so the first tick
  thrusts. `ĥ·v < 0` names it `braking`. The phases are `braking, burning, flipping, braking, arrived`, so the
  phase goes backwards once.
- **Order at 120° from the velocity**: the ship must turn about 60°, past the thrust cone, towards a target
  that opposes the velocity. The flip rule names it `flipping`. The phases are `flipping, braking, burning,
  flipping, braking, arrived`. This is the form seen on the overlay (SKY-34 check 5).

**Decision**: The reproducing test flies both directions. The 120° order pins FR-005 (first phase is
`aligning`). The 180° order pins scenario 3 (first thrust tick is `burning`). Each also pins forward-only
phases (FR-006).

## R2 — The fix: a `atRest` flag that only the phase naming reads

**Decision**: In `evaluate`, compute `atRest = speed <= settleSpeed` from the speed step 1 already has.
Derive `namedAgainstMotion = facingAgainstMotion && !atRest` and use it in the three places the phase is
named from `ĥ·v`: the settled return (step 5), the thrusting rule and the coasting rule (step 8). The
turning rule's guard becomes `!atRest && target·v < 0`. At rest that guard is false, so the rule takes its
`burning`-if-burning-else-`aligning` branch and never reaches the braking latch (spec clarification 1).
`facingAgainstMotion` itself stays as it is, because step 6's hold rule reads it (`committedToBraking`).

**Rationale**: This is four lines of change and adds no state, no allocation and no division (006 FR-013,
FR-015). It also keeps the law pure, so every run gives the same bits (006 FR-012). The settle speed is the
right threshold: station keeping already treats an error that small as nothing to correct, so a velocity
that small is the law's own idea of "no motion".

**Alternatives rejected**: zeroing the velocity on arrival, because the autopilot writes only inputs (006
FR-004). A threshold tied to `ArrivalTolerances.speed` (1 u/s), because it is too coarse and would rename
real mid-flight braking. Changing `facingAgainstMotion` itself, because that would feed the hold rule and
could change inputs (FR-004).

## R3 — The inputs do not change: checked by the probe, explained by the hold rule

**Finding**: The probe fingerprinted every tick's ship-state bits (FNV-1a, 64-bit) over all six re-order
flights, once with the current law and once with the R2 change applied. All six fingerprints are identical
before and after: `14098605131384196193`, `243082615205163470`, `229135446958481898`,
`8818756782525322908`, `12908878097606746420` and `6252949810781141796`. The phases changed as intended:
`burning, flipping, braking, arrived` and `aligning, burning, flipping, braking, arrived`.

**Why**: The renamed phase reaches the inputs only through `committedToBraking` in the hold rule. The hold
rule also needs `closingSpeed > 0.9·speed`. A ship whose leftover velocity points away from the destination
has negative closing speed. Once the burn reverses the velocity, the ship is far short of the desired speed,
so `forwardShortfall < 0.5·desired` fails. Either way, no hold engages and the input is the same.

**Decision**: FR-007's test pins this for the reproducing flights. For each tick it folds the bits of the
control input (from `Autopilot.control(for:)` on a copy of the state) and of the resulting ship into one
FNV-1a fingerprint. It asserts that fingerprint and the tick count, both recorded from the current law
**before** the fix is applied. One `UInt64` per flight stays readable. Thousands of per-tick constants would
not, and a fingerprint still fails on any single flipped bit. The phase is left out of the fingerprint,
because it is the one thing allowed to change.

**Alternatives rejected**: keeping a copy of the old law in the tests to compare against. It duplicates
about 100 lines and drifts. Asserting per-tick constants: too long to read or review.

## R4 — Test setup and where the tests live

**Decision**: Add a new `@Suite` file, `Tests/SwiftSkySimulationTests/AutopilotRestPhaseTests.swift`. It
reuses the `fly`, `Flight`, `speed` and `bits` helpers (module-internal test helpers in
`AutopilotTests.swift` and `StateBits.swift`). The setup flies from launch (`Ship()`) to (1000, 0) with
`Simulation.advance(_:ticks:)` until arrival, then keeps station for 600 ticks. It asserts the leftover
velocity's x and y bit patterns (recorded constants, FR-005) and that its speed is greater than 0 and at
most the settle speed. Destinations are computed from the pinned velocity's direction (180° and 120°), 1,000
units from the ship. The boundary test (FR-005a) builds a state with `SimulationState.setOrder(to:)` and calls the public `Autopilot.control(for:)` on hand-built `Ship` values, then reads `phase`: speed exactly
`settleSpeed` and the next representable `Double` above it (`settleSpeed.nextUp`), pointing away from a
destination that needs a turn of more than the thrust cone.

**Rationale**: A separate file keeps 006's `AutopilotTests.swift` unchanged (FR-008) and names the feature.
`evaluate` is internal and reachable through `@testable import`, as 006's tests already use it.

## R5 — Documentation

**Decision**: Add a "Rest" paragraph to 006 `research.md` R6 (rules 2–4 name a speed of at most
`settleSpeed` as rest: no direction, so never "against the motion"; SKY-46). Add the same clause to 006
`contracts/autopilot.md` step 8. 006 `spec.md` is not changed (spec clarification 5). In `CLAUDE.md`, add
one sentence to the `AutopilotLaw.swift` entry.
