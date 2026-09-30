# Feature Specification: Metal Text Rendering

**Feature Branch**: `002-metal-text-rendering`

**Created**: 2026-09-30

**Status**: Draft

**Input**: User description: "SKY-28 — Render text in Metal via a glyph atlas. Rendering layer, needed by the debug overlay (SKY-29). Rasterise a monospaced system font into a glyph atlas texture once at startup, and draw strings as textured quads through one pipeline. No third-party dependencies. Everything visible stays Metal-drawn (FR-001, FR-007), which is why SwiftUI text is not used. Text is built into a fixed-capacity vertex buffer from a fixed-size character buffer, so updating it every frame allocates nothing (FR-021f). ASCII only is enough for the debug overlay. Sized for the display's backing scale so it stays sharp on Retina. Done when a test string renders crisply on both platforms at 1× and 2× backing scale, and the allocation check (as in SKY-3/SKY-4) stays at zero with text updating every frame."

## Overview

swiftSky draws every visible pixel itself (001 FR-001), and its platform layer may not draw any
content of its own (001 FR-007). That rules out using the platform's text views, so the game cannot
show a single word on screen until its own rendering pipeline can draw text.

This feature adds that capability and nothing more. It prepares the images of a small, fixed set of
characters once, then draws strings from them every frame, crisply at whatever pixel density the
display has, without allocating memory on the per-frame path. The only visible result is a test
string that proves it works. The first real consumer is the live debug overlay (SKY-29), which is a
separate feature.

Out of scope: the debug overlay itself and its content (SKY-29), decimal and fixed-point number
formatting, player-facing text, localisation, any character outside printable ASCII, multiple
fonts, sizes or colours, and text input.

### Relationship to 001-metal-app-shell

- **Superseded**: 001 FR-002 ("a uniformly black surface, with no other content of any kind") is
  relaxed only for the test string, in Debug and Profiling builds, and only when the developer opts
  in at launch (FR-015, FR-015a). In every other case, including every Release build, the surface stays
  uniformly black.
