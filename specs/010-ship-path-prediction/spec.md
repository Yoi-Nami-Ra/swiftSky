# Feature Specification: Predict the Ship's Planned Path

**Feature Branch**: `010-ship-path-prediction`

**Created**: 2026-10-01

**Status**: Draft

**Input**: User description: "SKY-26 — Predict the ship's planned path" (`.tickets/26.yaml`). Logic
layer. For the order overlay (SKY-30), compute the path the ship will try to cover by running the
autopilot (SKY-25) forward on a copy of the state until arrival, sampling positions into a
fixed-capacity buffer (default 256 points, downsampled for long trips). Recompute only when the order
changes, not every frame, and never allocate on the per-frame path (constitution Principle III). Done
when tests show: the prediction's end point matches where the real simulation arrives; the first
point is the ship's current position; the buffer never exceeds its capacity.

## Overview

The first gameplay slice (SKY-22) ends with an **order overlay** (SKY-30): when the player clicks or
taps a destination, the screen shows a marker there and the route the ship is about to fly. Specs 006,
008 and 009 already let the player give that order and let the autopilot fly it. What is missing is
the route itself: the overlay cannot draw a path that nobody has worked out.

This feature works it out. When the ship is given an order, the simulation flies a copy of itself
forward, with the same autopilot and the same physics, until the copy arrives, and records where the
ship goes on the way. That record is the **planned path**. Because the autopilot keeps everything it
needs in the simulation state (006 FR-014) and the simulation is deterministic, the copy flies exactly
the flight the real ship is about to fly, so the planned path ends precisely where the ship will stop.

The path is worked out once per order, not every frame, and kept in a fixed amount of space: up to
256 positions. A short flight is recorded tick by tick; a long one is thinned out evenly so it still
fits. A flight that would never finish — a ship that cannot thrust, for instance — is cut off after a
fixed amount of simulated time and marked as not arriving.

Nothing new is drawn. The renderer receives the path with the state it is already handed but draws
nothing from it until SKY-30. In Debug and Profiling builds the existing order log line also reports
where the prediction ends, so the running app can be checked against it. The value of this feature is a tested path that the order overlay
builds on.

Out of scope: drawing the path, the destination marker or the ship highlight (SKY-30); trimming the
drawn path as the ship flies along it (SKY-30); the order lines of the debug overlay (SKY-34);
interpolating between ticks (SKY-12); predicting anything other than positions and when they are
reached (heading, speed or phase along the path); and any change to the autopilot, the ship's motion
or its limits.

### Relationship to earlier specs

- **Unchanged and still absolute**: 006's autopilot law and phases, 004's motion rule and limits — the
  real ship flies exactly as before; 001 FR-015 (no global mutable state), FR-033 (no clock in the
  simulation), SC-013 (byte-identical results across ten runs), FR-020 / FR-021f (no per-frame
  allocation), the 60 Hz fixed tick (FR-021a) and every layer-boundary rule.
- **Extended**:
  - The simulation state (001 FR-012, 004 FR-001, 006 FR-003) now also carries the planned path of the
    current order.
  - Giving the ship an order (006 FR-002) now also predicts that order's path.
  - 008 FR-015's Debug order log line also reports the prediction (FR-014).
- **Unaffected**: 005's camera and scale; 007's ship drawing; 008's and 009's tap and click, which
  give orders exactly as before and get a path with each one; 003's debug overlay, which shows the
  same lines as before.

## Clarifications

### Session 2026-10-01

- Q: Should the path record when each point happens, so SKY-30 can tell which part has already been
  flown? → A: Yes: the tick count at which the order was given, the spacing in ticks between
  consecutive points, and the tick count of the last point (FR-004).
- Q: The running app draws nothing new, so how is it seen in the app that each order gets a path? →
  A: Debug and Profiling builds add the prediction to the existing order log line: the predicted end
  point and its tick, the number of points, and whether it arrives (FR-014).
