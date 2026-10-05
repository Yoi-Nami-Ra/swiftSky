# Feature Specification: Draw the Order Overlay

**Feature Branch**: `014-order-overlay`

**Created**: 2026-10-05

**Status**: Draft

**Input**: User description: "SKY-30 — Draw the order overlay" (`.tickets/30.yaml`). While a move order
is active, draw a marker at the destination, a highlight around the controlled ship, and the planned
path from SKY-26 as a line from the ship to the destination. The overlay disappears when the order
completes. It is gameplay UI, so it shows in all builds. Lines and markers are drawn by the rendering
pipeline, built once, with fixed capacity (no per-frame allocation). No pulsing or other decorative
animation unless it respects Reduce Motion (Principle IV). Done when, after an order (SKY-10,
SKY-11), the marker sits exactly where the player clicked or tapped, the path ends at the marker, and
everything clears on arrival, on both platforms.

## Overview

Orders exist since 008 (tap, iOS) and 009 (click, macOS), and since 010 every order carries a
predicted path. None of it is visible: the player clicks, the ship turns and flies, and nothing on
screen says where it is going or how. This feature draws the order.

While the ship is flying an order, three things are drawn over the black background and under the
ship sprite:

- a **destination marker**, centred exactly on the world point the player picked;
- a **ship highlight**, a ring centred on the ship as it is drawn, so it moves with the sprite;
- the **planned path**, a line that starts at the ship as it is drawn, follows the part of the
  predicted path the ship has not flown yet, and ends at the marker's centre.

When the autopilot reports the order complete (arrived, keeping station), all three disappear. A new
order replaces them at once with the new destination and path. Nothing is animated: the overlay is
static apart from following the ship, so Reduce Motion has nothing to change.

The overlay is drawn from the same drawn ship pose as the sprite (013), never from the latest tick, so
the highlight and the start of the path never drift from the ship.

Out of scope: an indicator for a destination outside the visible area; the camera following the ship
(SKY-42); the debug overlay's order data (SKY-34); audio or haptic feedback for orders; any change to
how orders are issued (008, 009), flown (006) or predicted (010).

### Relationship to earlier specs

- **Unchanged and still absolute**: no allocation on the per-frame path (001 FR-020, FR-021f, 011
  check 25); the layer boundaries (Principle I) — the overlay only reads the simulation state and the
  drawn pose; everything visible is drawn by the rendering pipeline (001 FR-001, FR-007).
- **Extended**:
  - 007's frame drawing gains the overlay, between the background and the ship.
  - 010's planned path gets its first visible consumer.
- **Unaffected**: 005's camera and scale; 006's autopilot and arrival rule; 008's and 009's order
  input; 013's interpolation, whose drawn pose this feature reads; 003's debug overlay, still drawn on
  top of everything.

## Clarifications

### Session 2026-10-05

- Q: Which predicted points count as reached when the ship is drawn between two ticks? → A: Those at
  or before the earlier of the two ticks blended (the tick before the latest); under
  `--no-interpolation`, those at or before the latest tick (FR-007).
- Q: Is the ship highlight centred on the sprite's whole-pixel centre or on the exact drawn position?
  → A: On the sprite's whole-pixel centre (007 FR-006a), so ring and sprite never misalign; the marker
  and the line are not rounded (FR-005).

## User Scenarios & Testing *(mandatory)*

The users are the player, who orders the ship around and needs to see where it is going, and the
developers who build on the overlay (SKY-42's following camera, SKY-34's debug data).

### User Story 1 - The player sees where the ship is going (Priority: P1)

A player clicks (macOS) or taps (iOS) a point. A marker appears exactly there, a line runs from the
ship to it along the route the ship will fly, and the ship is ringed. As the ship flies, the line
shrinks behind it. When the ship arrives and stops, the marker, line and ring vanish.

**Why this priority**: This is the feature. Without it the first playable slice (SKY-22) gives no
feedback that an order was understood.

**Independent Test**: Launch the app on each platform, give an order, watch the overlay through the
flight and confirm it clears on arrival.

**Acceptance Scenarios**:

1. **Given** the ship at rest with no order, **When** nothing has been ordered, **Then** no overlay is
   drawn (SC-004).
2. **Given** the ship at rest, **When** the player orders it to a point, **Then** the marker is centred
   on that point, the ring surrounds the ship, and the path runs from the ship to the marker's centre,
   from the first frame after the order is applied (SC-001, SC-002).
3. **Given** an order being flown, **When** the ship moves, **Then** the ring and the start of the line
   stay on the ship as drawn, and the line covers only the route still ahead (SC-002).
4. **Given** an order being flown, **When** the ship arrives, **Then** the marker, line and ring are all
   gone from the first frame drawn after the arrival tick (SC-003).
5. **Given** an order being flown, **When** the player gives a new order, **Then** the old marker and
   path are replaced by the new ones on the next drawn frame (SC-001).

