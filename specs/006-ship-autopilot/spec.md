# Feature Specification: Ship Autopilot — Turn, Burn, Flip and Brake

**Feature Branch**: `006-ship-autopilot`

**Created**: 2026-10-01

**Status**: Draft

**Input**: User description: "SKY-25 — Autopilot: turn, burn, flip and brake" (`.tickets/25.yaml`).
Logic layer. Given the ship (SKY-24) and a move order (a destination in world space), produce the
control input each tick that gets the ship there and stopped as fast as its limits allow: rotate to
face the burn direction, accelerate, turn around, then decelerate to arrive at rest. Must handle:
starting while already moving (a new order mid-flight replaces the old one) — the burn direction
accounts for current velocity, so sideways drift is cancelled rather than carried into an orbit;
rotation time — the flip takes time, so the flip point comes earlier than the halfway mark; arrival
— within a position and speed tolerance the order completes and the ship holds still. Exposes its
current phase (aligning, burning, flipping, braking, arrived) for the debug overlay (SKY-29) and the
path prediction (SKY-26). Done when tests show: from rest and from arbitrary initial velocities it
arrives within tolerance and at rest, without overshooting past the tolerance; a new order mid-flight
is followed; results are deterministic. Default tolerances: 1 unit and 1 unit/s.

## Overview

The first gameplay slice (SKY-22) is a ship that the player sends somewhere with a click or tap, and
that gets there as fast as its physics allow. SKY-24 gave the simulation that ship: a body in empty
space that can only push forward along its heading, turn at a limited rate, and never slows down on
its own. SKY-23 fixed the world it lives in. What is missing is the pilot: something that, told
"go there", works out each tick how hard to thrust and which way to turn.

This feature adds that pilot, the **autopilot**. Given a **move order** — a destination in the world —
it flies the classic manoeuvre of a ship that can only push forward:

1. **Aligning**: turn to face the direction it needs to push.
2. **Burning**: thrust towards the destination.
3. **Flipping**: turn around, so the engine points the way it is travelling.
4. **Braking**: thrust against the motion to come to a stop on the destination.
5. **Arrived**: close enough and slow enough; the order is complete and the ship holds still.

Because turning around takes time, the ship must start the flip before the halfway point, or it will
still be turning when it should already be braking. Because the ship may already be moving when the
order arrives — including sideways to the destination — the direction it pushes is chosen to cancel
the unwanted part of its motion as well as to head for the destination, so it flies to the point
instead of swinging round it.

Nothing new is visible. The running app does not yet issue move orders (that is SKY-10 and SKY-11),
so the ship stays at rest where it starts and the surface looks exactly as it does today. The value
of this feature is a tested pilot that the path prediction (SKY-26), the order overlay (SKY-30) and
the input tickets build on.

Out of scope: issuing orders from a click or tap (SKY-10, SKY-11), predicting or drawing the path
(SKY-26, SKY-30), drawing the ship (SKY-27), the order lines of the debug overlay (SKY-29 follow-up),
queues or chains of orders, following a moving target, obstacle avoidance, more than one ship, and
any change to the ship's motion rule or its default limits.

### Relationship to earlier specs

- **Unchanged and still absolute**: 004's motion rule (FR-008, FR-009) and its control-input ranges
  (FR-006, FR-007) — the autopilot only chooses inputs, it never moves the ship any other way; 001
  FR-015 (no global mutable state), FR-033 (no clock in the simulation), SC-013 (byte-identical
  results across ten runs), FR-020 / FR-021f (no per-frame allocation), the 60 Hz fixed tick (FR-021a)
  and every layer-boundary rule.
- **Extended**:
  - The simulation state (001 FR-012, 004 FR-001) now also carries the current move order, if any,
    and whatever the autopilot needs to remember between ticks, so that a copy of the state can be
    run forward on its own (FR-014, needed by SKY-26).
  - 004 FR-011 said every tick of one advance receives the same control input. That stays true when
    an input is supplied explicitly. When the ship is under an order, each tick instead receives the
    input the autopilot chooses *for that tick* (FR-011), and advancing n ticks in one call still
    equals advancing one tick n times.
- **Unaffected**: 005's camera and scale, and 003's debug overlay, which shows the same lines as
  before. Its order lines are follow-up work that this feature unblocks.

## Clarifications

### Session 2026-10-01

