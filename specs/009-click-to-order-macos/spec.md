# Feature Specification: Click to Order the Ship on macOS

**Feature Branch**: `009-click-to-order-macos`

**Created**: 2026-10-01

**Status**: Draft

**Input**: User description: "SKY-11 — Click to order the ship on macOS" (`.tickets/11.yaml`). Part of
SKY-22, the macOS counterpart of SKY-10 (spec 008). A primary mouse click (or trackpad tap-to-click) on
the game surface posts the existing order request from 008, with the click position turned from the
platform's bottom-left origin into the surface's top-left points; the loop, conversion, order and
logging are reused unchanged. A new click mid-flight replaces the current order. Keyboard and game
controller input are out of scope. Done when clicking anywhere in the window sends the ship there at
any window size, including full screen, and the screen → world conversion (including the flip) is
unit-tested.

## Overview

On iOS, a tap sends the ship to the point under the finger (008). On the Mac nothing does yet: the ship
sits at the centre of the window. This feature lets the player click anywhere in the window and have
the ship fly there and stop, exactly as a tap does on iOS.

- **What**: one primary click on the surface becomes one move order to the world point under the
  pointer.
- **Where it goes**: the click's position is read in the surface's own points, turned from the Mac's
  bottom-left origin into the top-left origin the camera's view space uses (005 FR-004), and posted as
  the same order request a tap posts (008 FR-010). From there everything is 008's: the frame loop
  converts it against the surface it has applied, the ship gets the order, and the autopilot flies it.
- **Replacing**: a click while the ship is still flying replaces the current order at once.

Out of scope: keyboard and game-controller input (the ticket), drag-to-steer, secondary (right or
Control) clicks, the destination marker and planned path (SKY-30, SKY-26), VoiceOver ordering on macOS,
and any change to the order request, the frame loop, the camera, the ship, the autopilot or the drawing.

### Relationship to earlier specs

- **Reused unchanged**: the order request, its event and its trip into the loop, the conversion against
  the applied surface, the dropped-request rules and the Debug order and arrival logging (008 FR-004 to
  FR-012, FR-015); the camera's view → world mapping (005 FR-004, FR-008); the move order (006).
- **Completes**: 008 FR-010, which made the order request platform-neutral so that this click could post
  it. 008's iOS tap is unaffected.
- **Unchanged and still absolute**: the layer boundaries (001 FR-010, FR-011); the main thread never
  waits for a frame (001 FR-029); no per-frame allocation (001 FR-020); the platform-UI layer draws
  nothing (001 FR-007); the surface's accessible description (001 FR-009).

## Clarifications

### Session 2026-10-01

- Q: Should the first click on a window that is not frontmost also order the ship? → A: No. It only
  brings the window to the front, as is the Mac convention; later clicks order the ship.
- Q: Which clicks order the ship? → A: The primary button only, with or without Command, Option or
  Shift. Control-click is a secondary click and issues no order, and so do the middle and other mouse
  buttons.

## User Scenarios & Testing *(mandatory)*

The users of this feature are players on the Mac, with a mouse or a trackpad, and the developers of
SKY-30, who need real orders on both platforms.

### User Story 1 - Click to send the ship (Priority: P1)

A player launches the app on a Mac. The ship sits at the centre of the window, nose to the right. The
player clicks somewhere up and to the left of it. The ship turns to face that point, burns towards it,
flips, brakes and comes to rest under the pointer, then stays there.

**Why this priority**: This is the feature. It makes the Mac build playable.

**Independent Test**: Launch a Debug build on a Mac, click a few points in the window, and check that
the ship comes to rest under each one, and that each `order` line's world point matches its `arrived`
line within the arrival tolerance.

**Acceptance Scenarios**:

1. **Given** the ship at rest with no order, **When** the player clicks a point on the surface,
   **Then** the ship receives a move order to the world point under the pointer and comes to rest there
   within the arrival tolerances (006 FR-010).
2. **Given** a click at the exact centre of the surface, **When** the order is issued, **Then** its
   destination is the world origin.
