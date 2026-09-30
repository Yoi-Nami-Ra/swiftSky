# Feature Specification: Ship State and Newtonian Motion

**Feature Branch**: `004-ship-newtonian-motion`

**Created**: 2026-09-30

**Status**: Draft

**Input**: User description: "SKY-24 — Add ship state and Newtonian motion. Logic layer (SwiftSkySimulation). Extend SimulationState with one ship: position, velocity, heading and angular velocity, plus its fixed performance limits — maximum forward thrust acceleration, maximum angular speed and maximum angular acceleration. Advance it in Simulation.advance at the 60 Hz fixed tick with frictionless Newtonian motion (semi-implicit Euler), driven by a per-tick control input: thrust (0…1, forward only) and turn (-1…1). Stays pure and deterministic like the rest of the layer (FR-015, FR-033): plain value types, no clock, no allocation per tick. Done when Swift Testing covers: at rest with no input it stays put; full thrust matches the analytic kinematics within tolerance; turn rate and angular acceleration are clamped to the limits; ten identical runs are byte-identical (as SC-013). Default limits, to be tuned once SKY-23 fixes the scale: 200 units/s² thrust, 180°/s turn, 360°/s² angular acceleration."

## Overview

The first gameplay slice (SKY-22) is a ship that the player orders around a flat, top-down world,
and that gets where it is sent as fast as its physics allow. Everything in that slice — the
autopilot (SKY-25), the predicted path (SKY-26), the ship sprite (SKY-27), the ship lines of the
debug overlay (SKY-29) — needs a ship that exists and moves. Today the simulation holds only a tick
count.

This feature gives the simulation one ship and the rules it moves by. The ship has a position, a
velocity, a heading and a rate of turn, and three fixed limits on what its engine and thrusters can
do. Each simulation tick, a control input says how hard to thrust forward and which way to turn,
and the ship responds as a body in empty space would: no friction, no drag, no top speed. Thrust
pushes it along its heading, and it keeps drifting after the engine stops. Turning is limited both
in how fast the ship can spin and in how quickly it can change that spin.

Nothing new is visible. The running app does not yet supply any control input, so the ship stays at
rest where it starts, and the surface looks exactly as it does today. The value of this feature is
the tested motion model that the next tickets build on.

Out of scope: drawing the ship (SKY-27), the ship lines of the debug overlay (SKY-29 follow-up), the
autopilot and move orders (SKY-25), player input of any kind (SKY-10, SKY-11), path prediction
(SKY-26), interpolation between ticks (SKY-12), the world's units, extent and camera (SKY-23), more
than one ship, collisions, a top speed, drag, reverse or sideways thrust, and saving or loading
state.

### Relationship to earlier specs