- Q: How does the ship hold still after arrival, given arrival allows up to 1 unit/s of leftover
  speed? → A: Station-keeping: while arrived, the autopilot cancels the remaining velocity; if the
  ship ever drifts outside the position tolerance, the manoeuvre resumes and the phase leaves
  arrived until it is back (FR-009).
- Q: Can the phase sequence go backwards? → A: Yes. The phase is re-evaluated every tick from the
  ship's state. From rest it only moves forward; from a moving start, a turn-back or a station-keeping
  correction, phases may repeat (FR-005).
- Q: What happens to an active order when the simulation is advanced with an explicit control input?
  → A: The explicit input drives those ticks and the order is kept untouched; the autopilot resumes
  from the resulting state on the next advance without an explicit input (FR-011).
- Q: Does holding still include not rotating? → A: Yes. While arrived, the autopilot's turn input
  brings the rate of turn to zero. Arrival itself does not wait for the spin to stop (FR-009).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers building swiftSky and the tickets that build on the
autopilot (SKY-10, SKY-11, SKY-26, SKY-29, SKY-30). Players see nothing new until SKY-10 and SKY-11
let them issue orders.

### User Story 1 - Send a resting ship somewhere and have it stop there (Priority: P1)

A developer gives a ship sitting at rest a move order to a point some distance away, in any direction,
and runs the simulation. The ship turns to face the destination, burns towards it, flips around
before the halfway point, brakes, and comes to rest on the destination, within one unit of it and
moving slower than one unit per second. It never sails past the destination by more than a unit on
the way in, and it gets there about as quickly as the ship's limits allow.

**Why this priority**: This is the whole point of the feature and the heart of the first playable
slice. Everything else (starting while moving, changing orders) is a refinement of it.

**Independent Test**: Run the project's single test command. The arrival tests give resting ships
orders at a range of distances and directions, run the simulation until the order completes, and
check the arrival position, speed, overshoot and time taken.

**Acceptance Scenarios**:

1. **Given** a ship at rest facing heading zero, **When** it is ordered to a point 1,000 units along
   heading zero, **Then** it passes through burning, flipping and braking and ends in the arrived
   phase within 1 unit of the destination and slower than 1 unit per second (SC-001).
2. **Given** a ship at rest, **When** it is ordered to a destination behind it or to one side,
   **Then** it first turns to face the burn direction (aligning) before thrusting, and still arrives
   within tolerance.
3. **Given** a ship at rest, **When** it is ordered anywhere, **Then** at no tick is it more than
   1 unit beyond the destination, measured along the direction from its starting point to the
   destination (SC-003).
4. **Given** a ship at rest facing the destination, **When** it flies the order, **Then** the flip
   starts before the ship has covered half the distance, and it arrives no later than the time bound
   of SC-002.
5. **Given** a ship that has arrived, **When** the simulation keeps running with no new order,
   **Then** the phase stays arrived and the ship stays within the position tolerance of the
   destination (FR-009).

---

### User Story 2 - Send a moving ship somewhere without it swinging round the target (Priority: P2)

A developer gives an order to a ship that is already moving — towards the destination, away from it,
or across it — and runs the simulation. The ship picks a burn direction that cancels the part of its
motion it does not want while heading for the destination, so it flies to the point and stops there
rather than circling it.

**Why this priority**: A ship is rarely at rest when the player gives it a new order, and a pilot
that only works from rest would orbit or overshoot in real play. It comes after story 1 because it
refines the same manoeuvre.

**Independent Test**: Run the single test command. The moving-start tests give orders to ships with
a spread of initial speeds and directions and check that every one arrives within tolerance, within
the time limit, without circling the destination.

**Acceptance Scenarios**:

1. **Given** a ship moving at speed directly across the line to the destination, **When** it is
   ordered there, **Then** it cancels the sideways motion and arrives within tolerance, without
   sweeping a full turn around the destination (SC-004).
2. **Given** a ship moving fast straight at a destination that is too close to stop in time, **When**
   it is ordered there, **Then** it passes the destination, turns back, and arrives within
   tolerance; it passes the destination at most once more on the way back (SC-004).
3. **Given** a ship moving directly away from the destination, **When** it is ordered there,
   **Then** it brakes, turns back and arrives within tolerance.
4. **Given** a ship whose destination is its current position but which is still moving, **When**
   it is ordered there, **Then** it comes back and stops within tolerance of that point.

---

### User Story 3 - Change the order mid-flight (Priority: P3)

