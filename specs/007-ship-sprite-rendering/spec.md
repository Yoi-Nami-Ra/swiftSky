# Feature Specification: Ship Sprite Rendering

**Feature Branch**: `007-ship-sprite-rendering`

**Created**: 2026-10-01

**Status**: Draft

**Input**: User description: "SKY-27 — Render the ship sprite" (`.tickets/27.yaml`). Rendering layer.
Draw the ship from `design/sprites/ship.png` (80×80, with alpha; the top of the image is the ship's
front) at the ship's position and heading from the simulation state, through the camera from SKY-23.
Ship the image with the app and load it once at startup; a missing image is a renderer-initialisation
failure (as 001 FR-024, FR-026). Draw it as a textured quad blended over the black background, with
everything created once and reused (as 001 FR-002b) and nothing allocated per frame. Extend the
logic → render hand-off with the ship's pose; the renderer still never writes back to logic.
Supersedes 001's FR-002 (uniformly black surface), see SKY-22. Done when the ship shows at the world
origin facing heading zero on both platforms, rotates correctly, and holds its size and aspect across
window resizes.

## Overview

The first gameplay slice (SKY-22) is a ship the player orders around a flat, top-down world. The
simulation already has that ship (SKY-24) and flies it to a destination (SKY-25), and the camera
(SKY-23) says where any world point lands on screen. Nothing is drawn yet: the surface is still plain
black apart from the debug overlay. This feature makes the ship visible.

- **What**: the ship's image, drawn every frame where the ship is, pointing where the ship points,
  40 × 40 points in size (005 FR-009), over the black background and under the debug overlay.
- **Where from**: the ship's position and heading in the state the simulation hands the renderer each
  frame. The renderer reads them and never writes anything back.
- **At launch**: nothing gives the ship an order or an input yet, so the ship sits at the world origin,
  which is the centre of the surface, facing heading zero: its nose points to the right.

Out of scope: turning a tap or click into an order (SKY-10, SKY-11), the order overlay and planned
path (SKY-30, SKY-26), interpolation between ticks (SKY-12; the ship is drawn at the latest tick's
pose), engine flames, shadows, animation frames or any other ship art, more than one ship, and any
change to the camera, the ship's size or its motion.

### Relationship to earlier specs

- **Superseded**: 001 FR-002 (the rendered result is a uniformly black surface). The surface is now
  black *except for the ship* (FR-009). SKY-22 anticipated this. Every earlier check that expects a
  uniformly black surface either hides the ship with the new Debug-only switch (FR-014) or expects the
  ship at the centre instead (FR-015).
- **Unchanged and still absolute**: every pixel is drawn by the graphics pipeline (001 FR-001); the
  platform-UI layer shows nothing but the failure notice (001 FR-007); the layer boundaries (001 FR-010
  to FR-013); no global mutable state (001 FR-015); no per-frame allocation (001 FR-020, FR-021f); the
  sRGB, opaque, 8-bit surface (001 FR-002c); a zero-area surface is skipped, never an error
  (001 FR-027a); render-side interpolation stays out (001 FR-021c).
- **Extended**: the renderer-initialisation failures of 001 FR-024 and FR-026 gain one cause: the ship
  image is missing or unreadable (FR-005). 001 FR-012b still holds: the hand-off carries the ship's
  pose as simulation facts (where it is, which way it faces), not presentation concepts such as a
  colour or an image.
- **Reused**: the camera's world → clip mapping (005 FR-004), the ship's length of 40 units and the
  sprite-orientation note (005 FR-009, FR-010), the world convention of heading zero along +x,
  counter-clockwise positive (004 FR-004), and the Debug/Profiling launch-argument mechanism and its
  absence from Release builds (002 FR-015, 003 FR-009).

## Clarifications

### Session 2026-10-01

- Q: Should the drawn ship snap to whole surface pixels? → A: Yes — the drawn centre snaps to the
  nearest whole surface pixel, so the image is pixel-exact at quarter turns on every surface size.
- Q: Should the surface's accessible description include the ship? → A: No — 001 FR-009's
  description is unchanged; describing the ship waits for the order tickets (SKY-10, SKY-11, SKY-30).