- **Unchanged and still absolute**: 001 FR-015 (no global mutable state), 001 FR-033 (no clock
  read in the simulation), 001 SC-013 (identical inputs give byte-identical
  results across ten runs), 001 FR-021a and FR-021b (the 60 Hz fixed tick and its catch-up clamp),
  001 FR-020 / FR-021f (no per-frame allocation), 001 FR-012b (the tick count affects nothing
  visible, apart from 003's tick line), and every layer-boundary rule.
- **Extended**:
  - 001 FR-012c ("advancing the simulation MUST be a pure function of current state and a whole
    number of ticks") now reads: a pure function of current state, a whole number of ticks **and one
    control input** (FR-010, FR-012). Everything else in FR-012c — value types, no concurrency
    constructs in the logic layer — is unchanged.
  - The simulation state handed to the renderer (001 FR-012, FR-012a) now also carries the ship. The
    renderer receives it but draws nothing from it in this feature.
- **Unaffected**: 003's debug overlay shows the same six lines as before. Its ship lines are follow-up
  work that this feature unblocks.

## Clarifications

### Session 2026-09-30

- Q: What does the turn input command — a target rate of turn, or a raw angular acceleration? → A: A
  target rate of turn, as a fraction of the maximum angular speed, approached no faster than the
  maximum angular acceleration allows (FR-008).
- Q: When one frame advances several ticks, what control input does each tick get? → A: The same
  input for every tick of that advance (FR-011).
- Q: Within a tick, is rotation updated before translation? → A: Yes: rotation first, then thrust
  acts along the heading the ship has at the end of that tick's rotation (FR-009).
- Q: Which convention do heading zero and positive rotation follow until SKY-23 decides? → A: Heading
  zero along the positive x-axis, counter-clockwise positive with the positive y-axis up (FR-004).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers building swiftSky, and the tickets that build on the
ship (SKY-25, SKY-26, SKY-27, SKY-29). Players see nothing new.

### User Story 1 - The ship obeys thrust and drift (Priority: P1)

A developer building the autopilot needs to know exactly how the ship responds to thrust. They start
a ship at rest, apply full thrust for a second, then cut the engine, and check where it is and how
fast it is going against the textbook formulas for constant acceleration, and that it keeps moving
at a constant velocity afterwards.

**Why this priority**: This is the heart of the feature. The autopilot's burn and brake phases, the
path prediction and every later ticket depend on thrust and drift behaving as Newtonian motion does.

**Independent Test**: Run the project's single test command. The thrust tests create a ship, advance
it with a fixed thrust input and compare its speed and position with the constant-acceleration
formulas.

**Acceptance Scenarios**:

1. **Given** a ship at rest with no control input, **When** the simulation advances any number of
   ticks, **Then** its position, velocity, heading and rate of turn are exactly unchanged (SC-001).
2. **Given** a ship at rest facing heading zero, **When** full thrust is applied for one second
   (60 ticks), **Then** its speed equals the maximum thrust acceleration times one second, and the
   distance travelled matches half the acceleration times the time squared, within the tolerance of
   SC-002.
3. **Given** a ship moving with some velocity, **When** the engine is cut, **Then** it keeps exactly
   that velocity, tick after tick, and its position advances by the same amount every tick.
4. **Given** a ship facing any heading, **When** thrust is applied, **Then** the acceleration points
   along that heading and nowhere else.
5. **Given** a thrust input between 0 and 1, **When** it is applied, **Then** the acceleration is
   that fraction of the maximum thrust acceleration.

---

### User Story 2 - The ship turns within its limits (Priority: P2)

A developer building the autopilot's turn and flip phases needs to know how quickly the ship can
come round. They command a full turn, check that the rate of turn builds up no faster than the
angular acceleration limit and never exceeds the maximum angular speed, then release the turn and
check that the spin comes to a stop, again no faster than the limit allows.

**Why this priority**: The flip is what makes "turn, burn, flip and brake" work, and SKY-25 has to
plan its flip point from exactly these limits. It comes after thrust because a ship that cannot move
has nothing to turn for.

**Independent Test**: Run the single test command. The turning tests apply turn inputs and check the
rate of turn and heading tick by tick against the limits.

**Acceptance Scenarios**:

1. **Given** a ship not turning, **When** a full turn input is applied, **Then** its rate of turn
   grows by exactly the maximum angular acceleration times one tick per tick, until it reaches the
   maximum angular speed, and never exceeds it (SC-003).
2. **Given** a ship turning at its maximum angular speed, **When** the turn input returns to 0,
   **Then** its rate of turn falls by exactly the maximum angular acceleration times one tick per
   tick, reaches exactly zero, and stays there without overshooting into the opposite direction.
3. **Given** a turn input of -1, **When** it is applied, **Then** the ship turns the opposite way with
   the same limits.
4. **Given** a turn input between -1 and 1, **When** it is held, **Then** the rate of turn settles at
   that fraction of the maximum angular speed.
5. **Given** a ship turning for a long time, **When** its heading is read, **Then** it stays within
   one full turn's range rather than growing without bound (FR-005).

---

### User Story 3 - Every run is reproducible (Priority: P3)

A developer chasing a bug in the autopilot replays the same sequence of control inputs and needs the
ship to end up in exactly the same place, bit for bit, every time — on any run, whether the ticks
were advanced one at a time or several per frame.

**Why this priority**: Determinism is what makes the motion testable at all, and what later work
(replays, prediction matching the real path) relies on. It is listed third because it is a property
of stories 1 and 2 rather than a behaviour of its own.

**Independent Test**: Run the single test command. The determinism test runs a fixed, varied input
sequence ten times and compares the final states bit for bit.

**Acceptance Scenarios**:

1. **Given** a fixed sequence of control inputs and tick counts that thrusts, turns, drifts and
   brakes, **When** it is run ten times, **Then** the ten final states are byte-identical, including
   the sign of any zero (SC-004).
2. **Given** a ship and one control input, **When** it is advanced n ticks in one call and, separately,
   one tick at a time n times, **Then** the two results are byte-identical (FR-011).

---

### User Story 4 - The running app is unchanged (Priority: P4)

A developer runs the app after this feature lands and sees exactly what they saw before: the same
surface, the same debug overlay, the same log, the same frame times and no new allocations.

**Why this priority**: A gate rather than a feature, but the motion step runs on every tick of the
live frame loop, so it must not cost anything visible.

**Independent Test**: Run `./Scripts/verify.sh`, launch a Debug build on both platforms, and repeat
the allocation check used by SKY-3, SKY-4 and 002 SC-003.

**Acceptance Scenarios**:

1. **Given** the app built with this feature, **When** it is launched in Debug and Release on both
   platforms, **Then** what it draws is unchanged: the debug overlay in Debug, a uniformly black
   surface in Release and with `--no-debug-overlay`.
2. **Given** the app running for 60 seconds, **When** per-frame allocations are measured, **Then**
   there are zero (SC-005).

### Edge Cases

- **No control input yet**: the running app has no source of input until SKY-10, SKY-11 and SKY-25
  land, so every tick receives the neutral input (no thrust, no turn), and the ship stays at rest at
  its starting place (FR-010).
- **Out-of-range input**: a thrust below 0 is treated as 0 (the engine cannot push backwards), above
  1 as 1. A turn below -1 is treated as -1, above 1 as 1. A non-finite value (not a number, or
  infinite) is treated as 0, so a bad input can never make the ship's state non-finite (FR-007).
- **Zero ticks, or a negative tick count**: the state is returned exactly unchanged, ship included,
  as for the tick count today.
- **Catch-up after a stall**: the frame loop already advances at most four ticks per frame (001
  FR-021b). Those ticks all receive the frame's input (FR-011).
- **Rate of turn already above a lowered target**: when the turn input is reduced, the rate of turn
  falls toward the new target at the angular acceleration limit and stops exactly at it, never
  undershooting.
- **Very long drift**: with no drag the ship can travel indefinitely. Position and velocity are held
  at full floating-point precision; world bounds, if any, are SKY-23's concern.
- **A limit of zero**: a ship with zero thrust acceleration cannot accelerate, and one with zero
  angular speed or zero angular acceleration cannot change its rate of turn. None of these is an
  error. A negative or non-finite limit is treated as zero (FR-003).

## Requirements *(mandatory)*

### Functional Requirements

**The ship**

- **FR-001**: The simulation state MUST hold exactly one ship, with its position and velocity in the
  plane, its heading, and its rate of turn (angular velocity). It MUST remain a plain value, copied
  when it is handed across the layer boundary, as the tick count is today (001 FR-012c).
- **FR-002**: At launch the ship MUST be at the world's origin, at rest, facing heading zero and not
  turning.
- **FR-003**: Each ship MUST carry three performance limits that stay fixed for its lifetime: maximum
  forward thrust acceleration, maximum angular speed and maximum angular acceleration. Their default
  values MUST be 200 units per second squared, 180 degrees per second and 360 degrees per second
  squared, written in one place so SKY-23 can retune them. A ship MUST be creatable with other
  limits (for tests and later tuning); a negative or non-finite limit MUST be treated as zero.
- **FR-004**: Heading zero MUST point along the world's positive x-axis, and positive heading and
  positive rate of turn MUST be counter-clockwise with the positive y-axis pointing up. SKY-23 may
  restate how this maps to the screen; the motion rule does not depend on it.
- **FR-005**: The heading MUST be kept within a single turn: more than -180 degrees and at most 180
  degrees. Turning past either end continues from the other, with no jump in the direction the ship
  faces.

**The control input**

- **FR-006**: Each tick MUST be driven by one control input with two values: thrust, from 0 (engine
  off) to 1 (full thrust), forward along the heading only; and turn, from -1 (full clockwise) to 1
  (full counter-clockwise). The neutral input is no thrust and no turn.
- **FR-007**: Input values outside their ranges MUST be clamped to the nearest end of the range, and
  non-finite input values MUST be treated as 0.

**The motion rule, per tick**

- **FR-008**: Turning: the target rate of turn MUST be the turn input times the maximum angular speed.
  The ship's rate of turn MUST move toward that target by at most the maximum angular acceleration
  times one tick, and MUST stop exactly at the target when it is closer than that. The rate of turn
  MUST therefore never exceed the maximum angular speed in magnitude.
- **FR-009**: Moving: using the tick's new rate of turn and heading, the ship's velocity MUST change
  by the thrust input times the maximum thrust acceleration times one tick, along the new heading.
  Then its position MUST change by the new velocity times one tick. Velocity is updated before the
  quantity it drives, both for rotation and for translation (semi-implicit Euler). There MUST be no
  friction, no drag and no top speed.
- **FR-010**: Advancing the simulation MUST advance the ship by exactly the number of ticks the tick
  count advances, one tick being the fixed timestep (001 FR-021a). The existing way of advancing with
  no input MUST keep working and MUST mean the neutral input, so the frame loop's behaviour is
  unchanged until an input source exists.
- **FR-011**: When one call advances several ticks, every tick MUST receive the same control input,
  and the result MUST be byte-identical to advancing one tick at a time with that input.

**Purity and cost**

- **FR-012**: Advancing the ship MUST be pure and deterministic, like the rest of the logic layer:
  no clock, no randomness, no I/O and no shared state (001 FR-012c as extended above, FR-015,
  FR-033). Identical starting state
  and identical inputs MUST give byte-identical results on every run.
- **FR-013**: Advancing the ship MUST NOT allocate memory, on any tick (001 FR-020, FR-021f).
- **FR-014**: The ship, its limits, the control input and the motion rule MUST live in the logic
  layer and depend on nothing outside it (Principle I, 001 FR-010, FR-013).

**Testability**

- **FR-015**: The motion rule MUST be verifiable by automated tests that need no graphics device and
  no running app, run by the project's single checked-in test command (Principle II).

### Key Entities

- **Ship**: the one body the simulation moves. Its position and velocity in the plane, its heading
  and rate of turn, and its performance limits.
- **Performance limits**: the ship's maximum forward thrust acceleration, maximum angular speed and
  maximum angular acceleration. Fixed for the ship's lifetime; defaults in one place.
- **Control input**: what the ship is asked to do on one tick — thrust (0…1) and turn (-1…1). The
  neutral input is no thrust and no turn.
- **Simulation state**: the tick count, as before, plus the ship. Handed to the renderer as a copy.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A ship at rest given the neutral input for 10,000 ticks ends with its position,
  velocity, heading and rate of turn bit-for-bit equal to where it started.
- **SC-002**: From rest, one second (60 ticks) of full thrust at the default limit gives a speed
  within 0.0001 units per second of 200 units per second, and a distance travelled within 3.34 units
  (one tick's worth of travel at the final speed) of the 100 units the constant-acceleration formula
  predicts. Over the following second with the engine off, the distance travelled is within 0.0001
  units of 200.
- **SC-003**: Under a full turn input from rest at the default limits, the rate of turn increases by
  one tick's worth of maximum angular acceleration (6 degrees per second, to within 0.000001) on each
  tick until it reaches exactly the maximum angular speed, which takes 30 ticks (31 at most, allowing
  for rounding), and on no tick of a 600-tick run exceeds the maximum angular speed. Released, it
  returns to exactly zero within the same number of ticks and never changes sign.
- **SC-004**: Ten runs of the same varied input sequence, of at least 600 ticks covering thrust,
  turning in both directions, drifting and multi-tick advances, give byte-identical final states.
- **SC-005**: With this feature, the running app still performs zero heap allocations on the
  per-frame path over a sustained 60-second run on each platform, and what it draws is unchanged in
  Debug, with `--no-debug-overlay`, and in Release.
- **SC-006**: The project's single verification command passes, with every existing test still
  passing and the new motion tests running headlessly and deterministically on 10 consecutive runs.

## Assumptions

- **Units**: position is in world units, time in seconds, and angles in degrees at the interface of
  this spec. How long a world unit is on screen is SKY-23's decision, which is why the default limits
  are marked for retuning.
- **Turn semantics**: the turn input names a desired rate of turn rather than a raw angular
  acceleration. This is the usual model for a ship with attitude thrusters and a flight computer, it
  makes a turn input of 0 mean "stop turning", and it gives SKY-25 a simple, bounded input to plan
  with.
- **Order of updates**: fixed by FR-009 (rotation, then translation). The only requirement this puts
  on later tickets is that SKY-26's prediction uses the same rule.
- **Precision**: the ship's quantities use the same double-precision numbers as the rest of the logic
  layer.
- **One ship**: the ticket asks for one. A fleet is not anticipated (Principle V).
- **No renderer change**: the renderer receives the ship in the state it is already handed, and does
  not draw it until SKY-27.

## Dependencies

- **001-metal-app-shell**: the fixed timestep, the pure `advance` function, the state hand-off to the
  renderer and the determinism guarantee this feature extends. Merged to `main`.
- **SKY-3 and SKY-4**: the per-frame allocation check reused by SC-005.
- **SKY-23 (game space)**: not required. It will fix the world's scale, and the default limits will
  be retuned then.
- **Unblocks**: SKY-25 (autopilot), SKY-26 (path prediction), SKY-27 (ship sprite) and the ship lines
  of SKY-29's overlay.
