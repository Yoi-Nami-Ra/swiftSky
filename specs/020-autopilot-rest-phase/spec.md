# Feature Specification: A Re-order From Rest Starts in Aligning

**Feature Branch**: `claude/sky-46-autopilot-rest-phase-0b0e2c` (spec number 020)

**Created**: 2026-10-18

**Status**: Implemented

**Input**: User description: "SKY-46 — Autopilot starts a re-order from rest in flipping" (`.tickets/46.yaml`).
Seen while verifying SKY-34 (specs/015-debug-overlay-ship-order/quickstart.md, check 5): after the ship had
arrived and was keeping station, a new order made the debug overlay read `order   flipping` at once, with
`vel x 0.00 y 0.00`. 006 FR-005 says that from rest the phases only move forward, so the first phase should
be `aligning`.

## Background

Station keeping stops correcting once the velocity error is at most the autopilot's settle speed
(0.001 world units per second, 006 research R5), so a ship keeping station can be left with a velocity of up
to that size. It is far below what the overlay shows (0.005 u/s) and below anything a player could see. On a
new order, the phase rules of 006 research R6 look only at the *direction* of the velocity: a leftover
velocity pointing away from the new destination reads as "turning to face against the motion", which rule 3
calls `flipping`, and the same direction test can call the first thrust ticks `braking` (rule 2). The ship
flies the order correctly; only the phase it reports is wrong.

Decided in the ticket: a speed of at most the settle speed counts as rest when the phase is named. Rejected:
zeroing the velocity on arrival (the autopilot affects the ship only through its control input, and the
motion stays Newtonian, 004, 006 FR-004), and a threshold tied to the arrival speed tolerance (1 u/s, far too
coarse for naming a phase mid-flight).

## Clarifications

### Session 2026-10-18

- Q: At rest, which of the turning rule's latches applies — braking's or burning's? → A: A velocity at rest has no direction, so it never opposes the target: the turning rule takes its "any other target" branch (burning if the previous phase was burning, else aligning), and the braking latch is not reached _(assumed — 006 contracts/autopilot.md step 8; Sources/SwiftSkySimulation/AutopilotLaw.swift:164)_
- Q: Which speed decides rest — before or after the tick? → A: The speed of the ship state the tick is evaluated from, the same speed the law already computes for the tick _(assumed — Sources/SwiftSkySimulation/AutopilotLaw.swift:70)_
- Q: Is the boundary pinned by its own test, besides the flown re-order? → A: Yes: a single-tick check with a velocity exactly at the settle speed pointing away from the destination (named as rest) and one just above it (named from its direction, as today) _(assumed — spec Edge Cases; constitution v1.1.0 Test Coverage Discipline)_
- Q: What happens if the bit-identical inputs test shows a changed input? → A: Implementation stops and reports it to the user; neither the inputs nor the test's expected values are changed to make it pass. Reading the law, no input should change: the hold rule needs a closing speed above 0.9 of the speed, which a ship moving away from the destination does not have, and a ship that has just started towards it is far short of the desired speed _(assumed — ticket SKY-46 scope 2; AutopilotLaw.swift:128–134)_
- Q: Does 006 FR-005's text change? → A: No. The code is brought into line with it; only 006 research R6 and contracts/autopilot.md step 8 gain the rest rule _(assumed — ticket SKY-46 scope 3)_
- Q: How is "moves forward only" checked for the re-order? → A: As 006's flight tests do: each phase's rank in aligning → burning → flipping → braking → arrived never decreases and no phase appears twice _(assumed — Tests/SwiftSkySimulationTests/AutopilotTests.swift:57–59)_

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A new order after arrival reads as a fresh start (Priority: P1)

The player orders the ship somewhere, it arrives and holds still. The player then orders it to a point
behind it. The phase the game reports (the debug overlay's order line now; anything that reads the phase
later) starts at `aligning` (skipped when the ship already faces the burn direction), then `burning`, `flipping`, `braking` and `arrived`, as it does for a first
order from rest — never `flipping` or `braking` before the ship has gone anywhere.