- Q: Which copy of the ship image is the source of truth? → A: `design/sprites/ship.png`; any copy
  bundled with the app must be byte-identical to it, checked by the single verification command.

## User Scenarios & Testing *(mandatory)*

The users of this feature are players, who see the ship for the first time, and the developers
building the next tickets (SKY-10, SKY-11, SKY-30), who need to see where the ship is.

### User Story 1 - See the ship at launch (Priority: P1)

A player launches the app on a Mac or an iPhone or iPad. Over the black background, at the centre of
the window or screen, is the ship: the image from `design/sprites/ship.png`, 40 × 40 points, its nose
pointing to the right. Its edges are clean against the black: no box, fringe or halo around it.

**Why this priority**: This is the feature. Without it nothing in the slice can be seen.

**Independent Test**: Launch a Debug build (with and without the debug overlay) and a Release build
on both platforms and look at the centre of the surface; take a screenshot and measure the ship's
bounding box and orientation.

**Acceptance Scenarios**:

1. **Given** the app has just launched, **When** the first frames are drawn, **Then** the ship is
   centred on the surface's centre, drawn from the ship image, and its front (the image's top edge)
   points toward the right edge of the surface.
2. **Given** the ship is drawn at heading zero, **When** its size is measured on screen, **Then** it
   is 40 × 40 points: 80 × 80 pixels at 2×, 40 × 40 at 1×, 120 × 120 at 3×.
3. **Given** the ship image's transparent and partly transparent pixels, **When** it is drawn over the
   black background, **Then** fully transparent pixels leave the background black, and partly
   transparent pixels blend smoothly with no light or dark fringe and no visible rectangle.
4. **Given** the debug overlay is showing, **When** a frame is drawn, **Then** the overlay's text is
   drawn on top of the ship wherever the two overlap.

---

### User Story 2 - The ship turns the way the simulation says (Priority: P2)

A developer launches a Debug build with the spin switch (FR-013). The ship turns in place at the
centre, counter-clockwise, at the ship's maximum turn rate (half a turn a second): its nose passes the
top of the surface a quarter of a second after passing the right, then the left, then the bottom. The
image never stretches or shears as it turns. In a test, the ship's drawn corners are checked for many
headings and positions.

**Why this priority**: A ship drawn facing the wrong way, or turning the wrong way, would make every
later ticket look broken. It is second because the ship does not move until orders exist, so at launch
only heading zero is visible.

**Independent Test**: Run the project's single test command: the tests compute where the ship's four
corners land for known poses and surfaces, with no graphics device. Then launch a Debug build with the
spin switch and watch the ship turn.

**Acceptance Scenarios**:

1. **Given** a ship at heading zero, **When** the ship's drawn corners are computed, **Then** the
   image's top edge is the right-hand edge on screen (the image is turned a quarter turn clockwise).
2. **Given** a ship at heading +π/2 (a quarter turn counter-clockwise), **When** its corners are
   computed, **Then** the image is upright: its top edge is at the top of the surface. At ±π its front
   points to the left; at −π/2 it points to the bottom.
3. **Given** any heading, **When** the corners are computed, **Then** the drawn shape is a 40 × 40
   point square in the surface's points, centred on the ship's position, and its four sides stay equal
   and perpendicular: turning never distorts it.
4. **Given** a ship somewhere other than the origin, **When** its corners are computed, **Then** the
   square is centred on the camera's view position for the ship's world position (005 FR-004).
5. **Given** a Debug build launched with the spin switch, **When** it runs, **Then** the ship turns
   counter-clockwise in place, as described above.

---

### User Story 3 - The same ship in any window (Priority: P3)

A player resizes the Mac window, makes it full screen, moves it between a Retina and a standard
display, or uses the iPad app in a narrow Split View pane. The ship stays at the centre of the surface
and stays 40 × 40 points, square: it never stretches with the window's shape and never grows or
shrinks with the window's size.

**Why this priority**: A property of stories 1 and 2 rather than a new behaviour, but it is the one
that breaks first if the ship is sized in clip space or pixels rather than points.

**Independent Test**: Run the single test command: the tests compute the ship's corners for wide,
tall, odd-sized and differently scaled surfaces. Then resize the window on the Mac and use Split View
on the iPad.

**Acceptance Scenarios**:

1. **Given** surfaces of different sizes and shapes (wide, tall, 1,001 × 667 points), **When** the
   ship's corners are computed, **Then** the ship is 40 × 40 points on each, centred on the surface.
2. **Given** surfaces of the same size in points at backing scales 1, 2 and 3, **When** the corners
   are computed in points, **Then** they are identical.
3. **Given** the Mac window is resized continuously by dragging, **When** frames are drawn, **Then**
   the ship stays centred, square and the same size throughout.

---

### User Story 4 - A missing ship image stops the app with a reason (Priority: P4)

A developer ships a build in which the ship image is missing or cannot be read. The app does not
start with an invisible ship: it shows the text-only failure notice saying the ship image could not be
loaded, logs a diagnostic naming the cause, and exits, exactly as for the renderer's other
initialisation failures.

**Why this priority**: A safety net for a packaging mistake; it never happens in a correct build.

**Independent Test**: Run the single test command: the error's user-facing description and diagnostic
code are tested. Optionally, remove the image from a built app and launch it.

**Acceptance Scenarios**:

1. **Given** the ship image is missing from the built app, **When** the app launches, **Then** the
   failure notice (001 FR-024) names the missing ship image, the log has a diagnostic with a stable
   code for it (001 FR-026), and the app then exits.
2. **Given** the image exists but cannot be decoded, or is not 80 × 80 pixels, **When** the app
   launches, **Then** the same happens, with the same code.

### Edge Cases

- **Zero-area surface**: there is no camera (005 FR-008) and the frame is skipped as before
  (001 FR-027a). Nothing is drawn; this is not an error.
- **Ship off screen**: the world is unbounded (005 FR-002), so a ship that flies away can leave the
  surface. It is simply not visible, or partly visible at an edge; nothing clamps it and nothing is an
  error. Bringing it back is not this feature's job.
- **Very far from the origin**: positions of any finite size are drawn wherever the camera puts them.
  While the ship is within 10⁶ units of the origin, its drawn centre is the whole pixel nearest the
  camera's view position (SC-003); beyond that, ordinary floating-point precision applies.
- **Heading at the wrap point**: the simulation keeps the heading within (−π, π] (004 FR-005).
  Headings of π and a hair above −π look the same; the drawing must not jump when the heading wraps.
- **Backing scale changes mid-run** (moving the window between displays): the ship keeps its size in
  points. At 1× and 3× the image is resampled from its 80 × 80 pixels; it must still look smooth, with
  no shimmer as it turns.
- **Portrait-shaped surface** (iPad multitasking, 001 FR-006b): the ship is still square and centred.
- **Odd-sized surfaces**: a surface whose centre falls on a half pixel (for example 1,001 pixels wide)
  would put the ship between pixels; the centre is snapped to a whole pixel instead (FR-006a), so the
  ship is never blurred by its position.
- **Debug text checks**: `--debug-text-fill` fills the text capacity from the top-left corner and can
  reach the centre; 002's text checks, which compare drawn text with the system's, take `--no-ship`
  where the two could overlap.
- **Debug overlay over the ship**: the overlay sits top-left inside the safe area and the ship at the
  centre; on a very small surface they can overlap, and the overlay's text wins (User Story 1,
  scenario 4).

## Requirements *(mandatory)*

### Functional Requirements

**The hand-off**

- **FR-001**: The state the logic layer hands the renderer each frame MUST include the ship's pose:
  its position in world units and its heading in radians, from the same tick as everything else in
  that state. The renderer MUST read the pose from that state every frame and MUST NOT write to the
  logic layer's state or influence it in any way (001 FR-012, FR-012b).

**The ship image**

- **FR-002**: The ship's image MUST be `design/sprites/ship.png`, 80 × 80 pixels with an alpha
  channel, shipped inside both apps. That design file is the source of truth: any copy the build
  bundles MUST be byte-identical to it, and the project's single verification command MUST fail if
  the two differ, so they can never drift apart.
- **FR-003**: The image MUST be loaded into graphics memory exactly once, while the renderer is set up
  at launch, and reused for every frame thereafter. Nothing about it may be reloaded, re-decoded or
  re-uploaded per frame or on a resize.
