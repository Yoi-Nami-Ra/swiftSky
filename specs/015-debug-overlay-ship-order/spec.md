# Feature Specification: Ship and Order Lines on the Debug Overlay

**Feature Branch**: `015-debug-overlay-ship-order`

**Created**: 2026-10-05

**Status**: Draft

**Input**: User description: "SKY-34 — Show the ship and the order on the debug overlay" (`.tickets/34.yaml`).
SKY-29 shipped the live debug overlay with its frame-stat lines only; its ship and order lines were left
to follow once SKY-24 and SKY-25 landed. Both have (specs/004-ship-newtonian-motion,
specs/006-ship-autopilot), so this ticket adds them to the overlay in Debug and Profiling builds: the
ship (position, velocity, speed, heading, angular velocity) and the active order (autopilot phase,
destination, distance remaining), with a "no order" line when there is none. Same refresh rate as the
existing lines (4 Hz), same Metal text renderer, still absent from Release. Done when the new lines show
live values on both platforms in Debug, stay absent from a Release build (as SKY-29's symbol check), and
add no per-frame allocation. The ticket's suggested fixed-order launch argument is not needed: orders
now come from taps (008) and clicks (009).

## Overview

The debug overlay (003) shows six lines of frame statistics in the top-left corner of the surface in
Debug and Profiling builds. The ship now flies (004), the autopilot flies it to an ordered point (006),
and a tap or click gives that order (008, 009). What the ship is actually doing — where it is, how fast
it moves, which way it faces, which phase of the order it is in and how far it still has to go — can
today be seen only indirectly, from the sprite and from the order and arrival log lines.

This feature adds that data to the overlay, under the existing six lines, in the same block, at the same
four-times-a-second refresh, drawn by the same text renderer. Release builds still contain none of it.

The values are the simulation's own, as of its latest completed tick — not the interpolated pose the
sprite is drawn at (013) — because the overlay is a measuring instrument: it must report what the
simulation holds, not a drawing approximation of it.

Out of scope: any change to the six frame-statistic lines, to the log output, to the order overlay
(014), or to the ship, autopilot or order rules; the planned path's figures (010), which stay in the log
line; a launch argument that gives a fixed order; per-line toggles; a background panel; and any
player-facing heads-up display.

### Relationship to earlier specs

- **Extended**: 003's overlay gains the lines of FR-001–FR-004 below, and its snapshot (003 FR-006)
  gains the ship and order values. 003's allocation-free number writing gains a signed form (FR-006).
- **Unchanged and still absolute**: 003 FR-002/FR-003 (drawn by the pipeline, 13-point white text, 8
  points in from the safe area's top-left), FR-005 (no line longer than 33 characters within normal
  ranges), FR-006 (4 Hz refresh, last snapshot drawn every frame), FR-009 (absent from Release),
  FR-010 (not exposed to assistive technology), FR-011 (`--no-debug-overlay` hides it all), FR-012
  (`--debug-text` and `--debug-text-fill` replace it), FR-013 (the log is unchanged), FR-014 (no
  per-frame allocation, 011 check 25) and FR-015 (the renderer is handed plain values).
- **Respected**: 013's rule that the debug overlay shows exact tick values, not the drawn pose; 014's
  rule that the debug overlay is drawn on top of the order overlay.

## Clarifications

### Session 2026-10-05

- Q: Are the ship values the latest tick's or the drawn (interpolated) pose? → A: The latest tick's
  (013), taken at the 4 Hz refresh together with the frame statistics (FR-005).
- Q: How are numbers written? → A: Two decimals, rounded to the nearest hundredth, signed, right-aligned
  in a fixed column, without allocating (FR-006).
- Q: In what unit are heading and turn rate shown? → A: Degrees, with the ASCII units ` deg` and
  ` deg/s`, since the text renderer has no `°` (FR-002).
- Q: How is the phase written? → A: Lower case, as named: `aligning`, `burning`, `flipping`,
  `braking`, `arrived` (FR-003).
- Q: What is shown without an order? → A: One line, `order   none`, and no destination or distance
  line (FR-004).
- Q: What is shown after arrival? → A: The order lines stay, with the phase `arrived`, for as long as
  the ship keeps station on that order (FR-003).
- Q: Where do the new lines go? → A: Under the existing six, in the same top-left block (FR-001).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers building swiftSky. Players see nothing new.

### User Story 1 - Developer reads the ship's live state (Priority: P1)

A developer runs a Debug build and, under the frame statistics, reads the ship's position, velocity,
speed, heading and turn rate, refreshed four times a second. At launch the ship is at rest at the origin,
so every value reads zero. With `--debug-ship-spin` the heading sweeps round and the turn rate reads the
ship's top rate.

**Why this priority**: The ship lines are the base of the feature and need no order to check.

**Independent Test**: Launch a Debug build with no arguments, then with `--debug-ship-spin`, and read
the overlay from a screenshot.

**Acceptance Scenarios**:

1. **Given** a Debug build launched with no arguments, **When** the overlay appears, **Then** the ship
   lines of FR-002 are drawn under the six frame-statistic lines, reading position `0.00`, `0.00`,
   velocity `0.00`, `0.00`, speed `0.00`, heading `0.00` and turn `0.00`.
2. **Given** a Debug build launched with `--debug-ship-spin`, **When** the ship has reached its top turn
   rate, **Then** the turn line reads `180.00 deg/s`, and the heading line changes at every refresh and
   stays within −180 to 180 degrees.
3. **Given** the ship is flying an order, **When** the overlay refreshes, **Then** speed equals the
   length of the shown velocity to within the shown precision, and the position moves in the direction
   of the shown velocity.

---

### User Story 2 - Developer follows an order on the overlay (Priority: P2)

A developer taps (iOS) or clicks (macOS) to give an order and watches the order lines: the phase steps
through aligning, burning, flipping and braking to arrived, the destination shows the ordered world
point, and the distance remaining falls towards zero. Before any order the overlay says there is none.

**Why this priority**: This is the autopilot's debugging aid, and the reason the ticket exists, but it
needs US1's layout first.

**Independent Test**: Launch a Debug build, read `order   none`, give an order with a tap or click, and
watch the lines until the ship arrives.

**Acceptance Scenarios**:

1. **Given** a Debug build with no order given, **When** the overlay is drawn, **Then** the last line is
   `order   none`, and there is no destination or distance line.
2. **Given** an order has just been given, **When** the next refresh comes, **Then** the order line
   shows the autopilot's phase, the destination line shows the ordered world point, matching the
   `world=` value of the order log line to two decimals, and the distance line shows the distance from
   the ship's shown position to it.
3. **Given** the ship has arrived, **When** the overlay refreshes, **Then** the order line reads
   `arrived`, the destination stays, and the distance is at most the arrival tolerance (1 unit).
4. **Given** a new order replaces one in flight, **When** the next refresh comes, **Then** the
   destination is the new point and the phase is the new order's.

---

### User Story 3 - The new lines cost nothing per frame and stay out of Release (Priority: P3)

A developer confirms that the added lines allocate nothing per frame, and that a Release build contains
none of their labels or code.

**Why this priority**: These are gates rather than features, and need US1 and US2 to exist.

**Independent Test**: Run 011's allocation check (check 25) with the overlay showing and an order in
flight; inspect a Release build's symbols and strings as 003's check 16 does.

**Acceptance Scenarios**:

1. **Given** the overlay is showing and an order is being flown, **When** per-frame allocations are
   counted over a sustained run with the optimised instrumented build, **Then** there are zero,
   including on refresh frames.
2. **Given** a Release build, **When** its symbols and strings are inspected, **Then** none of the new
   labels, units or phase texts are present.

---

### User Story 4 - Developer verifies the new lines without a GPU (Priority: P4)

A developer changes how a value is formatted or a line is laid out, and checks it with the project's
single test command, with no graphics device and no running app.

**Why this priority**: Signed formatting, degree conversion and the order/no-order layouts are logic
with edge cases (Principle II); nothing visible depends on this story.

**Independent Test**: Run the checked-in test command headlessly and confirm the new tests run and pass.

**Acceptance Scenarios**:

1. **Given** values such as 0, −0.004, −0.005, 12.345, −1,234.5 and 99,999.99, **When** they are
   written signed, **Then** the tests confirm the exact text and alignment for each.
2. **Given** a snapshot with and without an order, and with each phase, **When** the overlay is written,
   **Then** the tests confirm the exact lines.

### Edge Cases

- **No order** (launch, before the first tap or click): one `order   none` line (FR-004).
- **Arrived and keeping station**: the order lines stay, reading `arrived` (FR-003).
- **Tiny negative values** that round to zero (for example a velocity of −0.004): written `0.00`, never
  `-0.00`, so a ship at rest never shows a stray minus sign (FR-006).
- **Large values**: the world is unbounded (005), so a position or distance can exceed the column. It is
  written in full, never cut short and never in exponent notation; the line grows wider and may run off
  the right edge, as 003 FR-005 allows. Values beyond what the writer can hold are clamped, not trapped
  on.
- **Heading at the seam**: heading is shown in (−180, 180], so a heading of exactly π reads `180.00`,
  never `-180.00`.
- **The ship is not drawn** (`--no-ship`): the ship and order lines are still shown, since the ship is
  still simulated.
- **Interpolation off** (`--no-interpolation`): no difference to the overlay, which never shows the
  drawn pose.
- **Frames between refreshes**: the lines keep showing the values from the last refresh, like the frame
  statistics (003 FR-006).
- **`--no-debug-overlay`, `--debug-text`, `--debug-text-fill`**: unchanged; the new lines go with the
  overlay (003 FR-011, FR-012).
- **Before the first refresh**: nothing of the overlay is drawn, as today.

## Requirements *(mandatory)*

### Functional Requirements

**Layout**

- **FR-001**: In Debug and Profiling builds, the overlay MUST show the lines of FR-002–FR-004 below its
  six existing lines, in the same block, same text, same placement, in this order: position, velocity,
  speed, heading, turn, order, and — with an order only — destination and distance. Each line MUST start
  with an eight-column label, as the frame statistics' lines do.
- **FR-002**: The ship lines MUST read:
  - `pos     x` *x* ` y` *y* — the ship's position, in world units.
  - `vel     x` *x* ` y` *y* — its velocity, in world units per second.
  - `speed   ` *s* ` u/s` — the length of that velocity.
  - `heading ` *h* ` deg` — its heading, in degrees, in (−180, 180], 0 along +x, counter-clockwise
    positive as in the simulation.
  - `turn    ` *t* ` deg/s` — its angular velocity, in degrees per second, counter-clockwise positive.
- **FR-003**: With an order, the order lines MUST read:
  - `order   ` followed by the autopilot's phase in lower case: `aligning`, `burning`, `flipping`,
    `braking` or `arrived`.
  - `dest    x` *x* ` y` *y* — the order's destination, in world units.
  - `dist    ` *d* ` u` — the distance from the ship to the destination, in world units.

  The order lines stay after arrival, reading `arrived`, for as long as that order is held.
- **FR-004**: Without an order, the overlay MUST show the single line `order   none`, and no destination
  or distance line.
- **FR-005**: The ship and order values MUST be the simulation's own, as of its latest completed tick at
  the moment of the overlay's refresh — the same snapshot moment as the frame statistics (003 FR-006) —
  and never the interpolated pose the ship is drawn at (013). Between refreshes, the last snapshot's
  values are drawn every frame.

**Formatting**

- **FR-006**: Every number on the new lines MUST be written rounded to the nearest hundredth with exactly
  two decimals, with a leading `-` for a negative value, right-aligned in a nine-column field (which
  holds `-99999.99`). A value that rounds to zero MUST be written `0.00`, without a sign. A wider value
  MUST be written in full, never cut short and never in exponent notation. All of it MUST be written
  without allocating memory.
- **FR-007**: Within normal ranges — positions and distances under 100,000 units, speeds under 100,000
  units per second — no new line may be longer than 33 characters (003 FR-005).
- **FR-008**: All text on the new lines MUST be printable ASCII, so every character is drawn by the
  existing text renderer.

**Builds, cost and boundaries**

- **FR-009**: The new lines, labels, units and phase texts MUST be compiled into Debug and Profiling
  builds only. A Release build MUST contain none of them (003 FR-009).
- **FR-010**: Showing the new lines, including taking the snapshot, MUST NOT allocate memory on the
  per-frame path (003 FR-014, 011 check 25).
- **FR-011**: The ship and order snapshot MUST be handed to the rendering layer as plain values, as the
  frame statistics are (003 FR-015). It MUST NOT carry the planned path.
- **FR-012**: The log output, the six frame-statistic lines, the ship sprite, the order overlay and the
  simulation MUST be unchanged.
- **FR-013**: Formatting and line composition MUST be verifiable by automated tests that need no
  graphics device, run by the project's single test command (Principle II).

### Key Entities

- **Ship and order snapshot**: the ship's position, velocity, heading and angular velocity, and, when an
  order is held, its phase, destination and distance remaining, taken from the simulation state at the
  overlay's refresh. Plain values only.
- **Overlay text**: the six frame-statistic lines followed by the five ship lines and one or three order
  lines.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On iOS and on macOS, a Debug build launched with no arguments shows the five ship lines
  and `order   none` under the frame statistics within one refresh of the overlay appearing, fully inside
  the safe area, confirmed by a screenshot on each platform.
- **SC-002**: After a tap (iOS) or click (macOS), the order lines appear within one refresh (0.25 s), the
  destination matches the order log line's `world=` value to two decimals, and the phase reaches
  `arrived` with a distance of at most 1.00.
- **SC-003**: With `--debug-ship-spin`, the turn line reads `180.00 deg/s` once the ship is at its top
  rate, and the heading line never reads outside −180.00 to 180.00.
- **SC-004**: Zero heap allocations per frame with the overlay showing and an order in flight, over a
  sustained run of at least 60 seconds, measured as in 011's check 25.
- **SC-005**: A Release build contains none of the new labels, units or phase texts, confirmed with
  `nm` and `strings` as in 003's check 16.
- **SC-006**: The new formatting and layout tests pass headlessly and deterministically on the project's
  single test command.

## Assumptions

- **Degrees**: the overlay is read by people; the simulation keeps radians. The ship's limits are already
  described in degrees per second (004).
- **Units**: one world unit is one point (005); the overlay writes `u` for it.
- **Phase on one line**: the ticket's "no order" line and the phase share the `order` label, so the order
  block is one line without an order and three with one.
- **Distance**: the simulation's own distance remaining (006) is shown, not one recomputed from the
  rounded figures.
- **Capacity**: the whole overlay stays near 350 of the text renderer's 1,024 characters, and fourteen
  lines fit inside a landscape iPhone's safe area at 13-point text.
- **Checks**: tap- and click-driven checks need a person at the device; launch-only checks can be run
  from screenshots.

## Dependencies

- **003-debug-overlay (SKY-29)**: the overlay, its snapshot and its Release symbol check. Merged.
- **004, 006, 008, 009**: the ship, the autopilot and the tap and click orders. Merged.
- **011**: the allocation check (check 25) and its optimised instrumented build. Merged.
- **013, 014**: the drawn pose this feature does not use, and the order overlay drawn under it. Merged.