- **Unchanged and still absolute**: 001 FR-001 (every visible pixel comes from the rendering
  pipeline), FR-007 (the platform layer draws no content), FR-012b (the tick count does not affect
  visible output), FR-020 and SC-004 (no per-frame allocation), FR-021e (instrumentation reports
  only to the log; drawing instrumentation on screen is SKY-29's change, not this one), and every
  layer-boundary rule.
- **Extended**: 001's Render Surface, the description of the drawable surface that the platform
  layer gives the renderer, gains safe-area insets alongside its size and backing scale (FR-006a).
  The addition is additive. It still crosses the thread boundary as a value, as 001 FR-030 requires.

## Clarifications

### Session 2026-09-30

- Q: When should the test string appear in Debug and Profiling builds? → A: Only when the developer
  opts in at launch. Without the opt-in, those builds stay uniformly black, so 001's checks are
  unaffected (FR-015, SC-006).
- Q: Should the text-rendering capability ship in Release builds? → A: Yes. It is present in Release
  but nothing there uses it, and there is no build-configuration gating in the renderer. Only the
  test string and its opt-in are limited to Debug and Profiling builds (FR-016, SC-006).
- Q: Where does the test string's per-frame counter come from? → A: From a count of frames drawn,
  kept by the rendering layer. It is not the simulation's tick count, so 001 FR-012b stays unchanged
  (FR-014). *Superseded during implementation, see the FPS bullet below.*
- Q: Where on an iOS screen is the test string placed? → A: 8 points in from the top-left corner
  of the safe area. The platform layer passes the safe-area insets to the renderer and updates them
  whenever they change (FR-006a, FR-006b).
- Q: How is the full-capacity frame-time check (SC-004, US3) produced? → A: With a second
  Debug/Profiling-only launch opt-in. It fills exactly the 1,024-character capacity every frame
  with copies of the test string, rewritten every frame. Release ignores it (FR-015a, SC-004,
  SC-006).
- Q (during implementation): Should the fourth line show a frame counter or FPS? → A: FPS,
  replacing the counter. It shows the whole number of frames drawn in the past second, updated once
  a second, measured from the frame loop's per-frame timestamp rather than a second clock read. The
  text is still rewritten every frame, so the per-frame write path that SC-003 measures is still
  exercised (FR-014, SC-003).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers building swiftSky. Players see nothing new.

### User Story 1 - Developer sees crisp text on macOS (Priority: P1)

A developer runs a Debug build on a Mac and sees the test string drawn over the black surface near
the top-left corner. It is sharp on the Retina built-in display, and still sharp after they drag the
window to a standard-resolution external display.

**Why this priority**: This proves the whole path from character images to pixels on screen. Every
later use of text depends on it, and macOS is where development happens.

**Independent Test**: Launch a Debug build on a Mac with the test string enabled. Capture the window
at native resolution on a 2× display and on a 1× display, and compare it with the reference check in
SC-001.

**Acceptance Scenarios**:

1. **Given** a Debug build with the test string enabled on a 2× display, **When** the window
   appears, **Then** the test string is legible, every character is recognisable, and no glyph edge
   looks blurred or doubled at native resolution.
2. **Given** the same window, **When** the developer moves it onto a 1× display, **Then** within one
   second the text is redrawn at 1× density with the same size in points, and it is equally sharp.
3. **Given** the window is resized, **When** it redraws, **Then** the text stays the same size in
   points and stays 8 points in from the top-left corner of the safe area (FR-006b).

---

### User Story 2 - Developer sees crisp text on iOS (Priority: P2)

A developer runs a Debug build on an iPhone or iPad and sees the same test string, equally sharp at
that device's pixel density.

**Why this priority**: iOS is a first-class platform (001 US2), and the debug overlay must work on
both platforms. It comes second only because the rendering path is shared, so most risk is already
retired by US1.

**Independent Test**: Launch a Debug build with the test string enabled on a 2× device and a 3×
device, capture a screenshot of each, and compare them with the reference check in SC-002.

**Acceptance Scenarios**:

1. **Given** a Debug build with the test string enabled on a 2× or 3× device, **When** the app
   launches, **Then** the test string is legible and sharp at that density.
2. **Given** the device is rotated, including to landscape with the camera cutout on the left,
   **When** the surface redraws, **Then** the text keeps its size in points, and it stays fully
   visible 8 points in from the top-left corner of the safe area, never under the cutout or a
   rounded corner.

---

### User Story 3 - Text changes every frame without cost (Priority: P3)

The test string is rewritten on every frame, and its FPS line changes once a second. The developer
runs a sustained session while measuring, and sees that rewriting the text allocates no memory on the
per-frame path and does not push the frame time over budget.

**Why this priority**: The debug overlay (SKY-29) rewrites its text continuously. If changing text
cost allocations or frame time, the overlay would disturb the very numbers it shows. Checking this
needs US1 or US2 working first.

**Independent Test**: Run the allocation check used by SKY-3 and SKY-4 for 60 seconds with the
test string rewritten every frame. Then measure frame time three ways: with no text, with the test
string, and with the full-capacity opt-in (FR-015a).

**Acceptance Scenarios**:

1. **Given** the test string is updating every frame, **When** allocations on the per-frame draw
   path are measured over a sustained run, **Then** there are zero.
2. **Given** the app is launched with the full-capacity opt-in, so 1,024 changing characters are
   drawn every frame, **When** frame time and per-frame allocations are measured, **Then** frame
   time stays within 001's frame budget and allocations stay at zero.

---

### User Story 4 - Developer verifies text layout without a GPU (Priority: P4)

A developer changes how text is laid out: which character image goes where, line breaks, or what
happens to unsupported characters and overflow. They check the change by running the project's
single test command on any machine, with no graphics device and no running app.

**Why this priority**: Layout has real logic and real edge cases, and the constitution requires
tests for it (Principle II). It adds nothing visible, so it comes last.

**Independent Test**: Run the checked-in test command headlessly and confirm the layout tests run
and pass.

**Acceptance Scenarios**:

1. **Given** a string that mixes letters, digits, punctuation, spaces, a line break and a non-ASCII
   character, **When** it is laid out, **Then** the tests confirm each character's cell position,
   the line break's effect, and the replacement glyph for the non-ASCII character.
2. **Given** more characters than the capacity allows, **When** they are laid out, **Then** the
   tests confirm that exactly the first capacity-many characters are placed and the rest are
   dropped.

### Edge Cases

- **Non-ASCII character** (é, emoji, a control character other than line feed): drawn as the
  replacement glyph, taking one cell (FR-003). It never crashes, and it is never dropped silently.
- **More text than capacity**: characters beyond the capacity are dropped from the end, and this is
  reported to the log once per run (FR-011).
- **Empty string**: nothing is drawn, and the rest of the frame is unaffected.
- **Text running past the surface edge**: it is clipped at the edge. There is no wrapping (FR-005).
- **Backing scale changes mid-run** (macOS window moved between displays): character images are
  prepared again at the new density (FR-010). This one-off event may allocate. Ordinary frames may
  not.
- **Safe area changes** (rotation, iPad Split View resize, macOS full screen on a display with a
  camera housing): the test string moves to the new safe-area corner on the next frame drawn after
  the change. It is never drawn under the cutout (FR-006a, FR-006b).
- **Zero-area or hidden surface**: no text is drawn, because no frame is drawn (001 FR-008, FR-027a).
- **Character images cannot be prepared at startup** (font unavailable, or not enough GPU memory):
  the app keeps running without text and logs a diagnostic (FR-018). It does not show the
  renderer-failure notice, because text is not essential to the app.
- **Consecutive line breaks, or a line break at the end**: each one advances a line. A trailing
  break draws nothing extra.

## Requirements *(mandatory)*

### Functional Requirements

**Source of glyphs**

- **FR-001**: Text MUST be drawn by the game's own rendering pipeline, in the same frame as the rest
  of the surface and on top of it. No platform text view, label or overlay may be used (001 FR-001,
  FR-007).
- **FR-002**: Character images MUST be produced from the platform's built-in monospaced system font.
  No font files may be bundled, and no third-party dependency may be added.
- **FR-003**: The supported characters are printable ASCII, from space to tilde (95 characters).
  Every other character except line feed MUST be drawn as a single replacement glyph, `?`, taking
  one cell.
- **FR-004**: Everything needed to draw text MUST be prepared once, at startup, and MUST NOT be
  rebuilt per frame (mirrors 001 FR-002b). The one exception is the character images: they depend
  on the display's backing scale, which is first known when a frame is drawn. So they are prepared
  on the first frame drawn, and again only on a backing-scale change (FR-010).

**Layout and appearance**

- **FR-005**: Each character MUST occupy one fixed-width cell. A line feed MUST start a new line at
  the string's left edge, one line height below the previous line. Text MUST NOT wrap. Anything past
  the surface edge MUST be clipped.
- **FR-006**: A string's position MUST be given in points, measured from the top-left corner of the
  surface. The caller chooses where to place text (SKY-29 for the overlay).
- **FR-006a**: The renderer MUST receive the surface's safe-area insets (top, left, bottom and
  right, in points) from the platform layer, together with the surface's size and scale. The
  platform layer MUST send updated insets whenever they change: rotation, resizing, iPad
  multitasking, or entering and leaving full screen. On macOS the insets are whatever the window
  reports, which is normally zero. Callers use the insets to keep text clear of cutouts and rounded
  corners.