- **FR-004**: The image MUST be drawn with its colours as designed: treated as sRGB and blended so that
  a pixel's colour over black is its colour weighted by its alpha, with no brightened or darkened
  edges. Pixels with zero alpha MUST leave the background exactly as it was.
- **FR-005**: If the image is missing, cannot be decoded, is not 80 × 80 pixels, or cannot be placed in
  graphics memory,
  renderer initialisation MUST fail with its own cause: the failure notice (001 FR-024) MUST say the
  ship image could not be loaded, and the diagnostic (001 FR-026) MUST carry a stable code for it.

**Drawing**

- **FR-006**: The ship MUST be drawn every frame as a square 40 × 40 points in size (the ship's length,
  005 FR-009), centred on the camera's view position for the ship's position (005 FR-004), snapped to
  the nearest whole surface pixel (FR-006a), except where FR-012 or FR-014 says it is not drawn.
- **FR-006a**: The drawn centre MUST be rounded to the nearest whole surface pixel (in device pixels,
  after the camera mapping), so the drawn centre is never more than half a pixel from the camera's
  view position. With the ship's size a whole, even number of pixels at 1×, 2× and 3×, this puts the
  image's pixel grid on the surface's at every quarter turn, on every surface size.
- **FR-007**: The ship MUST be drawn rotated by (heading − π/2), counter-clockwise positive in world
  space, so that the image's top edge — the ship's front (005 FR-010) — points along the ship's
  heading: to the right at heading zero, up at +π/2, left at π, down at −π/2.
- **FR-008**: The ship's shape on screen MUST NOT depend on the surface's size, aspect ratio or backing
  scale: it is square and 40 points on a side on every surface, and at every rotation.
- **FR-009**: Supersedes 001 FR-002. Each frame MUST show the black background (drawn as before,
  001 FR-002a, FR-002c), then the ship over it, then any debug text over both. Nothing else is drawn.
- **FR-010**: The image MUST be sampled smoothly, so that at 1× and 3× backing scale and at any
  rotation it shows no jagged edges, shimmer or missing lines. At 2× and heading zero or any multiple
  of a quarter turn, each image pixel MUST land on exactly one surface pixel, on surfaces of any size,
  odd or even (FR-006a).
- **FR-011**: Everything the ship's drawing needs — its pipeline, the image in graphics memory, its
  geometry and any buffer it writes per frame — MUST be created once at initialisation and reused
  (as 001 FR-002b). Drawing the ship MUST NOT allocate memory per frame (001 FR-020).
- **FR-012**: When there is no camera for the surface (005 FR-008), the ship MUST NOT be drawn; with a
  zero-area surface the whole frame is already skipped (001 FR-027a).

**Debug switches (Debug and Profiling builds only)**

- **FR-013**: A launch argument `--debug-ship-spin` MUST make the ship turn counter-clockwise in place
  at its maximum turn rate, for the whole run, by feeding the simulation a full-turn, zero-thrust
  input every tick. It MUST NOT change how anything is drawn: it only makes rotation visible before
  orders exist.
- **FR-014**: A launch argument `--no-ship` MUST stop the ship being drawn, so that together with
  `--no-debug-overlay` the surface is uniformly black again and every earlier check that expects that
  still applies. It MUST NOT change the simulation.
- **FR-015**: Neither switch, nor its parsing, nor any text naming it, MUST exist in Release builds
  (as 002 FR-015, 003 FR-009). A Release build always draws the ship and never spins it. Earlier
  checks that expect a uniformly black Release build now expect a black surface with the ship at its
  centre, facing right.

**Placement and testability**

- **FR-016**: The ship's drawing MUST live in the rendering layer; the choice of launch arguments in the
  platform layer; the ship's pose and motion stay in the logic layer (001 FR-010, FR-013).
- **FR-016a**: The rendering surface's accessible description (001 FR-009) MUST stay as it is: the
  ship is not described to assistive technology in this feature.
- **FR-017**: How the ship's corners are placed for a given pose and surface MUST be computable without
  a graphics device and verified by automated tests run by the project's single checked-in command
  (Principle II), covering headings, positions, surface shapes and backing scales. How the image looks
  on screen is verified visually (Principle II exempts render code).

### Key Entities

- **Ship pose**: where the ship is (a world position) and which way it faces (a heading in radians),
  as of the latest tick. Part of the state the logic layer hands the renderer; simulation facts, not
  presentation.
