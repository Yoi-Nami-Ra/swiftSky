# Feature Specification: Interpolate Rendering Between Simulation Ticks

**Feature Branch**: `013-render-interpolation`

**Created**: 2026-10-04

**Status**: Draft

**Input**: User description: "SKY-12 — Interpolate rendering between simulation ticks" (`.tickets/12.yaml`).
The simulation runs on a 60 Hz fixed timestep (001 FR-021a), so on 120 Hz ProMotion displays every
other frame repeats the previous tick's pose and the ship (SKY-27) judders. Draw the ship between its
last two ticks instead. Scope: the accumulator exposes its leftover as a fraction of a tick in 0..<1
and a pure function blends two ship poses by it (position linearly, heading along the shorter arc
across ±π); the frame loop remembers the pose from the tick before the current one (two small values,
not a copy of the state), updated only on frames that advance a tick, and on multi-tick frames the
pose before the last tick; the ship sprite is placed from the blended pose (interpolation, not
extrapolation); the order overlay (SKY-30) will use the same blended pose and the debug overlay
(SKY-34) keeps the exact tick values; a `--no-interpolation` launch argument in instrumented builds
draws the tick pose. Reduce Motion: no change. Done when tests cover the blend, the fraction and the
previous-pose tracking, the ship moves without visible stepping on a 120 Hz Mac, and 011's check 25
still reports zero allocations per frame on both platforms.

## Overview

The simulation advances in fixed steps of 1/60 s, whatever the display does (001 FR-021a). A 60 Hz
display draws once per step, so every frame shows a new pose. A 120 Hz ProMotion display draws twice
per step: one frame shows the new pose and the next shows the same pose again. The ship then moves in
uneven jumps, a step and a pause, which reads as judder. Displays that vary their rate, or frames that
land unevenly against the ticks, make it worse.

This feature draws the ship where it was **between** its last two ticks, in proportion to how much of
the next tick's time has already passed. The simulation itself is untouched: it still steps at 60 Hz
and stays deterministic. Only the pose handed to the drawing changes. Every drawn pose lies between
two poses the simulation really had, so the ship never appears somewhere it did not go; the price is
that the drawing runs up to one tick (16.7 ms) behind the simulation.

The blend is linear in position and takes the shorter way round in heading, so a ship turning through
the ±π seam does not spin the long way for one frame. The sprite's whole-pixel rounding (007 FR-006a)
applies to the blended pose, as it applies to the tick pose today.

In Debug and Profiling builds, `--no-interpolation` draws the tick pose instead, so the difference can
be seen side by side.

Out of scope: the order overlay itself (SKY-30), which will draw from the same blended pose; the
debug overlay's ship data (SKY-34), which shows exact tick values; the camera that follows the ship
(SKY-42), which will centre on this feature's blended pose; extrapolating past the latest tick; and
any change to the simulation's rate, motion rule or autopilot.

### Relationship to earlier specs

- **Unchanged and still absolute**: the 60 Hz fixed tick and its catch-up clamp (001 FR-021a,
  FR-021b); the simulation's purity and determinism (001 FR-015, FR-033, SC-013); no allocation on
  the per-frame path (001 FR-020, FR-021f, 011 check 25); the layer boundaries (Principle I); 004's
  motion and 006's autopilot.
- **Extended**:
  - 001's time accumulator also reports how far the current tick has progressed (FR-001).
  - 007's ship drawing places the sprite from the blended pose instead of the tick pose (FR-006).
- **Unaffected**: 005's camera and scale; 008's and 009's orders, which convert view points to world
  points against the camera as before; 010's planned path; 003's debug overlay; 012's main-thread
  probe; the Debug order and arrival log lines, which keep reporting tick values.

## User Scenarios & Testing *(mandatory)*

The users are the player, who sees the ship move, and the developers building the order overlay
(SKY-30) and the following camera (SKY-42), which build on the blended pose.

### User Story 1 - The ship moves smoothly on a fast display (Priority: P1)

A player on a 120 Hz Mac (or ProMotion iPhone or iPad) orders the ship across the screen. The ship
turns, burns, flips and brakes in one continuous motion, with no visible stepping, at every display
rate the device offers.

**Why this priority**: This is the defect the ticket fixes. Without it the first playable slice
(SKY-22) looks broken on Apple's own fast displays.

**Independent Test**: Launch a Debug build on a 120 Hz Mac, order the ship across the window and
watch it turn and fly; relaunch with `--no-interpolation` and compare.

**Acceptance Scenarios**:

1. **Given** a 120 Hz display, **When** the ship flies an order, **Then** it moves and turns without
   visible stepping (SC-004).
2. **Given** the same display and `--no-interpolation`, **When** the ship flies the same order,
   **Then** the old stepping is visible again, for comparison (SC-004).
3. **Given** a 60 Hz display, **When** the ship flies an order, **Then** it looks as it did before:
   one new pose per frame (SC-004).