3. **Given** a click near the top of the window, **When** the order is issued, **Then** its destination
   is above the origin (positive y), and a click near the bottom gives negative y: the click is never
   mirrored top to bottom.
4. **Given** a trackpad with tap to click turned on, **When** the player taps the trackpad, **Then** it
   orders the ship exactly as a physical click does.

---

### User Story 2 - A new click changes the plan (Priority: P2)

The ship is mid-flight. The player clicks somewhere else. The ship abandons the old destination at once
and flies to the new one.

**Why this priority**: Without it the player has to wait for each flight to finish. Second because
008's request already replaces orders; this story proves it for clicks.

**Independent Test**: In a Debug build, click far away, then click a second point before the ship
arrives; the ship comes to rest at the second point, and only one `arrived` line follows.

**Acceptance Scenarios**:

1. **Given** the ship flying to A, **When** the player clicks B, **Then** the order becomes B and the
   ship comes to rest at B.
2. **Given** a double-click, **When** both clicks are recognised, **Then** each is an order to the same
   point, which ends exactly as one would.

---

### User Story 3 - Any window size, full screen and any display (Priority: P3)

The player resizes the window, makes it full screen, or drags it to a display of a different
resolution. Wherever they click, the ship goes to the point under the pointer.

**Why this priority**: A property of stories 1 and 2, but the one that breaks if the flip uses the
wrong height or the click is read against stale geometry.

**Independent Test**: Run the single test command: the click-position turn is tested for wide, tall,
odd-sized and full-screen-sized surfaces at backing scales 1 and 2. Then resize the window through
several sizes, go full screen, and click near each corner.

**Acceptance Scenarios**:

1. **Given** surfaces of different sizes (wide, tall, 1,001 × 667 points, a full-screen size),
   **When** a click at each corner and at the centre is turned into a view position and converted,
   **Then** the world point is the one the camera puts under that position: the bottom-left corner of
   the window is (−w/2, −h/2), the top-right (w/2, h/2).
2. **Given** the same size in points at backing scales 1 and 2, **When** the same click is converted,
   **Then** the world point is identical.
3. **Given** the window is resized or made full screen, **When** the player clicks, **Then** the click
   is read against the size in effect when it happened (008 FR-005, FR-006).

### Edge Cases

- **First click on an inactive window**: the first click on a window that is not frontmost only brings
  it to the front, as Mac apps normally do, and issues no order. Clicks on the frontmost window order
  the ship.
- **Secondary and other clicks**: a right click, a two-finger trackpad click, a click with Control
  held, and a middle or other-button click issue no order.
- **Modifier keys**: a primary click with Command, Option or Shift held orders the ship like a plain
  click.
- **Drags**: pressing, moving and releasing is not a click and issues no order.
- **Clicks outside the surface**: the title bar, the window's edges while resizing, and the full-screen
  menu bar are not the surface; clicks there do what the system does and issue no order.
- **Full screen with a camera housing**: the surface fills the whole screen; where the housing hides
  part of it, nothing can be clicked, and that is not an error.
- **Zero-area surface** (a window collapsing mid-resize): 008's rule applies, and the click is dropped
  with the current order kept.
- **Click held past the edge**: a press that starts on the surface and is released outside it is not a
  click on the surface and issues no order.
- **`--debug-ship-spin`**: as on iOS (008), a click sets the order and the ship keeps spinning.
- **Renderer failure notice**: there is no surface to click.

## Requirements *(mandatory)*

### Functional Requirements

**Recognising a click**

- **FR-001**: On macOS, a single primary click on the game surface MUST be recognised: a press and
  release of the primary mouse button, or a trackpad tap with tap to click on, without moving beyond
  the system's click limits, with or without Command, Option or Shift held. Secondary clicks (right
  button, two-finger click, Control-click), middle and other-button clicks, and drags MUST issue no
  order.
- **FR-002**: Each recognised click MUST issue exactly one order. A double-click is two clicks.
- **FR-003**: The first click on a window that is not frontmost MUST only bring the window to the front
  and MUST issue no order, following the platform's convention for inactive windows.