---

### User Story 2 - The overlay geometry is tested (Priority: P2)

A developer relies on the rules behind the picture: when the overlay shows, which part of the path is
still ahead, where the marker and ring are placed and how big they are. They are pure and run headlessly
with the project's single test command.

**Why this priority**: The picture of story 1 is only as right as these rules, and SKY-42 and SKY-34
build on them.

**Independent Test**: Run the project's single test command; the overlay geometry tests run without a
GPU.

**Acceptance Scenarios**:

1. **Given** a state with no order, or with the autopilot reporting arrived, **When** the overlay is
   prepared, **Then** nothing is drawn (SC-003, SC-004).
2. **Given** a state flying an order, **When** the overlay is prepared, **Then** the marker's centre is
   the order's destination exactly, the ring's centre is the sprite's whole-pixel centre, the line's
   first point is the drawn ship position, and its last point is the destination (SC-001, SC-002).
3. **Given** a planned path and a tick partway through the flight, **When** the remaining path is
   taken, **Then** it holds exactly the predicted points the ship has not reached yet, in order (SC-002).
4. **Given** a prediction that stopped before arrival (the 60-second cap), **When** the overlay is
   prepared, **Then** the line still ends at the destination (SC-002).

---

### User Story 3 - The overlay costs nothing per frame (Priority: P3)

A developer runs the allocation and frame-time checks with an order being flown: still zero heap
allocations per frame on both platforms, and frame times within budget.

**Why this priority**: Principle III and 011's check 25 demand it. It is a property of how stories 1
and 2 are delivered.

**Independent Test**: Repeat 011's check 25 (the method in `specs/011-draw-allocation-counter/quickstart.md`)
on both platforms with orders being flown.

**Acceptance Scenarios**:

1. **Given** an optimised build carrying the allocation counter, **When** the ship flies orders for 60
   seconds on each platform, **Then** the frame summaries report zero allocations per frame (SC-005).

### Edge Cases

- **No order**: nothing is drawn, so the launch surface stays uniformly black as 001's and 002's
  checks expect (with the debug overlay and ship hidden).
- **Arrived, keeping station**: the order is still held but complete; nothing is drawn. If station
  keeping later drifts out of tolerance and the autopilot leaves `arrived`, the overlay returns.
- **New order mid-flight**: the new order's marker and path replace the old ones; the ring stays.
- **Order to the ship's own position**: the order may complete on its first tick; at most one frame
  shows the overlay, which is acceptable.
