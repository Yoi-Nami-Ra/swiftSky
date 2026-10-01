# Feature Specification: Tap to Order the Ship on iOS

**Feature Branch**: `008-tap-to-order-ios`

**Created**: 2026-10-01

**Status**: Draft

**Input**: User description: "SKY-10 — Tap to order the ship on iOS" (`.tickets/10.yaml`). Part of
SKY-22. A tap on the game surface issues a move order to the ship: the platform layer converts the tap
from view points to world coordinates (camera transform from SKY-23 / spec 005) and hands it to the
logic layer as a plain value, where the autopilot (SKY-25 / spec 006) takes over. This is the first
real use of the input → logic direction of 001's FR-010; the logic layer learns nothing about UIKit or
SwiftUI. A new tap mid-flight replaces the current order. Input crosses into the frame loop's
isolation domain by value, like surface events do today (FR-030), and the main thread never blocks on
a frame. Done when tapping anywhere on the surface sends the ship there, including in iPad Split View
sizes, and the screen → world conversion is unit-tested. The macOS counterpart is SKY-11 (click),
which should be able to reuse the order event and conversion.

## Overview

The ship is drawn (SKY-27) and can fly itself to a destination (SKY-25), but nothing gives it a
destination yet: it sits at the centre of the screen. This feature lets the player on an iPhone or
iPad tap anywhere on the game surface and have the ship fly there and stop.

- **What**: one tap on the surface becomes one move order to the world point under the finger.
- **Where it goes**: the tap is captured by the platform layer, travels to the frame loop as a plain
  value, is turned into a world point through the camera, and becomes the ship's order. From there the
  existing autopilot flies the ship: turn, burn, flip, brake, then keep station.
- **Replacing**: a tap while the ship is still flying replaces the current order at once.