**Why this priority**: It is the whole bug. A phase that jumps to `flipping` with the ship visibly at rest
breaks 006 FR-005 and makes the overlay misleading while verifying flights.

**Independent Test**: In the logic layer, fly an order to arrival, keep station until the leftover velocity
is non-zero and points away from the next destination, give a new order to a point behind that velocity, and
record the phase of every tick until arrival.

**Acceptance Scenarios**:

1. **Given** a ship keeping station after an order, with a leftover velocity that is non-zero, at most the
   settle speed, and pointing away from the next destination, **When** a new order to that destination is
   given and the first tick is flown, **Then** the phase is `aligning` (it is `flipping` today), or `burning` when the ship already faces the burn
   direction (it is `braking` today).
2. **Given** the same re-order, **When** it is flown to arrival, **Then** the phases move forward only
   through aligning → burning → flipping → braking → arrived (aligning skipped if the ship already faces
   the burn direction), with no phase repeated after it has been left.
3. **Given** the same re-order, **When** the ship first thrusts while its leftover velocity still points
   away from the destination, **Then** the phase is `burning`, not `braking`.

---

### User Story 2 - The flight itself does not change (Priority: P1)

The fix changes only the phase name. The control input of every tick, and so every position, velocity,
heading and turn rate the ship passes through, is exactly what it was before, for the re-order above and
for every flight 006 and 010 already pin.

**Why this priority**: The phase is not only a label: the autopilot reads the previous tick's phase when it
decides whether to keep its braking attitude (006 research R5, the hold rule). Renaming a phase could
therefore change a later tick's input. The ticket's promise — only the reported phase is wrong — has to be
proven, not assumed, and the planned path (010) must not move.

**Independent Test**: Fly the re-order of story 1 with the fixed law and compare every tick's control input
and resulting ship state, bit for bit, with the values the law produced before the fix.

**Acceptance Scenarios**:

1. **Given** the re-order of story 1, **When** it is flown to arrival with the fixed law, **Then** every
   tick's control input (thrust and turn) and every resulting ship state are bit-identical to those of the
   law before the fix, recorded in the test.
2. **Given** every existing 006 autopilot test and 010 planned-path test, **When** they run after the fix,
   **Then** they pass unchanged, with no expected value edited.

---

### Edge Cases

- **Speed exactly at the settle speed**: counts as rest (the bound is inclusive, matching the station
  keeping rule, which stops correcting at an error of at most the settle speed).
- **Speed just above the settle speed**: the phase is named from the velocity's direction as today; the ship
  is genuinely moving and 006 FR-005 allows repeats from a moving start.
- **Exactly zero velocity**: unchanged — it is already treated as rest by the existing rules.
- **Leftover velocity pointing towards the new destination**: the first phase is `aligning` (or `burning`
  if the ship already faces the burn direction), as today.
- **Leftover velocity pointing sideways**: the same bug — the order started in `flipping` — and the same
  fix: it starts `aligning` (pinned at ±90°).
- **New order while still arrived at the old destination's tolerance, nothing to fly**: the arrived rules are
  unchanged; this feature touches only how a non-arrived tick is named.
- **Mid-flight ticks**: during a real flight the speed is far above the settle speed except at the very
  first ticks from rest and the last ticks of the settle, so no mid-flight phase changes.
- **The settled return** (the tick where the velocity error is already within the settle speed, so the
  input is neutral): its burning/braking choice follows the same rest rule.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When naming a tick's phase, the autopilot MUST treat the ship as at rest — its velocity having
  no direction — when its speed, in the state the tick is evaluated from, is at most the settle speed
  (0.001 u/s, 006 research R5).
