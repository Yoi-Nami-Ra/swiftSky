# Feature Specification: Game Space and Camera

**Feature Branch**: `005-game-space-camera`

**Created**: 2026-09-30

**Status**: Draft

**Input**: User description: "SKY-23 — Define the game space and camera" (`.tickets/23.yaml`, refined
2026-09-30). The world is flat and seen top-down. Units: 1 world unit = 1 point at the fixed zoom; the
ship is 40 units long, so its 80×80 px sprite is drawn at 40×40 pt; SKY-24's default limits stay.
Extent: unbounded — no edges, no wrapping, no collisions. Camera: fixed, the world origin at the
centre of the whole surface (not the safe area), 1 pt per unit; resizing shows more or less world and
nothing scales. Background: plain black. Scope: a camera value built from the render surface with
world → view, view → world and world → clip transforms; a ship-size constant of 40 units; a note for
SKY-27 that the sprite's top is the ship's front. Done when the camera is headlessly tested (origin at
the centre, corners at ±w/2, ±h/2 with +y up, round trip within 1e-9 points, clip edges at ±1), is
identical at 1×, 2× and 3× for the same size in points, follows a resize including odd point sizes,
yields no transform for a zero-area surface, and costs no per-frame allocation.

## Overview

The first gameplay slice (SKY-22) is a ship that the player orders around a flat, top-down world.
SKY-24 gave the simulation that ship and fixed the world's coordinate conventions: positions in world
units, heading zero along +x, positive angles counter-clockwise with +y up. What it did not fix is
how the world meets the screen: how long a world unit is, how much of the world is visible, and
where. Every ticket that places something on screen (the ship sprite, SKY-27; the order overlay,
SKY-30) or turns a tap or click into a place in the world (SKY-10, SKY-11) needs that answer first,
and needs the *same* answer.

This feature pins it down and gives those tickets one shared, tested camera:

- **Scale**: one world unit is one point on screen. The ship is 40 units long.
- **Extent**: the world has no edges. Nothing wraps and nothing collides.
- **View**: the camera never moves. The world's origin sits at the centre of the whole drawable
  surface, at one point per unit. A bigger window, full screen or a narrower iPad Split View pane
  shows more or less of the world around that centre; nothing is scaled and the origin never moves
  away from the centre.

Nothing new is visible. The surface stays plain black, and the debug overlay is unchanged. The value
of this feature is the camera and the scale that the next tickets build on.

Out of scope: drawing anything (the ship is SKY-27, the order overlay SKY-30), turning a tap or click
into an order (SKY-10, SKY-11), panning, zooming, following the ship, a grid or starfield (not
planned; each needs its own ticket), interpolation between ticks (SKY-12), world bounds, wrapping and
collisions, and any change to the ship's motion or its default limits.

### Relationship to earlier specs

- **Unchanged and still absolute**: every layer-boundary rule (001 FR-010, FR-013), no global mutable
  state (001 FR-015), no per-frame allocation (001 FR-020, FR-021f), 001 FR-027a (a zero-area surface
  is routine and must be skipped, never an error), and what the app draws in every configuration.
- **Settled**: 004's Assumptions left "how long a world unit is on screen" to SKY-23 and marked the
  default limits for retuning. This feature fixes the unit at one point and keeps the limits as they
  are (FR-012), so that open note is closed rather than carried forward.
- **Restated, not changed**: 004 FR-004's convention (heading zero along +x, counter-clockwise
  positive, +y up) is the camera's world convention. On screen, +y up means toward the top of the
  surface.
- **Reused**: the render surface's size in device pixels and its backing scale (001, 002 FR-006a) are
  everything the camera needs. Its safe-area insets are deliberately *not* used (FR-003).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers building swiftSky and the tickets that build on the
camera (SKY-10, SKY-11, SKY-27, SKY-30). Players see nothing new.

### User Story 1 - Place a world point on screen (Priority: P1)

A developer drawing the ship (SKY-27) has the ship's position in world units and needs to know where
it lands on the surface. They build the camera from the current surface and ask where a world point
appears, both as a position in points from the surface's top-left corner and in the normalised
coordinates the graphics hardware draws in. The world's origin comes out at the centre of the
surface, a point up and to the right of the origin appears up and to the right of the centre, and
the surface's edges are exactly where the world's visible edges are.

**Why this priority**: Nothing can be drawn in the right place without it, and it is the half of the
camera that SKY-27, the next ticket in the slice, needs.