- Q: How is SC-007's 1 ms prediction-time target verified? → A: The automated tests check the
  deterministic work bound (no prediction advances more than 3,600 ticks, SC-004); the wall-clock time
  is measured once in an optimised build and recorded in the quickstart (SC-007).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers building swiftSky and the ticket that draws the path
(SKY-30). Players see nothing new until SKY-30 draws it.

### User Story 1 - Know where an order will take the ship (Priority: P1)

A developer gives the ship an order — from rest or while it is moving — and reads the planned path
from the simulation state. The path starts where the ship is, follows the flight the autopilot is
about to fly, and ends exactly where the ship will come to rest. Running the real simulation from the
same state confirms it: the ship passes through the path's points in order and stops on its last one.

**Why this priority**: This is the whole point of the feature: a path SKY-30 can draw that tells the
player the truth about where the ship is going.

**Independent Test**: Run the project's single test command. The prediction tests give orders from
rest and from moving starts, read the planned path, then advance the real simulation to arrival and
compare its positions with the path's points.

**Acceptance Scenarios**:

1. **Given** a ship at rest, **When** it is ordered to a point 1,000 units away, **Then** the path's
   first point is the ship's position, its last point is exactly the position on which the real
   simulation first reports arrival, and the path is marked as reaching arrival (SC-001).
2. **Given** a ship moving fast across the line to its destination, or straight at a destination too
   close to stop at, **When** it is ordered there, **Then** the path follows the real flight —
   including the sideways correction or the pass and turn-back — and still ends where the real ship
   arrives (SC-001, SC-002).
3. **Given** any order, **When** the real simulation flies it, **Then** every point of the path is a
   position the real ship occupies on its way, and the points come in the order the ship reaches them
   (SC-002).
4. **Given** a ship already at rest on its destination, **When** it is ordered there, **Then** the
   path is a single point, the ship's position, marked as reaching arrival.
5. **Given** a Debug build on either platform, **When** the player gives an order and lets the ship
   arrive, **Then** the order's log line reports the predicted end point and tick, and the arrival
   line that follows reports the same point and tick, allowing for an arrival on a multi-tick frame
   (SC-009).

---

### User Story 2 - Long and endless flights still fit (Priority: P2)

A developer orders the ship across a large window, or orders a ship that cannot thrust at all. The
long flight is thinned out evenly so it fits the fixed space of 256 points without losing its shape,
and still ends on the arrival point. The flight that would never finish stops being predicted after
60 simulated seconds, and the path says it does not arrive.

**Why this priority**: Without it, a long flight would overflow the fixed space or be cut short at a
wrong end point, and an impossible order would make the prediction run forever. It comes after story
1 because it only matters for flights longer than the space holds.

**Independent Test**: Run the single test command. The capacity tests order flights of many lengths,
from a single tick to past the cap, and check the number of points, their spacing, the end point and
the arrival mark.

**Acceptance Scenarios**:

1. **Given** a flight short enough for every tick's position to fit, **When** it is predicted,
   **Then** the path holds one point per tick, from the order to arrival (SC-003).
2. **Given** a flight longer than that, **When** it is predicted, **Then** the path holds no more than
   256 points and at least 128, evenly spaced in time, and its last point is still exactly where the
   real ship arrives (SC-003).
3. **Given** a ship with zero thrust ordered to a distant point, **When** it is predicted, **Then** the
   prediction stops after 60 simulated seconds, the last point is where the ship would be at that
   moment, and the path is marked as not reaching arrival (SC-004).

---

### User Story 3 - Planned once per order, free on every frame (Priority: P3)

A developer gives an order and lets the simulation run. The path is worked out when the order is
given and then left alone while the ship flies it; giving a new order replaces it at once. The
running app gives and flies orders without allocating memory on any frame, without dropping frames
when an order is given, and with exactly the picture it drew before.

**Why this priority**: The ticket and Principle III demand it, and it keeps the frame loop's cost
unchanged. It comes last because it is a property of how stories 1 and 2 are delivered.