- **FR-002**: A ship at rest by FR-001 MUST NOT be named `flipping` when it turns (it is `aligning`, or
  `burning` if the previous phase was `burning`, the existing mid-burn latch), and MUST NOT be named
  `braking` when it thrusts or coasts (it is `burning`). Its velocity never opposes a target, so the braking
  latch of 006 research R6 rule 3 is not reached at rest.
- **FR-003**: The rest rule MUST apply to every place the phase is named from the velocity's direction:
  the turning rule, the thrusting rule, the coasting rule and the settled (neutral-input) rule. It MUST NOT
  apply to the arrived rule, which does not use the velocity's direction.
- **FR-004**: The control input of every tick the autopilot flies from the order on MUST be unchanged, bit
  for bit, by this feature — including through the hold rule, which reads the previous tick's phase.
  Explicit-input ticks (006 FR-011) keep the stored phase, so after them a phase named from rest can change
  a later input through the hold rule; that exception was found in review and accepted, and is pinned by a
  test. If a test shows a changed input, the work
  MUST stop and be reported; neither the inputs nor the expected values may be changed to make it pass.
- **FR-005**: A logic-layer test MUST reproduce the bug: fly an order to arrival, keep station until the
  leftover velocity is non-zero and points away from the next destination, pin that velocity's bits in the
  test (so the setup cannot drift silently to an exact rest), give a new order behind it, and check that the
  first phase is `aligning`. It MUST fail before the fix and pass after it.
- **FR-005a**: A single-tick test MUST pin the boundary: a velocity of exactly the settle speed pointing away
  from the destination is named as rest (`aligning` when turning), and one just above it is named from its
  direction (`flipping`), as today.
- **FR-006**: A test MUST check that the phases of that re-order, flown to arrival, move forward only
  (006 FR-005: each phase's rank never decreases and none appears twice), and that the first thrust tick is
  `burning`.
- **FR-007**: A test MUST pin, bit for bit, the control input of every tick and the resulting ship state of
  that re-order, with the expected values taken from the law before the fix.
- **FR-008**: All existing 006 and 010 tests MUST pass with no change to their expected values.
- **FR-009**: 006 research R6 MUST record the rest threshold and why it is the settle speed, and 006
  `contracts/autopilot.md` step 8 MUST state it. 006 FR-005's text is unchanged: the law is brought into
  line with it.
- **FR-010**: The fix MUST keep the law's existing guarantees: constant work and no allocation per tick
  (006 FR-015), a finite input for any finite ship (006 FR-013), and the same bits on every run (006 FR-012).

### Key Entities

- **Phase**: the autopilot's report of what a tick does (aligning, burning, flipping, braking, arrived),
  stored as the previous phase for the next tick (006 FR-005, research R6).
- **Settle speed**: the velocity error below which the autopilot's input is neutral (0.001 u/s); this
  feature reuses it as the speed below which a velocity has no direction for naming the phase.
- **Leftover velocity**: what station keeping leaves on the ship, at most the settle speed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A re-order from station keeping starts in `aligning` (or `burning` when the ship already faces
  the burn direction) and moves forward only through the phases, every time, in the reproducing tests.
- **SC-002**: 0 bits differ in any tick's control input or ship state between the law before and after the
  fix, over the whole re-order flight.
- **SC-003**: 0 existing 006 or 010 tests change their expected values, and all pass.
- **SC-004**: The project's single verification command passes.

## Assumptions

- The leftover velocity after station keeping is never larger than the settle speed; drift that builds up
  over a long hold and lets go of the arrival latch is out of scope (FR-009 of 006 already allows the order
  to be flown again then).
- What the debug overlay and the order overlay show is unchanged in form; they only read the phase
  (SKY-34, SKY-30) and need no work.
- The planned path holds positions, not phases, so its prediction (010, SKY-26) does not change, which
  FR-004 and FR-008 confirm.
- The expected inputs and states for FR-007 are recorded from the current law before the fix is applied.
- The work is reviewed as pull request 3 before it merges.