- **FR-006b**: The test string MUST be placed 8 points in from the top-left corner of the safe area,
  on both platforms and in every orientation.
- **FR-007**: Text MUST be drawn at one fixed size of 13 points, in opaque white, with anti-aliased
  edges blended over whatever is underneath.
- **FR-008**: Text MUST keep its size in points when the surface is resized or rotated. The test
  string MUST keep its position 8 points in from the top-left corner of the safe area (FR-006b).

**Sharpness**

- **FR-009**: Character images MUST be prepared at the display's backing scale (1×, 2× or 3×), so
  that one pixel of a character image covers exactly one physical pixel. Each character cell MUST
  start on a whole physical pixel, so no glyph is resampled between pixels.
- **FR-010**: When the backing scale changes while the app is running, text MUST be prepared again
  at the new scale and shown correctly within one second. Text at the wrong density MUST NOT be
  shown for longer than that.

**Capacity and per-frame cost**

- **FR-011**: Text MUST have a fixed capacity of 1,024 characters per frame across all strings. Line
  feeds do not count. Characters beyond the capacity MUST be dropped from the end without failure,
  and the first overflow in a run MUST be reported to the log.
- **FR-012**: Changing the text on every frame, up to the full capacity, MUST NOT allocate memory on
  the per-frame path (001 FR-020, FR-021f, SC-004).