A developer gives a ship an order and, part way through — while it is aligning, burning, flipping or
braking — gives it a different one. The ship drops the first order at once and flies the second,
starting from wherever it is and however it is moving.

**Why this priority**: The player will change their mind; SKY-10 and SKY-11 issue a new order with
every click. It is third because, once story 2 works, it adds only the rule that the newest order
wins.

**Independent Test**: Run the single test command. The re-order tests interrupt an order in each
phase with a new destination and check that the ship arrives at the new one, not the old.

**Acceptance Scenarios**:

1. **Given** a ship in any phase of an order, **When** a new order is given, **Then** from the very
   next tick the autopilot flies to the new destination, and the ship arrives there within tolerance.
2. **Given** a ship that has arrived, **When** a new order is given, **Then** it leaves the arrived
   phase and flies to the new destination.
3. **Given** a ship under an order, **When** it is given an order to the same destination again,
   **Then** it carries on to that destination and still arrives within tolerance.

---

### User Story 4 - Watch what the autopilot is doing (Priority: P4)

A developer adding the order lines to the debug overlay (SKY-29) or computing the predicted path
(SKY-26) needs to read, from the simulation state alone, whether there is an order, where it goes,
how far is left, and which phase the autopilot is in.

**Why this priority**: The downstream tickets depend on it, but it is a read-out of stories 1–3
rather than behaviour of its own.

**Independent Test**: Run the single test command. The tests check the reported phase and order at
known points in a flight.

**Acceptance Scenarios**:

1. **Given** a state with no order ever given, **When** it is read, **Then** it reports no order and
   no phase, and the ship receives the neutral input.
2. **Given** a ship flying an order from rest, **When** the phase is read on every tick, **Then** it
   goes through aligning (only if the ship was not already facing the burn direction), burning,
   flipping, braking and arrived, in that order.
3. **Given** a ship under an order, **When** the state is read, **Then** it reports the destination
   and the distance remaining.

---

### User Story 5 - Every run is reproducible, and the app is unchanged (Priority: P5)

A developer replays the same orders from the same starting state and gets bit-for-bit the same
flight, whether the simulation was advanced one tick at a time or several ticks per frame. And the
running app, with no orders given, looks and costs exactly what it did before.

**Why this priority**: Determinism is what makes the autopilot testable and what lets SKY-26's
prediction match the real flight. It is last because it is a property of stories 1–4.

**Independent Test**: Run the single test command for determinism; run `./Scripts/verify.sh`, launch
a Debug build on both platforms, and repeat the allocation check used by 004 SC-005.

**Acceptance Scenarios**:

1. **Given** a fixed starting state and a fixed sequence of orders, **When** it is run ten times,
   **Then** the ten final states are byte-identical (SC-005).
2. **Given** a ship under an order, **When** it is advanced n ticks in one call and, separately, one
   tick at a time n times, **Then** the results are byte-identical (FR-011).
3. **Given** the app built with this feature, **When** it runs on both platforms, **Then** what it
   draws is unchanged and it performs no per-frame allocation (SC-007).

### Edge Cases

- **No order**: the ship receives the neutral input and nothing changes, exactly as before this
  feature (FR-010).
- **Already there**: an order to the ship's current position while it is at rest (within both
  tolerances) completes at once: the phase goes straight to arrived and the ship does not move.
- **Very short trip**: a destination closer than the ship can accelerate towards and still flip and
  stop — the autopilot still arrives within tolerance, burning only as long as it can afford.
- **Too close to stop**: a ship moving fast at a nearby destination cannot avoid passing it. That
  pass is not an overshoot failure; it turns back and arrives, with no repeated back-and-forth
  (story 2, SC-004).
- **Exactly behind**: when the burn direction is exactly opposite the heading, the turn direction is
  chosen by a fixed rule, never by chance, so runs stay reproducible (FR-012).
- **Non-finite destination**: an order whose destination is not a finite point is refused, and the
  state (including any current order) is left unchanged (FR-002).
- **Far destination**: destinations far from the origin (up to 10⁶ units away) are flown and arrived
  at within tolerance like near ones; the world has no edges (005).
- **A limit of zero**: a ship that cannot thrust or cannot turn cannot complete most orders. That is
  not an error: the autopilot keeps producing valid inputs, the ship's state stays finite, and the
  order simply stays in progress (FR-013).