**Independent Test**: Run the single test command for the per-order behaviour and determinism; run
`./Scripts/verify.sh`, launch a Debug build on both platforms, give an order every second for a
minute, and repeat the allocation and frame-time checks used by 008 and 009.

**Acceptance Scenarios**:

1. **Given** a ship flying an order, **When** the simulation is advanced by any number of ticks,
   **Then** the path is unchanged (SC-005).
2. **Given** a ship flying an order, **When** it is given a new one, **Then** the path is replaced at
   once by the new order's path, starting from where the ship is (SC-005).
3. **Given** a ship flying an order, **When** it is given an order that is refused (a non-finite
   destination), **Then** the path, like the rest of the state, is unchanged (SC-005).
4. **Given** a fixed starting state and a fixed sequence of orders, **When** it is run ten times,
   **Then** the ten final states, paths included, are byte-identical (SC-006).
5. **Given** the app built with this feature, **When** the player gives an order every second for a
   minute on each platform, **Then** no frame allocates memory, no frame is dropped because an order
   was given, and what the app draws is unchanged (SC-007).

### Edge Cases

- **No order**: the state carries no path, exactly as there is no order and no phase (006 FR-003).
- **Already there**: an order that completes at once (006's "already there" case) gives a one-point
  path at the ship's position, marked as reaching arrival.
- **New order mid-flight**: the old path is discarded whole; the new one starts at the ship's current
  position, whatever its speed and heading.
- **Same destination again**: re-ordering to the current destination predicts afresh from where the
  ship is now; the new path ends where the real ship will arrive, as always.
- **Refused order**: a non-finite destination is refused and leaves the state, path included,
  unchanged (006 FR-002).
- **Never arrives**: a ship with a limit of zero (006 FR-013), or any flight longer than the cap, gives
  a path that stops at the cap and is marked as not reaching arrival. It is not an error, and the real
  ship flies on regardless.
- **Very far destinations**: orders thousands of units away arrive well inside the cap (006 SC-004 has
  flights of up to 5,000 units arrive within 60 seconds), and the player can only click or tap on the
  visible surface. A destination far enough to exceed the cap (006's edge case of 10⁶ units) can only
  come from a test or a future feature, and gets a capped path.
- **Explicit input**: advancing with an explicit control input (tests and `--debug-ship-spin`) moves
  the ship off its plan but does not change the path; the path is the plan made when the order was
  given (006 FR-011).
- **After arrival**: the order stays, station-keeping, until a new one (006 FR-009); so does its path.
  Whether to show it after arrival is SKY-30's decision.
- **Catch-up frames**: advancing several ticks in one frame does not touch the path.

## Requirements *(mandatory)*

### Functional Requirements

**The planned path**

- **FR-001**: While the ship has an order, the simulation state MUST carry that order's planned path:
  an ordered list of world positions the ship is predicted to pass through, from where it was when
  the order was given to where it is predicted to stop. Without an order, the state MUST carry an
  empty path.
- **FR-002**: The path MUST be predicted by advancing a copy of the simulation state, just after the
  order is given, with the autopilot exactly as the real simulation advances it with no explicit input
  (006 FR-011, FR-014), one tick at a time, until the first tick on which the autopilot reports arrived
  or until the cap of FR-006.
- **FR-003**: The first point MUST be the ship's position at the moment the order is given. When the
  prediction reaches arrival, the last point MUST be the ship's position on the first arrived tick —
  bit for bit the position the real simulation reaches on that tick when advanced from the same state
  with no new order and no explicit input.
- **FR-004**: The path MUST record whether its prediction reached arrival, and when its points happen:
  the tick count at which the order was given, the spacing in ticks between consecutive points (1 when
  every tick is recorded), and the tick count of the last point (the predicted arrival, or the cap).
  Every point but the last is therefore at the order's tick plus a whole number of spacings, so SKY-30
  can tell which part of the path the ship has already flown.
- **FR-005**: The path MUST hold at most 256 points, a number written in one place. A flight whose
  positions all fit — at most 256, counting the first and the last — MUST be recorded at every tick.
  A longer flight MUST be thinned out: its points evenly spaced in ticks from the first, the last point
  always the final predicted position (which may lie closer to its predecessor than the spacing), and
  at least 128 points in all.
- **FR-006**: The prediction MUST stop after 60 simulated seconds (3,600 ticks) of flight if the
  autopilot has not reported arrival by then, a limit written in one place. The last point is then the
  predicted position at the cap, and the path is marked as not reaching arrival.

**When it is predicted**

- **FR-007**: The path MUST be predicted every time the ship is given an order, by whatever means —
  including the player's tap and click (008, 009) — and MUST replace any previous path completely. An
  order that is refused MUST leave the path unchanged, with the rest of the state (006 FR-002).
- **FR-008**: Advancing the simulation, by any number of ticks, with or without an explicit control
  input, MUST NOT change the path. It changes only when the order does.
- **FR-009**: Predicting MUST NOT change anything else in the state: the ship, the order, the
  autopilot's phase and the tick count after an order is given MUST be exactly what they would be
  without this feature, so the real flight is unchanged.

**Purity and cost**

- **FR-010**: The prediction MUST be pure and deterministic, like the rest of the logic layer: no
  clock, no randomness, no I/O and no shared state (001 FR-015, FR-033). Identical states and orders
  MUST give byte-identical paths.
- **FR-011**: Predicting MUST NOT allocate memory, and carrying the path MUST NOT add any allocation
  when the state is advanced, copied or handed to the renderer (001 FR-020, FR-021f, Principle III).
  Its work MUST be bounded by the cap, whatever the order.
- **FR-012**: The path and its prediction MUST live in the logic layer and depend on nothing outside
  it (Principle I).

**Testability**

- **FR-013**: The prediction MUST be verifiable by automated tests that need no graphics device and no
  running app, run by the project's single checked-in test command (Principle II).

**Observability**

- **FR-014**: In Debug and Profiling builds, the log line written for each applied order (008 FR-015)
  MUST also report the prediction: the last point and its tick count, in the same format as the
  arrival line's position and tick count, the number of points, and whether the prediction reaches
  arrival. Nothing is formatted on frames without an order, and Release builds log nothing, as before.

### Key Entities

- **Planned path**: up to 256 world positions in flight order; whether the prediction reached arrival;
  the tick count at which the order was given, the spacing in ticks between points and the tick count
  of the last point. Belongs to the current order; empty without one.
- **Prediction cap**: 60 simulated seconds (3,600 ticks), the longest flight that is predicted.
- **Simulation state**: the tick count, the ship and the autopilot, as before, plus the planned path.
  Still a plain value, copied when handed to the renderer.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For every order in 006's arrival grid (from rest, distances {0.5, 10, 100, 1,000,
  10,000} units in 16 directions) and in 006's spread of at least 64 moving starts, 100% of planned
  paths start at the ship's position when the order was given, end bit for bit on the position where
  the real simulation first reports arrival, and are marked as reaching arrival.