- **FR-004**: The click's position MUST be turned into the surface's view space: points from the
  surface's top-left corner, +y down (005 FR-004). The platform reports positions from the bottom-left
  corner, +y up, so the turn is (x, h − y), with h the surface's height in points at the moment of the
  click. The whole surface MUST be clickable, at any window size and in full screen.
- **FR-005**: Recognising clicks MUST NOT interfere with window moving, resizing, full screen, the
  menu bar or the surface's existing size, scale and visibility reporting.

**Handing it on**

- **FR-006**: The click MUST be posted as 008's order request, through the same non-blocking channel,
  so that everything after it — the ordering against surface events, the conversion against the applied
  surface, dropped requests, replacing the order, the autopilot and the Debug logging — is 008's,
  unchanged (008 FR-004 to FR-012, FR-015).
- **FR-007**: No part of the order request, the frame loop, the logic layer or the rendering layer may
  change for this feature (001 FR-010, 008 FR-010).

**Testability and accessibility**

- **FR-008**: How a click's platform position becomes a view position for a given surface height MUST be
  computable without a window, a view or a graphics device and verified by automated tests run by the
  project's single checked-in command (Principle II), together with the resulting world point through
  008's order request. Recognising the click is platform glue, verified in the quickstart.
- **FR-009**: The surface's accessible description (001 FR-009) MUST stay as it is. Ordering the ship
  through VoiceOver on macOS is not part of this feature.

### Key Entities

- **Click**: one recognised primary click on the surface; its position in the surface's points, origin
  bottom-left, +y up, as the platform reports it. Exists only in the platform layer, in macOS code.
- **Order request**: 008's platform-neutral value, now posted by clicks as well as taps. Unchanged.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On a Mac, a click on any of at least nine points (the centre, the four corners and the four
  edge midpoints, each within 20 points of the edge) brings the ship to rest within 1 point of the world
  point under the pointer, read from the Debug log.
- **SC-002**: The tests show that for at least four surface sizes (wide, tall, 1,001 × 667 points and a
  full-screen size) at backing scales 1 and 2, a click at the bottom-left, top-left, top-right,
  bottom-right corners and the centre gives world points (−w/2, −h/2), (−w/2, h/2), (w/2, h/2),
  (w/2, −h/2) and (0, 0), each within 1e-9 units.
- **SC-003**: A click mid-flight replaces the order: the ship comes to rest at the second point every
  time across at least five tries.
- **SC-004**: Right clicks, Control-clicks, middle clicks (where a mouse has one), drags and the first
  click on an inactive window issue no order, and Command-, Option- and Shift-clicks do, every time,
  across at least three tries each.
- **SC-005**: After resizing the window through at least five sizes, including one taller than it is
  wide, and in full screen, clicks near each corner send the ship there (SC-001's tolerance).
- **SC-006**: With clicks happening, frame times stay within budget (001 SC-003), and frames without a
  click still allocate nothing (001 SC-004), compared before and after on the same Mac.
- **SC-007**: The project's single verification command passes, with every existing test, including
  008's, still passing, and the new tests running headlessly and deterministically.

## Assumptions

- **Standard click**: the system decides what counts as a click (movement and timing limits) and what is
  a secondary click; no custom thresholds are introduced.
- **Inactive windows**: Mac apps conventionally let the first click on an inactive window only activate
  it, so a click meant for another app's window cannot accidentally send the ship. A game could choose
  otherwise; this one follows the convention.
- **The flip uses the surface's own height**: the click is read in the surface's coordinates, and the
  surface fills the window's content area, so no window chrome is involved.
- **No feedback yet**: the visible response is the ship turning towards the point. A destination marker
  is SKY-30.
- **VoiceOver**: macOS has no equivalent of the iOS direct-interaction trait for this surface; ordering
  through VoiceOver is deferred, as describing the ship was in 007.

## Dependencies

- **008-tap-to-order-ios (SKY-10)**: the order request and everything after it. Merged.
- **005-game-space-camera (SKY-23)** and **006-ship-autopilot (SKY-25)**: merged; used through 008.
- **Unblocks**: SKY-30 (order overlay) with real orders on both platforms; completes SKY-22's input.