Out of scope: the macOS click (SKY-11, which reuses this feature's order event and conversion), the
destination marker and planned path (SKY-30, SKY-26), drag-to-steer, long press, multi-finger
gestures, haptic or audio feedback, keyboard and game-controller input, VoiceOver custom actions or
spoken descriptions of the ship, and any change to the camera, the ship, the autopilot or the drawing.

### Relationship to earlier specs

- **First use**: the input → simulation direction of 001 FR-010 and the constitution's unidirectional
  data flow (input → simulation update → render). Until now only surface events crossed into the loop.
- **Extended**: the one channel from the main thread into the loop (001 FR-029, FR-030) now also
  carries a tap. The same rules apply to it: handed over without blocking, safe to transfer by
  construction, applied at a frame boundary and never mid-draw (001 FR-031).
- **Reused unchanged**: the camera's view → world mapping and its absence for a zero-area surface
  (005 FR-004, FR-008); the move order, its rejection of non-finite destinations and its whole
  replacement by a new order (006 FR-001, FR-002); the autopilot-flown advance (006 FR-011); the
  `--debug-ship-spin` explicit-input path that leaves any order alone (007 FR-013).
- **Unchanged and still absolute**: the logic layer depends on neither rendering nor platform UI
  (001 FR-010, FR-011); no global mutable state (001 FR-015); no per-frame allocation (001 FR-020);
  determinism of the simulation for the same inputs (001 FR-033, SC-013); the platform-UI layer draws
  nothing (001 FR-007).

## Clarifications

### Session 2026-10-01

- Q: How do VoiceOver users order the ship, given the surface is an image element that a tap only
  selects? → A: The surface allows direct interaction: with VoiceOver on, taps on it reach the game and
  order the ship as usual. Its accessible label is unchanged.
- Q: How is arrival under the tap verified on device, when nothing on screen shows the order? → A:
  Debug and Profiling builds log one line per applied order (tap view position and world destination)
  and one line on arrival (final position), through the existing log-only instrumentation; Release
  builds log nothing.

## User Scenarios & Testing *(mandatory)*

The users of this feature are players on iPhone and iPad, who order the ship around for the first
time, and the developers of SKY-11 and SKY-30, who build on the order event and conversion.

### User Story 1 - Tap to send the ship (Priority: P1)

A player launches the app on an iPhone. The ship sits at the centre, nose to the right. The player
taps somewhere on the screen, up and to the left of the ship. The ship turns to face that point, burns
towards it, flips, brakes and comes to rest where the finger touched, then stays there.

**Why this priority**: This is the feature. It turns the slice from something to watch into something
to play.

**Independent Test**: Launch a Debug build on an iPhone (or the simulator), tap a few points on the
surface and check that the ship comes to rest under each one.

**Acceptance Scenarios**:

1. **Given** the ship at rest with no order, **When** the player taps a point on the surface, **Then**
   the ship receives a move order whose destination is the world point under the tap, and the
   autopilot flies it there and brings it to rest within the arrival tolerances (006 FR-010).
2. **Given** a tap at the exact centre of the surface, **When** the order is issued, **Then** its
   destination is the world origin.
3. **Given** a tap at view position (vx, vy) points on a surface w × h points, **When** the order is
   issued, **Then** its destination is (vx − w/2, h/2 − vy) in world units (005 FR-004): taps to the
   right of centre give positive x, taps above centre give positive y.
4. **Given** a tap anywhere on the surface, including under the status bar, the home indicator or the
   debug overlay, **When** it is recognised, **Then** it is an order like any other: the whole surface
   is the target, not only the safe area.
5. **Given** the ship has arrived at an ordered destination, **When** nothing else happens, **Then**
   it keeps station there until the next tap.

---

### User Story 2 - A new tap changes the plan (Priority: P2)

The ship is mid-flight towards a destination. The player changes their mind and taps somewhere else,
perhaps behind the ship. The ship abandons the old destination at once and flies to the new one,
cancelling its current velocity on the way rather than orbiting.

**Why this priority**: Without it the player has to wait for each flight to finish, which feels
broken. It is second because a single tap already proves the path from finger to ship.

**Independent Test**: In a Debug build, tap far away, then tap a second point before the ship arrives;
the ship comes to rest at the second point. In the single test command, a sequence of taps applied to
the state leaves only the last one's order.

**Acceptance Scenarios**:

1. **Given** the ship flying to destination A, **When** the player taps point B, **Then** the order
   becomes B, the order to A is forgotten, and the ship comes to rest at B (006 FR-002).
2. **Given** two or more taps recognised between two frames, **When** the next frame applies them,
   **Then** they are applied in the order they happened, so the last one is the order flown.
3. **Given** a tap on the point the ship is already at, **When** the order is issued, **Then** the
   ship keeps station there; nothing is an error.

---

### User Story 3 - Every iPhone and iPad layout (Priority: P3)

A player rotates the iPhone to landscape, or uses the iPad app in a narrow Split View or Slide Over
pane, or resizes the pane while the ship is flying. Wherever they tap, the ship goes to the point under
the finger.

**Why this priority**: A property of stories 1 and 2 rather than a new behaviour, but the one that
breaks if the tap is converted against stale or wrong geometry.

**Independent Test**: Run the single test command: the conversion is tested for portrait, landscape,
narrow and odd-sized surfaces at backing scales 1, 2 and 3. Then on an iPad, use Split View at each
available width and tap near each corner.

**Acceptance Scenarios**:

1. **Given** surfaces of different shapes and sizes (portrait, landscape, a narrow Split View pane,
   1,001 × 667 points), **When** a tap at each corner and at the centre is converted, **Then** the
   world point is the one the camera puts under that view position (005 FR-004).
2. **Given** the same size in points at backing scales 1, 2 and 3, **When** the same tap is converted,
   **Then** the world point is identical.
3. **Given** the surface is resized and a tap follows, **When** the tap is applied, **Then** it is
   converted against the surface size in effect when the tap happened, never an older one.

---

### User Story 4 - The macOS click can reuse it (Priority: P4)

A developer starting SKY-11 adds a click recogniser on macOS. The order event, its trip into the loop
and the view → world conversion already exist and are platform-neutral, so the click needs only to
produce a view position in points and post it.

**Why this priority**: It saves duplicate work and keeps the two platforms identical, but does nothing
for players on its own.

**Independent Test**: Review: the order event and the conversion contain no iOS-only code, build on
both platforms, and are covered by tests that run on the Mac.

**Acceptance Scenarios**:

1. **Given** the macOS app is built, **When** it compiles, **Then** the order event and the
   conversion compile and their tests run, even though nothing on macOS posts the event yet.

### Edge Cases

- **Zero-area surface**: there is no camera (005 FR-008); a tap applied while the surface is zero-area
  is dropped. Nothing is an error and the current order, if any, is kept.
- **Tap during a resize**: the tap and the resize reach the loop in the order they happened, so the
  tap is converted against the geometry the player saw when they touched the screen.
- **Tap far off the visible ship**: the world is unbounded (005 FR-002); any visible point is a legal
  destination, however far from the ship.
- **Non-finite world point**: cannot arise from a real tap on a usable surface, but if it did, the
  order is rejected (006 FR-002) and the current order is kept.
- **Tap while backgrounded or before the first frame**: taps only reach the surface while it is on
  screen; one recognised just before the app is backgrounded is applied on the next frame drawn.
- **Touches that are not taps**: a touch that moves too far, lasts too long, or uses more than one
  finger is not a tap and issues no order. System edge gestures (home, Control Center, notification
  centre, Slide Over) keep working and issue no order.
- **Rapid taps**: each recognised tap is an order; a burst of them simply ends with the last one.
- **`--debug-ship-spin`**: the explicit spin input drives the ship and leaves the order alone
  (007 FR-013, 006 FR-011). A tap still sets the order, but the ship keeps spinning; this is the
  developer switch working as specified.
- **VoiceOver on**: the surface allows direct interaction (FR-014), so a tap orders the ship rather
  than only selecting the surface.
- **Renderer failure notice**: when the renderer could not be built, the failure notice is shown
  instead of the surface (001 FR-024) and there is nothing to tap.

## Requirements *(mandatory)*

### Functional Requirements

**Recognising a tap**

- **FR-001**: On iOS and iPadOS, a single-finger tap anywhere on the game surface MUST be recognised,
  with the platform's standard meaning of a tap: a touch that does not move or last beyond the
  system's tap limits. Touches that are not taps, and touches with more than one finger, MUST issue no
  order.
- **FR-002**: The tap's position MUST be taken in the surface's own view points, origin at its
  top-left corner, +y down — the space the camera's view → world mapping takes (005 FR-004). The whole
  surface MUST be tappable, including the areas outside the safe area.
- **FR-003**: Recognising taps MUST NOT interfere with the system's own gestures (home, Control
  Center, notifications, multitasking) or with the surface's existing size, scale and visibility
  reporting.