- **Ship image**: the 80 × 80 pixel design file with alpha, whose top edge is the ship's front. Loaded
  once.
- **Ship sprite placement**: the four corners of the 40 × 40 point square the image is drawn into, for
  one pose on one surface, computed through the camera.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On both platforms, a freshly launched app (Debug with and without the overlay, and
  Release) shows the ship centred on the surface within one pixel, its nose pointing to the right, and
  measuring 40 × 40 points (80 × 80 pixels on a 2× display) within one pixel.
- **SC-002**: For at least the eight headings in steps of π/4, the computed corners put the image's top
  edge along the heading, with every corner within 1e-6 points of its expected place.
- **SC-003**: For at least three surface shapes (wide, tall, 1,001 × 667 points) and backing scales 1,
  2 and 3, the computed ship is a square 40 points on a side (each side within 1e-6 points, each
  corner angle 90° within 1e-6 radians) whose centre is a whole surface pixel no more than half a
  pixel from the camera's view position for the ship, for positions up to 10⁶ units from the origin;
  and for the same size in points, the unsnapped placement in points is identical at 1×, 2× and 3×.
- **SC-004**: With `--debug-ship-spin`, once it has reached full rate (within the first second), the
  ship completes one counter-clockwise turn every 2 seconds (±5%) and stays centred and undistorted throughout.
- **SC-005**: Resizing the Mac window through at least five sizes, including one taller than it is
  wide, and using iPad Split View, leaves the ship centred and 40 × 40 points every time.
- **SC-006**: A build without the ship image shows the failure notice naming the ship image and logs
  its diagnostic code, and never presents a frame.
- **SC-007**: With the ship drawn and the overlay showing, frame times stay within budget (001 SC-003)
  and the draw path's allocation count stays at zero (001 SC-004), measured as in 003.
- **SC-008**: With `--no-ship --no-debug-overlay` a Debug build is uniformly black, and the 001 and 002
  checks that expect that still pass; a Release build contains no trace of either switch.
- **SC-008a**: The verification command fails if the bundled ship image differs by one byte from
  `design/sprites/ship.png`.
- **SC-009**: The project's single verification command passes, with every existing test still
  passing and the new placement tests running headlessly and deterministically.

## Assumptions

- **Latest tick, no interpolation**: the ship is drawn at the pose of the latest tick. At 60 Hz ticks on
  a 120 Hz display the ship moves every other frame; smoothing that is SKY-12.
- **No per-frame image work**: the image is small (80 × 80), so loading it once and keeping it for the
  whole run costs nothing worth measuring against the memory budget.
- **Smooth sampling**: at 2× the 80-pixel image is pixel-exact when axis-aligned; at 1× it is shown at
  half size, and at 3× at one and a half times, both of which need smooth filtering to look right. A
  small, fixed set of pre-shrunk copies of the image, made once at launch, is an acceptable way to keep
  the 1× case clean.
- **The switches are developer tools**: `--debug-ship-spin` exists because nothing else can turn the
  ship until orders arrive (SKY-10, SKY-11); `--no-ship` exists so the earlier black-surface checks stay
  runnable. Both follow the existing double-dash, Debug-only launch-argument pattern.
- **The pose is already there**: the state handed to the renderer already carries the whole ship (004);
  "extending the hand-off" means the renderer now reads the ship's position and heading, not that new
  fields must be added. Nothing else from the ship (velocity, turn rate, limits) or from the autopilot is
  used for drawing in this feature.
- **The image is final**: the art may change later, but a replacement with the same size, alpha and
  orientation needs no code change.

## Dependencies

- **004-ship-newtonian-motion (SKY-24)**: the ship, its pose and the heading convention. Merged.
- **005-game-space-camera (SKY-23)**: the camera, the 40-unit ship length and the orientation note.
  Merged.
- **006-ship-autopilot (SKY-25)**: merged; not used here, but the ship it flies is the ship drawn.
- **001, 002, 003**: the render pipeline, failure notice and diagnostic, text drawing order, and the
  Debug-only launch-argument pattern. Merged.
- **Unblocks**: SKY-30 (order overlay), and makes SKY-10 and SKY-11 (tap and click to order) visible.