- **FR-013**: Callers MUST be able to write text, including non-negative whole numbers up to the
  largest 64-bit value, into the text without allocating memory, so the FPS value in the test string
  can be rewritten every frame for free. A number may be zero-padded to a minimum width. A number longer
  than that width is written in full, never cut short.

**Builds and the test string**

- **FR-014**: The test string MUST contain all 95 supported characters in character-code order,
  split into three lines: space to `@`, `A` to the backtick, and `a` to tilde. Each line is at most
  33 characters, so it fits across the narrowest surface iOS can give this landscape-only app
  (iPad Slide Over, about 320 points; 001 FR-006b). A fourth line MUST show the frame rate, for
  example `fps 120`:
  - the value is the whole number of frames drawn in the past second, updated once a second;
  - until the first full second has been measured, the line reads `fps --`;
  - after a pause of more than a quarter of a second (the app hidden, say), measuring starts again,
    so the gap does not drag the value down;
  - frames are counted by the rendering layer and timed with the timestamp the frame loop already
    reads once per frame (001 FR-033), with no second clock read;
  - it MUST NOT be taken from Simulation State: 001 FR-012b (the tick count does not affect visible
    output) stays in force.
  The whole test string is rewritten every frame, even when the FPS value has not changed.
- **FR-015**: The test string MUST be drawn only in Debug and Profiling builds, and only when the
  developer opts in at launch. Without the opt-in, those builds MUST show the uniformly black
  surface of 001 FR-002, so that 001's visible-output checks still pass unchanged. In Release builds
  the opt-in MUST have no effect.
- **FR-015a**: A second launch opt-in, also limited to Debug and Profiling builds, MUST fill exactly
  the 1,024-character capacity on every frame. It does so with copies of the test string placed one
  under another from the same safe-area anchor, with the last copy cut short to fit and every copy
  rewritten each frame. Characters clipped at the surface edge still count toward the
  capacity. Filling exactly the capacity MUST NOT trigger the overflow report (FR-011). If both
  opt-ins are given, this one wins. In Release builds it MUST have no effect.
- **FR-016**: In Release builds, the surface MUST stay uniformly black exactly as 001 FR-002 defines.
  The text-rendering capability itself MUST be present in Release builds, and nothing in Release
  may use it. It MUST NOT be compiled conditionally by build configuration. Only the test string
  and the two opt-ins (FR-015, FR-015a) are limited to Debug and Profiling builds.
- **FR-017**: 001's other rules for visible output (FR-002a to FR-002c) MUST still hold for the part
  of the surface not covered by text.

**Failure and testability**

- **FR-018**: If character images cannot be prepared on the first frame drawn (FR-004), the app MUST continue to run and
  render without text, and MUST log a diagnostic that names the cause. It MUST NOT show the 001
  renderer-failure notice, and it MUST NOT crash. The same applies if preparing them again after a
  backing-scale change (FR-010) fails: text stops being drawn rather than being shown at the wrong
  density.
- **FR-019**: Text layout MUST be verifiable by automated tests that need no graphics device and are
  run by the project's single checked-in test command (Principle II). This covers character-to-cell
  mapping, line breaks, the replacement glyph, capacity truncation and pixel-grid alignment.
- **FR-020**: Text drawn by this feature MUST NOT be exposed to assistive technology. It is
  developer-facing debug content. The surface's accessible description (001 FR-009) is unchanged.

### Key Entities

- **Character set**: the 95 printable ASCII characters plus the replacement glyph. Fixed for this
  feature.
- **Glyph images**: the prepared images of every supported character at the current backing scale,
  and the size and position of each within the prepared set. Built once, and rebuilt only on a scale
  change.
- **Safe-area insets**: the top, left, bottom and right distances, in points, that keep content
  clear of cutouts and rounded corners. They are part of the surface description the platform
  layer gives the renderer, alongside size and backing scale (FR-006a).
- **Font metrics**: the cell width, line height and baseline of the monospaced font at 13 points,
  in points and in physical pixels at the current scale.