- **SC-002**: For every order in SC-001, every point of the path equals, bit for bit, the real ship's
  position on the tick the path assigns to it (FR-004), and the last point's tick is the tick on which
  the real simulation first reports arrival.
- **SC-003**: Across flights of every length from 0 ticks to past the cap, no path ever holds more than
  256 points; every flight of at most 255 ticks is recorded at every tick; every longer flight holds
  at least 128 points, evenly spaced in ticks apart from the last.
- **SC-004**: An order that cannot complete — a ship with zero thrust, or zero angular acceleration
  facing away from its destination — gives a path that ends on the position the real simulation
  reaches after exactly 3,600 ticks, marked as not reaching arrival. For every order in the tests, the
  last point's tick is at most 3,600 ticks after the order's: no prediction does more work than that.
- **SC-005**: While a ship flies an order, advancing it by 1 to 1,000 ticks, with or without an
  explicit input, leaves the path byte-identical; a new order replaces it with that order's prediction
  on the same step; a refused order leaves the whole state byte-identical.
- **SC-006**: Ten runs of 006's determinism scenario — an order from a moving start, interrupted by a
  new order during each of burning, flipping and braking, at least 1,200 ticks with multi-tick
  advances — give byte-identical final states, planned paths included.
- **SC-007**: Predicting a flight that runs to the cap takes under 1 millisecond, measured once in an
  optimised build on the development Mac and recorded in the quickstart; the automated tests check
  SC-004's work bound instead of wall-clock time, which would make them flaky. With this feature, the
  running app performs zero heap allocations on the per-frame path over a 60-second run with an order
  given every second on each platform; in a Profiling build (optimised, with the overlay's dropped-frame
  count) it drops no frame because an order was given; and it draws exactly what it drew before, in
  Debug, with `--no-debug-overlay`, and in Release.