4. **Given** `--debug-ship-spin`, **When** the ship turns in place through the ±π heading, **Then** it
   turns continuously the short way, with no frame that spins it the long way round (SC-002).

---

### User Story 2 - The blended pose is tested and exact (Priority: P2)

A developer relies on the blend and the frame loop's bookkeeping: the blended pose equals the previous
tick's pose at the start of a tick and approaches the current tick's pose as the tick ends; the
fraction never leaves its range; and the previous pose is the right one on frames that advance no
tick, one tick or several.

**Why this priority**: The smooth picture of story 1 is only as good as these rules, and SKY-30 and
SKY-42 build on them.

**Independent Test**: Run the project's single test command; the blend, fraction and pose-tracking
tests run headlessly.

**Acceptance Scenarios**:

1. **Given** two poses, **When** they are blended at fraction 0, **Then** the result is the previous
   pose bit for bit; **When** blended at fractions approaching 1, **Then** the result approaches the
   current pose, and equals it bit for bit when the two poses are the same (SC-001).
2. **Given** headings on either side of the ±π seam, **When** they are blended, **Then** the heading
   moves the short way across the seam, in both directions (SC-002).
3. **Given** any sequence of elapsed times, including stalls that trigger the catch-up clamp, **When**
   the accumulator consumes them, **Then** the reported fraction is always at least 0 and below 1
   (SC-003).
4. **Given** a frame that advances 0, 1 or several ticks, **When** the frame loop records poses,
   **Then** the previous pose is unchanged on a 0-tick frame, is the pose before the frame on a 1-tick
   frame, and is the pose before the last tick on a multi-tick frame; and the state after the frame is
   byte-identical to advancing the same ticks in one step (SC-003).

---

### User Story 3 - Smoothness costs nothing per frame (Priority: P3)

A developer runs the allocation and frame-time checks after this feature: still zero heap
allocations per frame on both platforms, and frame times within budget.

**Why this priority**: Principle III and 011's check 25 demand it. It comes last because it is a
property of how stories 1 and 2 are delivered.

**Independent Test**: Repeat 011's check 25 (the method in `specs/011-draw-allocation-counter/quickstart.md`)
on both platforms with an order being flown.

**Acceptance Scenarios**:

1. **Given** the app with this feature in an optimised build carrying the allocation counter, **When**
   the ship flies orders for 60 seconds on each platform, **Then** the frame summaries report zero
   allocations per frame (SC-005).

### Edge Cases

- **First frame**: before any tick there is no earlier pose; the previous pose is the initial pose,
  so the blend draws the initial pose.
- **Frames that advance no tick**: the previous and current poses stay as they were and only the
  fraction grows, so consecutive frames draw consecutive points between the same two ticks.
- **Multi-tick (catch-up) frames**: the previous pose is the one before the last tick advanced, not
  the one before the frame, so the drawing never blends across more than one tick.