- **Text buffer**: a fixed-capacity, reusable store of up to 1,024 characters, each with its
  position. Callers write into it, and the renderer reads from it each frame.
- **Laid-out text**: for each character, the physical-pixel rectangle it covers on the surface and
  the glyph image it shows. This is derived from the text buffer and the font metrics by pure,
  testable logic.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On macOS, at 2× and at 1× backing scale, in a screenshot captured at native
  resolution:
  - the height of the test string's capital letters, in physical pixels, equals the 13-point
    font's own cap height in points × the scale, to within 1 pixel;
  - a reviewer comparing it side by side with the same string in the system's own 13-point
    monospaced text finds no blurring, doubling or uneven stroke weight.
- **SC-002**: The same checks as SC-001 pass on iOS on a 2× device and a 3× device.
- **SC-003**: With the test string rewritten every frame, zero heap allocations occur in the per-frame
  draw path over a sustained 60-second run on each platform. This is measured with the same check
  as SKY-3 and SKY-4.
- **SC-004**: With the full-capacity opt-in (FR-015a), meaning 1,024 characters rewritten every
  frame, mean and worst frame time stay within 001's frame budget, and per-frame allocations stay at
  zero over a sustained 60-second run. Measurements with no text, with the test string and with full
  capacity are taken on the same device with 001's method, and recorded as the before/after evidence
  Principle III requires.
- **SC-005**: Text preparation adds no more than 2 MB to the idle memory footprint, measured as the
  difference between launching without text and launching with the full-capacity opt-in, on the same
  device and build. 001's absolute baseline is not yet recorded (SKY-31, SKY-32), and a difference
  measured on one device stays valid without it. The app still reaches its first visible frame within 001 SC-001's
  1 second.
- **SC-006**: A Release build shows a uniformly black surface with no text on both platforms, even
  when launched with either opt-in (FR-015, FR-015a). A Debug build launched without the opt-in also shows a
  uniformly black surface, and it passes 001's visible-output checks unchanged.
- **SC-007**: Every one of the 95 supported characters is drawn as its own distinct glyph, and a
  non-ASCII character is drawn as the replacement glyph. This is confirmed by the automated layout
  tests, and by one visual check of the test string, which contains all 95 (FR-014).
- **SC-008**: The layout tests pass headlessly and deterministically on 10 consecutive runs of the
  single test command, with no graphics device available.

## Assumptions

- **Standalone spec**: SKY-28 is specified on its own as spec 002, even though SKY-22 planned spec
  002 to cover the whole click-to-move slice with SKY-28 as one child. The SKY-22 slice will take the
  next number. The supersessions SKY-22 listed are therefore split: this spec relaxes 001 FR-002
  only for the test string, and relaxing FR-021e for the on-screen overlay stays with SKY-29.
- **Size and colour**: a single size of 13 points and a single colour, white, are enough for a
  debug overlay. Configurable sizes or colours would be speculative (Principle V).
- **ASCII only**: there is no kerning, ligatures, right-to-left text, emoji or localisation, as the
  ticket states.
- **No Dynamic Type**: Principle IV's Dynamic Type and VoiceOver requirements cover player-facing
  UI. Debug text is developer-only. Any later player-facing use of this capability must revisit
  this.
- **Capacity**: 1,024 characters covers the planned overlay (about 12 lines of up to 60 characters)
  with room to spare.
- **Number formatting**: only whole numbers are needed here, for the FPS value. Allocation-free
  decimal formatting for frame times belongs to SKY-29.
- **Test devices**: a 1× check on macOS needs a standard-resolution display, or a display mode that
  runs at 1× backing scale. iOS has no 1× devices, so iOS is checked at 2× and 3×. Frame-time
  evidence uses whichever device 001's performance checks use. The formal baseline devices are still
  being acquired (SKY-31, SKY-32).

## Dependencies

- **001-metal-app-shell**: the layer structure, frame loop, renderer, instrumentation and
  verification command this feature builds on. It is merged to `main`.
- **SKY-3 and SKY-4**: the method for measuring per-frame allocations, reused by SC-003. The check
  can be run before those tickets are closed, but its method must match theirs.
- **SKY-29**: the first consumer. It depends on this feature (it is blocked by SKY-28) and must not
  be started until this feature's text path exists.