**Handing it to the loop**

- **FR-004**: The main thread MUST hand each recognised tap to the frame loop as a plain value
  carrying its view position, through the same non-blocking channel as the surface events
  (001 FR-029). The main thread MUST NOT wait for a frame, and the value's safety to transfer MUST be
  checked by the compiler (001 FR-030).
- **FR-005**: Taps and surface events MUST reach the loop and be applied in the order they happened,
  at a frame boundary and never mid-draw (001 FR-031). A tap applied on a frame takes effect in that
  frame's simulation advance.

**Turning it into an order**

- **FR-006**: The loop MUST convert the tap's view position to a world point with the camera for the
  surface in effect at that point in the event order (005 FR-004). If there is no camera for that
  surface (005 FR-008), the tap MUST be dropped and the current order, if any, kept.
- **FR-007**: The world point MUST become the ship's move order, replacing any current order whole
  (006 FR-002). If the point cannot become an order (006 FR-002), the tap MUST be dropped and the
  current order kept.
- **FR-008**: From then on the ship MUST be flown by the autopilot exactly as for any other order
  (006 FR-011). Nothing about the order's flight depends on how it was issued.
- **FR-009**: The logic layer MUST receive only a world point in world units. It MUST NOT learn about
  taps, views, points, screens, UIKit or SwiftUI (001 FR-010, FR-011).

**Sharing with macOS**

- **FR-010**: The value that carries an order request into the loop, and the view → world conversion
  it uses, MUST be platform-neutral: they MUST build on macOS too, so SKY-11's click can post the same
  value. Only the recognition of the tap itself is iOS-specific.

**Resources and determinism**

- **FR-011**: Recognising, handing over and applying taps MUST NOT allocate memory on the frame loop's
  per-frame path when no tap is pending, and MUST NOT add per-frame cost beyond what the existing event
  queue already does (001 FR-020). The one exception is FR-015's arrival check in Debug and Profiling
  builds: a single comparison per frame, allocation-free, absent from Release.
- **FR-012**: The same sequence of orders applied at the same ticks MUST produce the same simulation,
  bit for bit (001 FR-033): a tap only adds an order; it introduces no clock, randomness or I/O into
  the logic layer.

**Testability and accessibility**

- **FR-013**: How a tap's view position becomes a world point (or no point) for a given surface, and
  how an order request is applied to the simulation state, MUST be computable without a graphics
  device or a running app and verified by automated tests run by the project's single checked-in
  command (Principle II). Recognising the gesture is platform glue, verified on device and in the
  quickstart.
- **FR-014**: The surface's accessible description (001 FR-009) MUST stay as it is, and the surface
  MUST allow direct interaction for assistive technology, so that with VoiceOver on a tap on the
  surface reaches the game and orders the ship exactly as FR-001 to FR-008 describe.