- **Prediction capped before arrival** (010's 3,600-tick limit): the line follows the predicted
  points, then runs straight from the last one to the destination, so it always ends at the marker.
- **Thinned path** (010 halving past 256 points): the line joins the remaining points; it is coarser on
  long flights but still starts at the ship and ends at the marker.
- **Ship between two predicted points**: the line starts at the drawn ship and joins the next point
  not yet reached, with no backwards segment to a point already passed.
- **Destination or path outside the visible area**: drawn as far as it is visible and clipped at the
  surface edge; no off-screen indicator.
- **Window resized or rotated**: the overlay is placed through the camera each frame, so it stays on the
  same world points.
- **No camera** (zero-area surface or unusable scale, 005): nothing is drawn, as for the ship.
- **`--no-ship`**: hides only the ship sprite; the overlay still follows orders. No order exists at
  launch, so 001's and 002's black-surface checks are unaffected.
- **`--no-interpolation`**: the overlay follows the tick pose, the same pose the sprite then uses.
- **Debug overlay and debug text**: drawn on top of the order overlay.

## Requirements *(mandatory)*

### Functional Requirements

**When it shows**

- **FR-001**: The order overlay MUST be drawn exactly when the autopilot holds an order and its phase
  is not `arrived`. With no order, or with the order complete, nothing of it MUST be drawn.
- **FR-002**: The overlay MUST follow the state each frame: a new order's marker and path MUST replace
  the old ones on the first frame drawn after the order is applied, and the overlay MUST be gone on the
  first frame drawn after the arrival tick.
- **FR-003**: The overlay MUST be drawn in every build configuration (Debug, Profiling, Release). It
  is gameplay UI, not a debug aid.

**What it draws**

- **FR-004**: The **destination marker** MUST be a ring centred exactly on the order's destination,
  with an outer radius of 8 points and a stroke of 2 points.
- **FR-005**: The **ship highlight** MUST be a ring centred on the sprite's centre: the drawn ship
  position (013) rounded to whole pixels exactly as the sprite is (007 FR-006a), so ring and sprite
  never misalign. It MUST have a radius of 28 points, clear of the 40-point ship sprite (007), and a
  stroke of 1.5 points, and MUST NOT rotate with the ship. The marker and the line are not rounded.
- **FR-006**: The **planned path** MUST be a line 1.5 points wide that starts at the drawn ship
  position, then passes through, in order, every predicted path point the ship has not reached yet,
  and ends at the destination. When the prediction stopped before arrival, the line MUST run straight
  from the last predicted point to the destination.
- **FR-007**: A predicted point counts as reached once its tick is at or before the earlier of the two
  ticks the drawn pose blends (the tick before the latest, 013); under `--no-interpolation`, at or
  before the latest tick. Reached points MUST NOT be drawn, so the line never doubles back behind the
  ship.
- **FR-008**: All three parts MUST use one accent colour, the same in every build, chosen for contrast
  against the black background, and partly transparent so the ship and the background stay readable
  through it. The marker and the ring MUST differ by shape and size, not by colour alone
  (Principle IV).
- **FR-009**: The overlay MUST be drawn after the background and before the ship sprite, so the ship
  is drawn over its own ring and over the start of the line; the debug overlay and debug text MUST
  stay on top of everything.
- **FR-010**: Sizes MUST be in points (world units at the fixed scale of 005), converted to pixels for
  the surface's backing scale, so the overlay looks the same size on every display.

**How it is drawn**

- **FR-011**: The overlay MUST be placed through the same camera as the ship (005), so a marker for a
  destination given by a click or tap is centred on the point under the finger or pointer, within
  half a pixel.
- **FR-012**: Everything drawn from the ship's position MUST use the drawn pose passed to the renderer,
  never the latest tick's state (013), including under `--no-interpolation`.
- **FR-013**: The overlay MUST be drawn by the rendering pipeline: its drawing state MUST be built once
  when the renderer is created, and the per-frame work MUST NOT allocate on the heap. The capacity MUST
  be fixed and cover the largest overlay: 010's full 256-point path plus the start and end points,
  the marker and the ring.
- **FR-014**: The overlay MUST NOT animate: no pulsing, fading or dashing in motion. Its only movement
  is following the ship and shrinking as the path is flown, which is the state it shows, not decoration.
- **FR-015**: With no camera (005), nothing of the overlay MUST be drawn, and the frame MUST otherwise
  draw as before.
- **FR-016**: The overlay MUST only read the simulation state and the drawn pose. It MUST NOT change
  the order, the autopilot, the planned path or the ship (Principle I).

**Testing**

- **FR-017**: The rules for when the overlay shows, which path points remain, and where the marker,
  ring and line ends are placed MUST be pure and covered by headless tests in the project's single test
  command. The drawing itself is render code and exempt (Principle II).

### Key Entities

- **Order overlay**: what one frame shows of the current order — whether it is visible, the marker's
  centre, the ring's centre and the line's points. Prepared from the simulation state and the drawn
  pose, every frame, without keeping anything between frames.
- **Remaining path**: the predicted points the ship has not reached yet, between the drawn ship and the
  destination.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On both platforms, after an order by click or tap, the marker's centre is within half a
  pixel of the point under the pointer or finger, in 10 out of 10 orders to points across the visible
  area, including after a resize or rotation.
- **SC-002**: Throughout every flight, the line starts on the ship as drawn and ends at the marker's
  centre, with no segment behind the ship; checked by tests on the geometry and by eye on both
  platforms.
- **SC-003**: The overlay disappears on the first frame after the ship arrives, in 10 out of 10 orders
  on each platform.
- **SC-004**: With no order, the drawn surface is exactly as before this feature: uniformly black with
  the ship and debug overlay hidden, and otherwise only the ship and the debug overlay.
- **SC-005**: Zero heap allocations per frame on both platforms while orders are flown for 60 seconds
  (011 check 25), and frame times within the existing budget.

## Assumptions

- **No design exists.** `design/` holds only the ship sprite and a background, and SKY-30 has no
  `Design:` ticket. The sizes in FR-004 to FR-006 and the accent colour are this spec's choice, kept
  in one place so a later design can change them.
- **The accent colour** is a cyan-green on the black background, partly transparent; the exact value
  is a plan decision, constrained by FR-008.
- **The background is black.** If a textured background (`design/backgrounds/space.jpg`) is added
  later, the colour may need revisiting; that is out of scope here.
- **The predicted path is exact.** 010 predicts by flying the same tick the simulation uses, so the
  ship stays on the predicted points and the remaining-path rule (FR-007) never leaves a gap.
- **Visual only.** Principle IV's "more than one channel where feasible" is met for now by the ship's
  own visible motion; audio or haptic order feedback is a separate ticket.
- **Platform.** The ticket is filed under macOS, but its done-when covers both platforms and the
  renderer is shared, so this spec covers iOS and macOS.

## Dependencies

- SKY-10 (008) and SKY-11 (009): orders by tap and click.
- SKY-26 (010): the planned path.
- SKY-23 (005): the camera and the one-point-per-unit scale.
- SKY-27 (007): the ship sprite and the frame's drawing order.
- SKY-12 (013): the drawn ship pose.
- All are done.