- **Catch-up clamp discards time**: the fraction is the leftover after the discard, still in 0..<1.
- **Ship at rest or station-keeping**: the two poses are equal and the blend returns that pose exactly.
- **Heading across ±π**: blended the short way. Headings exactly π apart (never reached in one tick,
  whose turn is bounded by the ship's angular rate) blend in a fixed, documented direction.
- **New order**: an order changes the target, not the ship's position or heading, so no snap is
  needed; the blend continues across it.
- **Explicit input** (`--debug-ship-spin`, tests): the poses come from whatever ticks were advanced;
  the blend does not care what drove them.
- **Window hidden, resized or paused**: no frame is drawn while paused (012 R13); on resume the
  accumulator's handling of elapsed time is unchanged, and the poses and fraction follow from it.
- **Rounding in the accumulator**: floating-point error in the leftover must never push the fraction
  below 0 or to 1 or above; it is clamped into range.
- **`--no-ship`**: nothing is drawn, interpolated or not.

## Requirements *(mandatory)*

### Functional Requirements

**The fraction**

- **FR-001**: The time accumulator MUST report the progress of the current tick: its leftover time as
  a fraction of one tick, always at least 0 and below 1, including after the catch-up clamp discards
  time (001 FR-021b) and in the presence of floating-point rounding.

**The blend**

- **FR-002**: The logic layer MUST provide a pure function that blends a previous and a current ship
  pose (position and heading) by a fraction in 0..<1. Position MUST be blended linearly. Heading MUST
  be blended along the shorter arc between the two headings, crossing ±π when that is shorter.
- **FR-003**: At fraction 0 the blend MUST return the previous pose bit for bit. When the two poses
  are equal, it MUST return that pose bit for bit at every fraction. As the fraction approaches 1 the
  result MUST approach the current pose.
- **FR-004**: The blend MUST be deterministic, allocation-free and depend on nothing outside the
  logic layer (001 FR-015, Principle I).

**Tracking the previous pose**

- **FR-005**: The frame loop MUST keep the ship's position and heading from the tick before the
  current state's tick, as two small values rather than a copy of the simulation state. On a frame
  that advances no tick they MUST NOT change. On a frame that advances one or more ticks they MUST be
  the pose before the last tick of that frame. Before the first tick they MUST equal the initial pose.
  Splitting a frame's advance to capture that pose MUST leave the resulting state byte-identical to
  advancing the same ticks at once, with or without an explicit control input.

**Drawing**

- **FR-006**: The ship sprite MUST be placed from the blended pose of the previous and current tick
  poses at the accumulator's fraction for that frame, with 007's whole-pixel rounding applied to the
  blended position. The blended pose MUST NOT be written back to the simulation.
- **FR-007**: The blended pose MUST be available, alongside the state, to everything that draws from
  the ship's pose, so the order overlay (SKY-30) and the following camera (SKY-42) can use the same
  pose as the sprite. The debug overlay and the Debug log lines MUST keep reporting tick values.
- **FR-008**: In Debug and Profiling builds, the launch argument `--no-interpolation` MUST draw the
  current tick pose instead of the blended one. Release builds MUST NOT recognise it.

**Cost and accessibility**

- **FR-009**: Interpolation MUST add no heap allocation to the per-frame path (001 FR-020, FR-021f).
- **FR-010**: Interpolation MUST NOT change behaviour under Reduce Motion: it adds no motion, only
  smooths the motion the simulation already produces.

**Testability**

- **FR-011**: The fraction, the blend and the previous-pose tracking MUST be verifiable by automated
  tests that need no graphics device, run by the project's single checked-in test command
  (Principle II).

### Key Entities

- **Ship pose**: a position in world units and a heading in radians, as the ship carries them.
- **Tick fraction**: how far the time since the last tick has progressed towards the next, in 0..<1.
- **Previous pose**: the ship pose one tick before the current state, held by the frame loop.
- **Blended (drawn) pose**: the pose the ship is drawn at this frame; never stored in the simulation.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The blend returns the previous pose bit for bit at fraction 0 and an equal pair's pose
  bit for bit at every tested fraction; across at least 1,000 pose pairs and fractions in 0..<1, every
  blended position lies on the segment between the two positions and its distance from the previous
  position is the fraction of the whole distance, to within 1e-9 of it.
- **SC-002**: For heading pairs across the ±π seam in both directions (for example 3.1 → −3.1 and
  −3.1 → 3.1), every blended heading lies on the short arc between them; no blend ever turns more than
  half a turn. With `--debug-ship-spin` no frame shows the ship turning the long way.
- **SC-003**: Over at least 10,000 elapsed-time values, including 0, negative, non-finite, sub-tick,
  exact multiples of a tick and stalls of 10 s, the fraction is always ≥ 0 and < 1. For frames
  advancing 0, 1, 2 and 4 ticks, the tracked previous pose matches FR-005 bit for bit, and the state
  after the split advance is byte-identical to the unsplit advance.
- **SC-004**: On a 120 Hz Mac, a ship flying an order and spinning in place shows no visible stepping;
  with `--no-interpolation` the stepping is visible. On a 60 Hz display the picture is unchanged.
  Checked by eye and recorded in the quickstart.
- **SC-005**: 011's check 25 reports zero allocations per frame over 60 seconds of flying orders on
  both iOS and macOS, and frame times stay within the 001 frame budget.
- **SC-006**: The project's single verification command passes, with every existing test still
  passing and the new tests running headlessly and deterministically on 10 consecutive runs.

## Assumptions

- **Interpolation, not extrapolation**: drawing up to one tick behind keeps every drawn pose real at
  the cost of at most 16.7 ms of extra latency, which the ticket accepts.
- **Ship only**: the ship is the only thing that moves today. Anything that moves later (SKY-30's
  markers follow fixed points; SKY-42's camera follows the ship) uses the same blended pose.
- **No snap case**: nothing in the simulation teleports the ship; a new order changes the target only.
  A future feature that teleports would add its own reset of the previous pose.
- **Exactly-opposite headings**: cannot occur between two consecutive ticks (one tick's turn is far
  below half a turn), so their blend direction is a documented convention rather than a product
  decision.
- **Visual check by eye**: smoothness is a perceptual property; the automated tests verify the rules
  that produce it, and the by-eye check is recorded in the quickstart, as 007 recorded its visual
  checks.

## Dependencies

- **001-metal-app-shell**: the fixed timestep, the accumulator, the frame loop and the allocation
  guarantee. Merged to `main`.
- **004-ship-newtonian-motion (SKY-24)** and **006-ship-autopilot (SKY-25)**: the ship's pose and the
  ticks that move it. Merged to `main`.
- **007-ship-sprite-rendering (SKY-27)**: the sprite placement this feature feeds. Merged to `main`.
- **011-draw-allocation-counter**: check 25, the zero-allocation measurement. Merged to `main`.
- **Unblocks**: SKY-30 (the order overlay, which draws from the blended pose) and SKY-42 (the camera
  that follows the ship).