**Independent Test**: Run the project's single test command. The camera tests build cameras for
known surfaces and compare mapped points against the expected positions.

**Acceptance Scenarios**:

1. **Given** a surface w points wide and h points tall, **When** the world origin is mapped to view
   points, **Then** it lands at (w/2, h/2), the surface's centre.
2. **Given** the same surface, **When** the four world points (±w/2, ±h/2) are mapped to view points,
   **Then** (−w/2, +h/2) lands at the top-left corner (0, 0), (+w/2, +h/2) at the top-right (w, 0),
   (−w/2, −h/2) at the bottom-left (0, h) and (+w/2, −h/2) at the bottom-right (w, h).
3. **Given** the same surface, **When** the world origin and the four corner points are mapped to
   the graphics hardware's normalised coordinates, **Then** the origin lands at (0, 0) and the
   corners at (±1, ±1) with +1 at the top and the right.
4. **Given** a world point one unit further along +x (or +y) than another, **When** both are mapped
   to view points, **Then** the second lands exactly one point to the right of (or above) the first.

---

### User Story 2 - Turn a screen position into a world point (Priority: P2)

A developer turning a tap or click into a move order (SKY-10, SKY-11) has a position in points from
the surface's top-left corner and needs the world point under it. They ask the camera, and the
answer, mapped back to the screen, is the position they started with.

**Why this priority**: The other half of the camera, needed by the input tickets that come after the
ship is visible. It is second because nothing can be ordered until something can be seen.

**Independent Test**: Run the single test command. The tests map known view positions to world
points and round-trip many points in both directions.

**Acceptance Scenarios**:

1. **Given** a surface w×h points, **When** the view position (w/2, h/2) is mapped to the world,
   **Then** the result is the world origin.
2. **Given** the same surface, **When** the top-left corner (0, 0) is mapped to the world, **Then**
   the result is (−w/2, +h/2), and the bottom-right corner (w, h) gives (+w/2, −h/2).
3. **Given** any view position whose coordinates are both within ±10⁶ points, **When** it is mapped
   to the world and back, **Then** the result is within 1e-9 points of where it started (SC-002).
4. **Given** a view position outside the surface (a pointer dragged past the window edge), **When**
   it is mapped to the world, **Then** it gives the world point that would be there; the world has
   no edges (FR-002).

---

### User Story 3 - The same world on every display and window size (Priority: P3)

A developer moves the window from a Retina display to a standard one, resizes it, makes it full
screen, or runs the iPad app in a narrow Split View pane. The world does not jump or scale: the same
world point stays the same distance from the centre in points, the origin stays at the centre, and
only the amount of world that fits around it changes.

**Why this priority**: A property of stories 1 and 2 rather than a behaviour of its own, but the one
that breaks first if the camera works in pixels instead of points, or anchors to a corner or the
safe area instead of the centre.

**Independent Test**: Run the single test command. The tests build cameras for the same point size
at three backing scales, for resized surfaces including odd point sizes, and for surfaces with
safe-area insets, and compare mapped points.

**Acceptance Scenarios**:

1. **Given** surfaces of the same size in points at backing scales 1, 2 and 3, **When** the same
   world point is mapped to view points on each, **Then** the three results are identical (SC-003).
2. **Given** a surface that is resized, **When** the camera is rebuilt from the new surface, **Then**
   the world origin maps to the new centre, including for odd point sizes such as 1,001 × 667, where
   the centre falls on a half point (500.5, 333.5) (SC-004).
3. **Given** two surfaces that differ only in their safe-area insets, **When** the same world point
   is mapped on each, **Then** the results are identical: the origin is the centre of the whole
   surface, not of the safe area (FR-003).
4. **Given** a surface with no area (zero width or zero height, as happens mid-resize or at
   teardown), **When** a camera is requested for it, **Then** there is none, rather than a transform
   that divides by zero (SC-005).

---

### User Story 4 - The running app is unchanged (Priority: P4)

A developer runs the app after this feature lands and sees exactly what they saw before: the same
black surface, the same debug overlay, the same log, the same frame times and no new allocations.

**Why this priority**: A gate rather than a feature. Nothing yet draws with the camera, so the app
must not change at all.

**Independent Test**: Run `./Scripts/verify.sh`, and launch a Debug build on both platforms.

**Acceptance Scenarios**:

1. **Given** the app built with this feature, **When** it is launched in Debug and Release on both
   platforms, **Then** what it draws is unchanged: the debug overlay in Debug, a uniformly black
   surface in Release and with `--no-debug-overlay` (SC-006).

### Edge Cases

- **Zero-area surface**: no camera exists for it (FR-008). The frame loop already skips drawing such
  a surface (001 FR-027a); anything that needs a camera does nothing until the surface has area again.
- **Unusable backing scale**: a backing scale that is zero, negative or not a finite number cannot
  convert pixels to points, so it is treated like a zero-area surface: no camera (FR-008). The same
  holds for a finite scale so extreme that the surface's size in points overflows to infinity or
  underflows below the smallest normal number; no display reports one, but the camera must still
  never hold a half-size it cannot divide by.
- **Odd and fractional point sizes**: a surface 1,001 points wide has its centre at 500.5, and one
  whose pixel size is not a whole multiple of the backing scale (e.g. 1,001 px at 2×) has a
  fractional width in points. Both are legal, and the camera uses the exact value rather than
  rounding it (FR-004).
- **Portrait-shaped surfaces**: iPad multitasking can hand the landscape-only app a surface taller
  than it is wide (001 FR-006b). The camera handles any aspect ratio; it simply shows more world
  vertically than horizontally.
- **Points off the surface**: world points beyond the visible edges map to view positions outside
  the surface and to normalised coordinates beyond ±1, and view positions outside the surface map to
  world points. None of these is an error (FR-002).
- **Very large world coordinates**: the ship can drift indefinitely (004). The camera is a pure
  mapping with no limits; how far from the origin a point is makes no difference beyond ordinary
  floating-point precision.
- **Non-finite world or view values**: mapping one passes it through as a non-finite result; the
  camera does not hide bad input from its caller.

## Requirements *(mandatory)*

### Functional Requirements

**The game space**

- **FR-001**: One world unit MUST be one point on screen. The world's convention is SKY-24's: +x to
  the right, +y up (toward the top of the surface), angles counter-clockwise positive (004 FR-004).
- **FR-002**: The world MUST be unbounded: no edges, no wrapping and no collisions. Every finite
  world point MUST map to a view position and every finite view position to a world point, whether
  or not it lies on the surface, with no clamping; the result is finite whenever it is representable
  (in practice, for any coordinate below 10¹² in magnitude at any real backing scale).

**The camera**

- **FR-003**: The camera MUST be fixed: the world origin at the centre of the whole drawable surface,
  at one point per unit, with no panning, zooming or following. The surface's safe-area insets MUST
  NOT affect it.
- **FR-004**: The camera MUST be built from the render surface alone. With w × h the surface's size
  in points (its size in device pixels divided by its backing scale, exactly, without rounding):
  - world → view points: a world point (x, y) MUST map to (w/2 + x, h/2 − y), measured in points from
    the surface's top-left corner with +y down;
  - view points → world: a view position (vx, vy) MUST map to (vx − w/2, h/2 − vy);
  - world → normalised device coordinates (clip space): a world point (x, y) MUST map to
    (x ÷ (w/2), y ÷ (h/2)), so the surface's left and right edges are −1 and +1, and its bottom and
    top edges −1 and +1.
- **FR-005**: The view → world mapping MUST be the inverse of the world → view mapping: any view
  position whose coordinates are both within ±10⁶ points, mapped to the world and back, MUST
  return within 1e-9 points.
- **FR-006**: For the same size in points, the camera MUST give identical results at every backing
  scale: it works in points, never in pixels.
- **FR-007**: When the surface changes (resize, full screen, Split View, moving to another display),
  a camera built from the new surface MUST place the origin at the new centre. The camera is a plain
  value: it MUST be rebuilt from the new surface rather than updated in place, and MUST NOT allocate
  memory to be built or to map points.
- **FR-008**: For a surface with zero width or zero height, or with a backing scale that is zero,
  negative or not finite, the camera MUST NOT exist: asking for one MUST give "no camera" rather than
  a transform, and nothing MUST ever divide by zero.

**The ship's size and sprite orientation**

- **FR-009**: The ship's length MUST be 40 world units, written in one place beside the camera so the
  ship sprite (SKY-27) and the order overlay's ship highlight (SKY-30) share it.
- **FR-010**: Beside that size, a note MUST record for SKY-27 that the ship sprite's top edge is the
  ship's front, so at heading zero (+x) the image is drawn rotated −90 degrees (a quarter turn
  clockwise).

