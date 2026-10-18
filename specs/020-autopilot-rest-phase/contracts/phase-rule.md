# Contract: the phase rule with rest (amends 006 contracts/autopilot.md step 8)

The public API is unchanged: `Autopilot.control(for:) -> ControlInput` and `Autopilot.phase`. This file
states what 006's step 8 says after 020. The implementation copies the wording into
`specs/006-ship-autopilot/contracts/autopilot.md`.

8. **Phase** (unless arrived by step 2). **Rest**: a ship whose speed is at most `settle` (0.001 u/s) is at
   rest, and its velocity has no direction for naming the phase (020):
   - thrusting → **braking** if `ĥ·v < 0` and not at rest, else **burning**;
   - turning (`|δ| > cone`) towards a target opposing the velocity (`target·v < 0`, never at rest) →
     **braking** if the previous phase is braking, else **flipping**; towards any other target →
     **burning** if the previous phase is burning, else **aligning**;
   - otherwise (coasting / holding / settled) → **braking** if `ĥ·v < 0` and not at rest, else **burning**.

Step 5's settled return names its phase by the last bullet. Step 6's hold rule still reads `ĥ·v < 0`
without the rest clause. It also reads the previous phase, which this rule can rename.

**Guarantees**: While the autopilot flies every tick from the order on, `control(for:)` returns the same
`ControlInput` bits as before 020; only `phase` differs, on ticks evaluated from a ship at rest and on the
ticks that phase latches into. The exception is a flight interrupted by explicit-input ticks (006 FR-011),
which keep the stored phase: a phase named from rest can then reach the hold rule on a later tick, when
the ship is moving, and change its input. `AutopilotRestPhaseTests` pins both.