- **Catch-up after a stall**: when one frame advances several ticks, the autopilot chooses a fresh
  input for each of them (FR-011).

## Requirements *(mandatory)*

### Functional Requirements

**Move orders**

- **FR-001**: A move order MUST consist of a destination: a point in the world plane, in world units.
- **FR-002**: It MUST be possible to give the ship a move order, and to do so at any time. A new order
  MUST replace the current one, if any, completely. An order whose destination is not finite MUST be
  refused, leaving the state unchanged.
- **FR-003**: The simulation state MUST report the current order, if any, and while there is one, the
  autopilot's current phase and the distance from the ship to the destination.

**The manoeuvre**

- **FR-004**: While there is an order, the autopilot MUST produce, for every tick, a control input
  within the ranges of 004 FR-006, and only through that input affect the ship (004's motion rule is
  unchanged).
- **FR-005**: The autopilot MUST fly the order in phases, and report which one it is in:
  **aligning** (turning to face the burn direction, not yet thrusting), **burning** (thrusting to
  build the velocity that carries the ship to the destination), **flipping** (turning to face against
  the direction of travel), **braking** (thrusting to lose speed and stop at the destination) and
  **arrived** (the order is complete). The phase MUST be re-evaluated every tick from the ship's
  state and the order. From rest, the phases MUST only move forward through that list (aligning is
  skipped when the ship already faces the burn direction). From a moving start, when the ship must
  turn back, or when station-keeping has to correct a drift, phases MAY repeat.
- **FR-006**: The burn direction MUST account for the ship's current velocity: it MUST aim to change
  the velocity the ship has into the velocity it needs to reach the destination, so that motion
  across the line to the destination is cancelled rather than carried into an orbit.
- **FR-007**: The autopilot MUST account for the time the ship needs to turn: the flip MUST begin
  early enough that the ship finishes turning and can still brake to a stop at the destination
  within its thrust limit — which, from rest, is before the halfway point.
- **FR-008**: The autopilot MUST get the ship to the destination and stopped about as fast as the
  ship's limits allow, within the time bound of SC-002.

**Arrival**

- **FR-009**: The order MUST complete — the phase becomes arrived — on the first tick on which the
  ship is within the position tolerance of the destination and its speed is below the speed
  tolerance. Once arrived, the ship MUST hold still at the destination (station-keeping): the
  autopilot MUST cancel any remaining velocity and bring the rate of turn to zero, and the ship MUST
  stay within the position tolerance for as long as no new order is given. Should it nevertheless
  drift outside the position tolerance, the manoeuvre MUST resume (the phase leaves arrived) and
  complete again as above. Arrival does not wait for the rate of turn to reach zero.
- **FR-010**: The default tolerances MUST be 1 world unit of position and 1 world unit per second of
  speed, written in one place. The autopilot MUST be usable with other tolerances (for tests and later
  tuning); a negative or non-finite tolerance MUST be treated as zero.

**The simulation**

- **FR-011**: When the ship has an order and the simulation is advanced without an explicit control
  input, each tick MUST be driven by the input the autopilot chooses for that tick, from the state at
  the start of that tick. Advancing n ticks in one call MUST give byte-identical results to advancing
  one tick n times. With no order, advancing MUST behave exactly as before this feature (the neutral
  input). Advancing with an explicit control input MUST keep 004's behaviour: that input drives every
  one of those ticks, and the order MUST be kept untouched, so the autopilot resumes from the
  resulting ship state on the next advance without an explicit input.
- **FR-012**: The autopilot MUST be pure and deterministic, like the rest of the logic layer: no
  clock, no randomness, no I/O and no shared state (001 FR-015, FR-033, 004 FR-012). Every choice,
  including ties such as which way to turn when the burn direction is exactly behind, MUST follow a
  fixed rule. Identical starting state and identical orders MUST give byte-identical results.
- **FR-013**: The autopilot MUST never produce an input that makes the ship's state non-finite, for
  any finite ship state, any limits (including zero) and any accepted order.