**Placement, cost and testability**

- **FR-011**: The camera and the ship size MUST live in the rendering layer, so both the renderer and
  the platform layer's input code can use them, and MUST NOT depend on the platform layer (001 FR-010,
  FR-013). They MUST NOT require a graphics device.
- **FR-012**: The ship's default performance limits MUST stay as SKY-24 set them (200 units/s²
  thrust, 180°/s turn, 360°/s² angular acceleration), now read at one unit = one point. Any note in the
  code that marks them for retuning "once SKY-23 fixes the scale" MUST be updated to say the scale is
  now fixed.
- **FR-013**: What the app draws MUST NOT change: a plain black background, the debug overlay where it
  appears today, and nothing else.
- **FR-014**: The camera MUST be verifiable by automated tests that need no graphics device and no
  running app, run by the project's single checked-in test command (Principle II).

### Key Entities

- **Game space**: the flat, top-down, unbounded world. One unit is one point; +x right, +y up.
- **Camera**: the fixed mapping between the world and one drawable surface. Built from the surface's
  size in points; maps world points to view positions and to normalised device coordinates, and view
  positions to world points. Exists only for a surface with area.
- **View position**: a place on the surface, in points from its top-left corner, +y down — what the
  platform reports for a tap or click.
- **Normalised device coordinates (clip space)**: the −1…+1 square the graphics hardware draws into, +y up.
- **Ship size**: the ship's length, 40 world units, shared by everything that draws or highlights the
  ship.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For at least three surface sizes (including a portrait-shaped one), the world origin maps
  exactly to the surface's centre, the four world points (±w/2, ±h/2) map exactly to the four corners
  with +y up, and in normalised coordinates the origin maps to (0, 0) and the corners to (±1, ±1).
- **SC-002**: For at least 1,000 view positions spread across and beyond the surface, view → world →
  view returns within 1e-9 points of the start.
- **SC-003**: For the same size in points, cameras at backing scales 1, 2 and 3 map a set of world
  points to identical view positions and identical normalised coordinates.
- **SC-004**: After a resize, including to 1,001 × 667 points, the origin maps to the new centre
  (500.5, 333.5 for that size), and a surface's safe-area insets change no mapped value.
- **SC-005**: For a zero-width, a zero-height and a zero-area surface, and for backing scales of 0, a
  negative number and a non-finite number, no camera is produced, and no test observes a non-finite
  value from a camera that was produced.
- **SC-006**: The project's single verification command passes, with every existing test still passing
  and the new camera tests running headlessly and deterministically; and the app launched in Debug,
  in Debug with `--no-debug-overlay`, and in Release on both platforms draws exactly what it drew
  before.
- **SC-007**: Building a camera and mapping points performs no heap allocation, verified by the
  camera being a plain value with no reference-typed or growable storage.

## Assumptions

- **Points, not pixels**: one unit per point keeps the world the same physical size on every display,
  and makes the 80×80-pixel ship sprite pixel-exact at 40×40 points on 2× displays, the common case.
  On 1× and 3× displays the sprite is resampled; that is SKY-27's concern.
- **Whole surface, not safe area**: centring on the safe area would move the world whenever the
  device rotates or the insets change, and make the origin depend on hardware. The safe area remains
  what text and chrome use (002 FR-006a).
- **No live wiring yet**: nothing draws with the camera or reads input through it in this feature
  (Principle V). Each consumer builds one from the surface it already has, whenever that surface
  changes; since the frame loop replaces its surface only on a surface event, that is rebuilt only
  when the surface changes and never per frame.
- **Precision**: the camera uses the same double-precision numbers as the rest of the code, which is
  what makes the 1e-9-point round trip reachable.
- **No world bounds**: an unbounded world with a fixed camera means the ship can fly off screen and
  not return by itself. That is accepted for this slice; following the ship, if wanted, is its own
  ticket.

## Dependencies

- **004-ship-newtonian-motion (SKY-24)**: the world's coordinate conventions and the ship's default
  limits this feature confirms. Merged to `main`.
- **001-metal-app-shell and 002-metal-text-rendering**: the render surface (size in pixels, backing
  scale, safe-area insets) and its zero-area rule. Merged to `main`.
- **Unblocks**: SKY-27 (ship sprite), SKY-30 (order overlay), SKY-10 and SKY-11 (tap and click to
  order).
