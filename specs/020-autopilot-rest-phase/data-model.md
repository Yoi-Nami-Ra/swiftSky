# Data Model: A Re-order From Rest Starts in Aligning (020)

No stored data changes. `SimulationState`, `Autopilot`, `AutopilotPhase` and `Ship` keep their fields, and
`bits(_:)` keeps its layout.

## Per-tick values in `Autopilot.evaluate` (transient, not stored)

| Value | Definition | Read by |
| --- | --- | --- |
| `speed` | `|v|` of the ship the tick is evaluated from (existing) | arrival, `atRest` |
| `facingAgainstMotion` | `ĥ·v < 0` (existing) | step 6 hold rule (**unchanged**), `namedAgainstMotion` |
| `atRest` (new) | `speed <= settleSpeed` (0.001 u/s) | phase naming only |
| `namedAgainstMotion` (new) | `facingAgainstMotion && !atRest` | settled return, thrusting and coasting rules |

## Phase naming (006 research R6, with 020's rest rule)

| Tick does | Not at rest (unchanged) | At rest (new) |
| --- | --- | --- |
| Arrived (step 2) | arrived | arrived (unchanged) |
| Settled, neutral input | braking if `ĥ·v < 0`, else burning | burning |
| Thrusts | braking if `ĥ·v < 0`, else burning | burning |
| Turns, target opposes `v` | braking if previous braking, else flipping | — (no direction: never opposes) |
| Turns, any other target | burning if previous burning, else aligning | burning if previous burning, else aligning |
| Coasts or holds | braking if `ĥ·v < 0`, else burning | burning |

The previous phase is stored as before. Under the hold rule it feeds the next tick's input, which R3 and
the fingerprint tests show does not change for a re-order the autopilot flies. Explicit-input ticks keep
the stored phase, so after them it can (contracts/phase-rule.md).