- **FR-014**: Everything the autopilot needs to choose its next input MUST be held in the simulation
  state, so that a copy of the state advanced on its own flies exactly the same path as the original
  (this is what SKY-26's prediction relies on).

**Purity and cost**

- **FR-015**: Choosing a tick's input MUST NOT allocate memory, and MUST take a bounded amount of work
  that does not grow with the distance or time remaining (001 FR-020, FR-021f).
- **FR-016**: The order, the autopilot and its phases MUST live in the logic layer and depend on
  nothing outside it (Principle I).

**Testability**

- **FR-017**: The autopilot MUST be verifiable by automated tests that need no graphics device and no
  running app, run by the project's single checked-in test command (Principle II).

### Key Entities

- **Move order**: a destination in the world plane. At most one at a time; a new one replaces the old.
- **Autopilot phase**: one of aligning, burning, flipping, braking and arrived. Reported only while
  there is an order.
- **Arrival tolerances**: the position tolerance (default 1 unit) and speed tolerance (default
  1 unit/s) within which an order counts as complete.
- **Simulation state**: the tick count and the ship, as before, plus the current order and the
  autopilot's memory between ticks. Still a plain value, copied when handed to the renderer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: From rest at the default limits, for destinations at every distance in {0.5, 10, 100,
  1,000, 10,000} units and in each of 16 evenly spaced directions relative to the ship's heading, 100%
  of orders reach the arrived phase within 1 unit of the destination and below 1 unit per second.
- **SC-002**: From rest, every order in SC-001 completes within 110% of the reference time plus
  0.5 seconds, where the reference time is the time an ideal pilot would take: turn in place to face
  the destination as fast as the angular limits allow, burn at full thrust, flip 180° as fast as the
  angular limits allow while coasting, and brake at full thrust to stop exactly on the destination.
- **SC-003**: For every order in SC-001, the ship is at no tick more than 1 unit beyond the
  destination, measured along the direction from its starting position to the destination.
- **SC-004**: From a spread of at least 64 starting conditions — speeds up to 1,000 units per second
  in at least 8 directions relative to the destination, destinations between 0 and 5,000 units away —
  100% of orders reach the arrived phase within tolerance within 60 simulated seconds; in none does
  the ship's bearing from the destination sweep a full turn (360°) or more; and in none does the ship
  pass the destination more than twice.
- **SC-005**: Ten runs of the same scenario — an order from a moving start, interrupted by a second
  order during each of the burning, flipping and braking phases, at least 1,200 ticks in all, with
  multi-tick advances — give byte-identical final states.
- **SC-006**: An order interrupted in any phase by a new destination arrives at the new destination
  within tolerance, and at no tick after the interruption does the autopilot's input depend on the
  old destination.
- **SC-007**: With this feature, the running app still performs zero heap allocations on the
  per-frame path over a sustained 60-second run on each platform, and what it draws is unchanged in
  Debug, with `--no-debug-overlay`, and in Release.
- **SC-008**: After arrival, a ship left with no new order for 10,000 ticks stays within 1 unit of the
  destination and in the arrived phase throughout, and by the end its speed is below 0.01 units per
  second and its rate of turn is zero.
- **SC-009**: The project's single verification command passes, with every existing test still
  passing and the new autopilot tests running headlessly and deterministically on 10 consecutive
  runs.

## Assumptions

- **Units and limits**: positions in world units (one point on screen, 005), time in seconds, and the
  ship's default limits from 004 (200 units/s², 180°/s, 360°/s²). SC-002's reference time uses the
  ship's actual limits, so it stays valid if they are retuned.
- **One order at a time**: the ticket asks for replace-on-new-order. Queued waypoints are not
  anticipated (Principle V).
- **Cancelling an order**: not requested; SKY-10/SKY-11 only ever issue new orders. Not added until a
  ticket needs it.
- **Stationary destination**: the destination does not move; following a moving target is out of
  scope.
- **Closed loop**: the autopilot looks at the ship's actual state every tick rather than following a
  pre-computed script, so it recovers from rounding and from a change of order the same way.
- **Precision**: the same double-precision numbers as the rest of the logic layer.
- **No renderer change**: the renderer receives the order in the state it is already handed and draws
  nothing from it until SKY-30.

## Dependencies

- **004-ship-newtonian-motion (SKY-24)**: the ship, its limits, the control input and the motion rule
  the autopilot drives. Merged to `main`.
- **005-game-space-camera (SKY-23)**: the world's units and the fact that it has no edges. Merged to
  `main`.
- **001-metal-app-shell**: the fixed tick, the pure `advance`, the state hand-off and the determinism
  and allocation guarantees this feature keeps.
- **Unblocks**: SKY-26 (path prediction), SKY-30 (order overlay, via SKY-26), the order lines of
  SKY-29's overlay, and SKY-10 / SKY-11 (issuing orders from input).