- **SC-008**: The project's single verification command passes, with every existing test still passing
  and the new prediction tests running headlessly and deterministically on 10 consecutive runs.
- **SC-009**: In a Debug build on each platform, for at least 10 orders flown to arrival without
  interruption, the predicted end point and tick on each order's log line equal the position and tick
  count on the arrival line that follows it. The one allowed difference: the arrival line is written
  once per frame, after the frame's whole advance (008 FR-015), so when arrival falls on a frame that
  advanced several ticks, that line comes the extra ticks later and its position is the ship's
  station-keeping position at that tick.

## Assumptions

- **Positions and their ticks only**: SKY-30 draws the path as a line from the ship, so the path
  records positions and when they are reached (three tick numbers, FR-004), not heading, speed or
  phase. Anything more waits for a ticket that needs it (Principle V).
- **Capacity**: 256 points, the ticket's default; fixed, not configurable at run time.
- **Cap**: 60 simulated seconds, the same bound within which 006 SC-004 has every moving-start order
  arrive; far beyond any flight between two points of the visible surface.
- **Even spacing in time**: points are spaced by ticks, not by distance, so a thinned path keeps its
  timing shape and its points are positions of the real flight. Points cluster where the ship is slow
  (turning in place, the last metres of braking) — harmless for a drawn line.
- **A plan, not a live track**: the path is predicted when the order is given and describes the flight
  from that moment. Trimming the part already flown, or redrawing it from the ship's current position,
  is SKY-30's concern; the recorded ticks (FR-004) tell it which part that is.
- **Timing reference**: the iOS and macOS baseline devices of 001 were dropped (SKY-1, SKY-2,
  2026-10-01), so SC-007's timing target is measured on the development Mac, as other checks are now.
  Under 1 ms is about 6% of a 60 Hz frame; a typical on-screen order flies for a few seconds and costs
  a fraction of that.
- **No renderer or input change**: the renderer receives the path in the state it is already handed
  and draws nothing from it until SKY-30; tap and click are unchanged. The only change outside the
  logic layer is FR-014's extra fields on the Debug order log line; the arrival line is unchanged.

## Dependencies

- **006-ship-autopilot (SKY-25)**: the autopilot, its phases and arrival, and the guarantee that a copy
  of the state flies the same flight (FR-011, FR-014). Merged to `main`.
- **004-ship-newtonian-motion (SKY-24)**: the ship and its motion rule. Merged to `main`.
- **008-tap-to-order-ios / 009-click-to-order-macos (SKY-10, SKY-11)**: the player's orders, which now
  arrive with a path. Merged to `main`.
- **001-metal-app-shell**: the fixed tick, the pure `advance`, the state hand-off and the determinism
  and allocation guarantees this feature keeps.
- **Unblocks**: SKY-30 (the order overlay), and with it the end of SKY-22's first playable slice.