**Observability (Debug and Profiling builds only)**

- **FR-015**: Each applied order MUST be logged once through the existing log-only instrumentation
  (001 FR-021d to FR-021f), with the tap's view position and the world destination; each arrival
  (the autopilot's phase becoming arrived, 006 FR-009) MUST be logged once with the ship's final
  position. Dropped taps MUST be logged with the reason (no camera, or not a valid order). Nothing is
  drawn on screen, the per-frame path stays allocation-free, and none of this exists in Release builds
  (as 002 FR-015, 003 FR-009).

### Key Entities

- **Tap**: one recognised single-finger tap on the surface; its position in view points, top-left
  origin, +y down. Exists only in the platform layer.
- **Order request**: the plain value the platform layer hands the loop: "order the ship to the world
  point under this view position". Platform-neutral, shared with SKY-11's click.
- **Move order**: the existing logic-layer order (006): a finite world destination. The only thing the
  logic layer sees of a tap.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On an iPhone and an iPad, a tap on any of at least nine points (the centre, the four
  corners and the four edge midpoints, each within 20 points of the edge) brings the ship to rest
  within 1 point (the arrival tolerance) of the world point under the tap.
- **SC-002**: The conversion tests show that for at least four surface shapes (portrait phone,
  landscape phone, narrow iPad Split View pane, 1,001 × 667 points) and backing scales 1, 2 and 3, the
  centre maps to the origin and the four corners to (±w/2, ±h/2) with +y up, each within 1e-9 units,
  and that the same view position on the same size in points gives the identical world point at every
  scale.
- **SC-003**: A tap during a flight replaces the order: in tests, applying taps A then B leaves B as
  the only order; on device, the ship comes to rest at B every time across at least five tries.
- **SC-004**: A tap on a zero-area surface issues no order and leaves any current order unchanged, in
  tests.
- **SC-005**: The order takes effect on the first frame after the tap is recognised: in tests, an order
  request applied at a frame boundary is the order that frame's simulation advance flies; on device,
  the ship visibly starts turning towards the tapped point with no perceptible delay.
- **SC-006**: With taps happening, frame times stay within budget (001 SC-003) and the per-frame
  allocation count on frames with no pending tap stays at zero (001 SC-004), measured as in 003.
- **SC-007**: In iPad Split View, at every width the system offers, and after resizing the pane while
  the ship is flying, taps near each corner send the ship there (SC-001's tolerance).
- **SC-007a**: With VoiceOver on, a tap on the surface sends the ship there, as in SC-001.
- **SC-007b**: In a Debug build, every applied order and every arrival appears once in the log with
  the values FR-015 names; SC-001's within-1-point check is read from those lines. A Release build
  logs none of them.
- **SC-008**: The macOS app builds, and the order request and conversion tests run there.
- **SC-009**: The project's single verification command passes, with every existing test still
  passing and the new tests running headlessly and deterministically.

## Assumptions

- **Standard tap**: the system's own tap recognition decides what counts as a tap (movement and
  duration limits); no custom thresholds are introduced.
- **Conversion in the loop**: the tap travels as a view position and is converted in the loop, against
  the surface the loop has applied up to that event, rather than on the main thread. This keeps the
  conversion consistent with the geometry being drawn and avoids a race with a resize.
- **No feedback yet**: the visible response to a tap is the ship turning towards the point. A
  destination marker is SKY-30; haptics and sound are not planned for this slice.
- **Debug overlay**: the overlay shows frame statistics only (003); showing the order or the
  autopilot's phase there is not part of this feature. The ship's motion is the evidence that a tap
  took effect.
- **VoiceOver**: the surface keeps its 001 label and allows direct interaction, so VoiceOver users
  tap to order like everyone else. Describing the order or the ship's movement aloud is deferred until
  the order overlay (SKY-30) exists to describe.
- **One ship, one order**: there is one ship (004) and one order at a time (006); a tap never queues
  orders.

## Dependencies

- **005-game-space-camera (SKY-23)**: the camera and its view → world mapping. Merged.
- **006-ship-autopilot (SKY-25)**: the move order and the autopilot that flies it. Merged.
- **007-ship-sprite-rendering (SKY-27)**: makes the result visible. Merged.
- **001**: the frame loop, its event channel and the layer boundaries. Merged.
- **Unblocks**: SKY-11 (click to order on macOS), and gives SKY-30 (order overlay) real orders to show.
