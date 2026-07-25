# Feature Specification: Metal App Shell

**Feature Branch**: `001-metal-app-shell`

**Created**: 2026-07-26

**Status**: Draft

**Input**: User description: "Build XCode project — Everything visible by the user is done in Metal (2D); IF swiftUI or UIKit is not needed, drop them both, IF one of them is needed use swiftUI; clean architecture; the app when launched should show just black screen (window on mac)"

## Overview

This is the foundational slice of swiftSky. It establishes the buildable project, the layer
boundaries every later feature will live inside, and a real rendering path that presents frames to
the screen. The only thing the player sees is a black surface — but that black surface is produced
by the rendering pipeline drawing and presenting a frame, not by a static coloured background.
Proving the pipeline end-to-end while the visible result is trivial is the point: everything after
this feature adds content to a surface that already works.

Nothing gameplay-related is in scope. No sprites, no input handling, no simulation behaviour, no
menus, no settings, no audio.

## Clarifications

### Session 2026-07-26

- Q: Minimum platform versions, and which device is the performance-gate baseline? → A: Current major versions — iOS 26 / macOS 26; baseline is the oldest device each supports
- Q: Does the app render continuously at display refresh, or only when the surface needs redrawing? → A: Continuous, display-paced while visible; fully stopped when not visible
- Q: How does a renderer-initialisation failure reach the user, given FR-007 forbids visible platform-UI content? → A: Minimal platform-UI alert/text stating the reason, then terminate — a documented narrow exception to FR-007
- Q: Which iOS orientations does the app support? → A: Landscape only, both left and right
- Q: How is the idle memory budget expressed? → A: Measure and record the baseline, plus a loose absolute ceiling as a bloat tripwire
- Q: Fixed or variable simulation timestep? → A: Fixed timestep with an accumulator, decoupled from render rate; render-side interpolation deferred
- Q: Is CI in scope for this feature? → A: No pipeline — a checked-in verification script that CI can call verbatim later; constitution's CI clause recorded as deferred (no remote configured)
- Q: How is layer-boundary enforcement verified, given a violating build cannot be committed? → A: One-time manual proof per direction, evidence recorded in the quickstart; no permanent harness
- Q: How are the frame-time and allocation gates measured? → A: Debug/profiling-build-only instrumentation, emitted to the log; absent from release builds and never rendered
- Q: What are the macOS window's initial and minimum sizes? → A: 1280×720 default, 640×360 minimum, aspect ratio left free
- Q: How many windows/scenes can exist? → A: Exactly one; the platform's multi-window default must be explicitly disabled
- Q: Thread and concurrency model for the frame loop? → A: Dedicated isolation domain off the main thread; platform events marshalled in, main thread never blocks on a frame
- Q: What happens when the single macOS window is closed? → A: The app quits; window lifetime equals app lifetime
- Q: What is the fixed simulation tick rate? → A: 60 Hz, with the catch-up clamp set at 4 ticks per frame
- Q: How does the Mac get its build? → A: Native macOS target only; the iOS target's Mac Catalyst and "Designed for iPad" destinations explicitly disabled
- Q: Does the black screen go through a real draw call, or just a clear pass? → A: A full-screen black quad drawn through compiled shaders and a real pipeline state, not a clear-only pass
- Q: Colour space and pixel format of the surface? → A: Standard sRGB, opaque, 8 bits per channel; black is (0,0,0) at full alpha. No wide gamut, no HDR
- Q: Is the logic→render hand-off actually exercised, given a black quad needs no state? → A: Yes — it carries logic-owned state that does not drive appearance (the accumulated tick count), read every frame
- Q: What happens when a drawable cannot be acquired for a frame? → A: Skip the frame and continue; accumulated time is retained so no simulation time is lost. Never fatal, never user-visible
- Q: Is the simulation an actor, or plain values owned by the loop? → A: Plain value types advanced by a pure function; the loop provides isolation, the logic layer has no concurrency model

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Player launches the app on macOS and sees a black window (Priority: P1)

A person double-clicks the swiftSky app on a Mac. A normal, resizable application window opens. Its
entire content area is uniformly black. The window behaves like any other Mac window — it can be
moved, resized, minimised and zoomed, and the black content follows the window's size exactly with no
borders, letterboxing, stretching, or flicker. Closing it quits the app, since this is a single-window
game with no windowless state. Nothing else appears: no toolbar, no buttons, no labels, no placeholder
graphics.

**Why this priority**: This is the smallest deliverable that proves the whole chain works — project
builds, app launches, a window exists, the rendering pipeline initialises, and a frame is drawn and
presented. The user explicitly called out the Mac window as the launch outcome. Without this,
nothing else can be built or verified.

**Independent Test**: Build and run the macOS target, observe a black window, resize it and move it
between displays, and confirm the black content area tracks the window at every size with no visual
artefacts. Fully verifiable on its own and delivers the first runnable app.

**Acceptance Scenarios**:

1. **Given** the app is not running, **When** the user launches it on a Mac, **Then** a resizable
   1280×720 window appears whose entire content area is uniformly black.
2. **Given** the app window is open, **When** the user resizes it (including down to the 640×360
   minimum and up to full screen), **Then** the black content area fills the new size exactly, with no
   letterboxing, stretched edges, or transient non-black frames.
3. **Given** the app window is open, **When** the user drags a resize handle further inward than
   640×360, **Then** the window stops shrinking at that minimum.
4. **Given** the app window is open, **When** the user moves it to a second display with a different
   pixel density or refresh rate, **Then** the content area remains uniformly black and correctly
   sized for that display.
5. **Given** the app is launching, **When** the window first becomes visible, **Then** the user never
   sees a non-black frame (no white or grey flash before the first drawn frame).
6. **Given** the app window is open, **When** the user minimises it or fully covers it with another
   window, **Then** the app stops producing frames, and resumes producing them when the window is
   visible again.
7. **Given** the app window is open, **When** the user closes it, **Then** the app quits cleanly — no
   windowless process is left running, and no crash or hang occurs even if the close lands mid-draw.

---

### User Story 2 - Player launches the app on iOS and sees a black screen (Priority: P2)

A person taps the swiftSky icon on an iPhone or iPad. The app fills the screen with a uniformly
black surface, edge to edge, and stays that way. The app is landscape-only: rotating between the two
landscape orientations keeps the surface filling the screen, and turning the device upright does not
flip it into portrait. Sending the app to the background and returning to it leaves the screen black
with no artefacts.

**Why this priority**: iOS is a required target platform, and it exercises the same shared code
through a different platform entry point — which is what validates that the shared/platform split
actually holds. It follows macOS because the user named the Mac window as the primary launch
outcome, and because a desktop window makes resize and multi-display behaviour easier to verify
first.

**Independent Test**: Build and run the iOS target on a device and a simulator, observe a
full-screen black surface, rotate the device, and background/foreground the app — confirming the
surface stays correct throughout.

**Acceptance Scenarios**:

1. **Given** the app is not running, **When** the user taps its icon, **Then** the screen fills edge
   to edge with a uniformly black surface, including under the safe-area insets.
2. **Given** the app is open in landscape, **When** the user rotates the device to the opposite
   landscape orientation, **Then** the black surface resizes to fill it with no stretching or
   letterboxing.
3. **Given** the app is open, **When** the user rotates the device to portrait, **Then** the app
   stays in landscape and does not rotate.
4. **Given** the app is open, **When** the user sends it to the background, **Then** the app stops
   producing frames; **When** the user returns to it, **Then** frames resume and the screen is black
   with no stale or corrupted content.
5. **Given** the same shared code drives both platforms, **When** the iOS and macOS builds run side
   by side, **Then** the visible result is identical (a uniformly black surface) with no
   platform-specific visual difference.

---

### User Story 3 - Developer adds and tests logic without a GPU or a running app (Priority: P3)

An engineer writes a piece of game logic, and can build and unit-test it on its own — with no
graphics device, no window, and no app running — in a fast headless test run. Attempting to
reference rendering or platform-UI types from that logic fails to build, so the boundary is enforced
by the compiler rather than by convention.

**Why this priority**: This is what makes the architecture real instead of aspirational, and it is
the prerequisite for every future feature being testable. It is P3 because the two visible slices
above must exist first to prove the pipeline; this slice makes the codebase sustainable.

**Independent Test**: Add a trivial piece of logic in the logic layer, write a unit test for it, and
run the full test suite headlessly (no GPU, no simulator UI). Then, once per forbidden direction, add
a violating reference, confirm the build fails, revert it, and record the evidence in the quickstart
(per SC-009).

**Acceptance Scenarios**:

1. **Given** a piece of logic in the logic layer, **When** the test suite runs headlessly with no
   graphics device available, **Then** all tests execute and pass deterministically.
2. **Given** the logic layer, **When** code in it references a rendering-layer or platform-UI type,
   **Then** the build fails.
3. **Given** the rendering layer, **When** code in it references a platform-UI or app-lifecycle
   type, **Then** the build fails.
4. **Given** a fresh clone of the repository, **When** an engineer opens the project and runs the
   test suite, **Then** it succeeds with no manual setup, code generation, or dependency
   installation step.

---

### Edge Cases

- **No usable graphics device**: On hardware or in an environment where no graphics device can be
  obtained, the app must present the FR-024 failure notice naming the cause and then terminate,
  rather than crashing, hanging, or presenting an empty window indefinitely. On the supported OS
  floor (FR-022) every device has a graphics device, so this path is expected to be unreachable in
  production — it exists so that the reachable variants surface the same way. Those variants are real
  now that FR-002a requires a shader-backed draw call: shader compilation failure and pipeline-state
  creation failure are both genuine initialisation failure modes, not hypothetical ones.
- **Rendering surface has zero area**: When the window or view is resized to zero width or height
  (mid-resize, collapsed, or during window teardown), the app must skip drawing rather than attempt
  to draw into a zero-sized surface.
- **iPad multitasking sizes**: In Split View, Slide Over, or a resizable window, the surface can be
  handed a portrait-shaped or unusually narrow size even though the app is landscape-only. It must
  fill whatever size it is given rather than assuming a landscape aspect ratio.
- **Pixel density change mid-session**: When the surface's backing scale changes (moving between
  Retina and non-Retina displays, or a display resolution change), the drawable dimensions must
  update to match so the surface stays sharp and correctly sized.
- **Variable refresh rate displays**: On displays with adaptive or non-60 Hz refresh rates, frame
  pacing must follow the display's actual refresh rate rather than assuming a fixed rate.
- **Screen reader active**: With a screen reader enabled, the rendering surface must not be an
  unlabelled dead zone — it must expose an accessible description of what it is, so the app is
  navigable rather than silent.
- **Reduced motion enabled**: The surface presents no motion in this feature, so the setting has
  nothing to suppress; the app must nonetheless read as correct and not assert or warn.
- **Long stall before a frame**: After a debugger pause, a resume from background, or display sleep,
  the elapsed time handed to the accumulator can be seconds or minutes. The catch-up must clamp at 4
  ticks and discard the excess (FR-021b) rather than attempting every missed tick at once — so the
  simulation loses time rather than stalling the frame budget trying to reclaim it.
- **Drawable unavailable for a frame**: Under rapid resizing or memory pressure, no drawable may be
  available when the loop wants one. The frame is skipped and time is retained (FR-027a, FR-027b) — this
  is routine backpressure, and treating it as fatal would kill the app during ordinary window dragging.
- **Low Power Mode or thermal pressure**: The system may cap the display's refresh rate. Because pacing
  follows the display's actual rate (FR-020), the loop adapts with no special handling; the app MUST NOT
  add its own throttling on top (FR-021).
- **Platform event arriving mid-draw**: A resize, scale change, or visibility change can be delivered
  on the main thread while the loop is drawing. It must be queued and applied at the next frame
  boundary (FR-031), never mutate state a draw is reading, and never block the main thread.
- **App terminated while a frame is in flight**: Quitting or force-closing during a draw must stop and
  drain the loop before releasing graphics resources (FR-032), without a crash or a hang on exit.

## Requirements *(mandatory)*

### Functional Requirements

**Visible output**

- **FR-001**: Every pixel the user sees in the app's content area MUST be produced by the 2D
  rendering pipeline drawing and presenting a frame. No visible pixel may come from a platform-UI
  view, background colour, image asset, or launch placeholder.
- **FR-002**: The rendered result for this feature MUST be a uniformly black surface, with no other
  content of any kind.
- **FR-002a**: That surface MUST be produced by an actual draw call — a full-screen quad rendered
  through compiled vertex and fragment shaders using a created pipeline state and bound geometry. A
  pass that merely clears the surface to black MUST NOT be used, because it would leave the shader
  compilation, pipeline-state creation, geometry binding, and draw-submission path unexercised, which
  is precisely what this feature exists to prove.
- **FR-002b**: The quad's geometry and pipeline state MUST be created once at initialisation and reused
  every frame, never rebuilt per frame (FR-020).
- **FR-002c**: The rendering surface MUST use a standard sRGB, opaque, 8-bit-per-channel format. "Black"
  in FR-002 means (0, 0, 0) at full alpha in that space. Wide-gamut and extended-range/HDR surfaces are
  explicitly out of scope; no tone mapping or headroom management may be introduced.
- **FR-003**: The rendering surface MUST fill the entire available area — the whole window content
  area on macOS, and the whole screen edge to edge on iOS.
- **FR-004**: The user MUST never observe a non-black frame at any point during launch, resize,
  rotation, or resume.
- **FR-004a**: The platform's pre-first-frame launch appearance (iOS launch screen, macOS initial
  window background) MUST be configured black and empty. The OS presents it before any frame can be
  drawn, so it cannot be eliminated — it is a narrow, documented exception to FR-001, and configuring
  it black is what makes FR-004 achievable. It MUST carry no logo, text, or image; left at its default
  it would flash a light background on launch.

**Platform shell**

- **FR-005**: The app MUST run on both iOS and macOS from a single shared codebase, presenting the
  same visible result on both.
- **FR-006**: On macOS the app MUST present a standard, resizable, movable application window that
  honours normal window behaviours (minimise, zoom, full screen, close).
- **FR-006a**: The macOS window MUST open at 1280×720 points and MUST NOT be resizable below
  640×360 points. Its aspect ratio MUST NOT be locked — the surface must fill any legal size, since
  the user may resize freely and full screen imposes the display's own aspect.
- **FR-006b**: On iOS the app MUST support landscape-left and landscape-right only, and MUST NOT
  rotate into portrait. It MUST nonetheless tolerate arbitrary surface dimensions, since iPad
  multitasking can present sizes that match no device orientation.
- **FR-006c**: The app MUST support exactly one window/scene, and the platform's multi-window
  affordances MUST be explicitly disabled — no New Window command or Window menu entry on macOS, and
  no multi-window support declared on iPadOS. Exactly one Simulation State, one renderer, and one
  Render Surface exist at any time. Left at the platform default the app would accept a second window
  and behave undefinedly, so this must be turned off deliberately rather than assumed absent.
- **FR-006d**: On macOS, closing the window MUST terminate the app. Window lifetime equals app
  lifetime, so no windowless running state exists. Termination MUST follow the FR-032 teardown
  ordering — the loop stopped and drained before graphics resources are released — since closing the
  window can happen mid-draw.
- **FR-007**: The platform-UI layer MUST be limited to app lifecycle, window/scene creation, hosting
  the rendering surface, and the renderer-failure notice defined in FR-024. Apart from that notice it
  MUST NOT draw any user-visible content. No menus, controls, labels, or chrome beyond the
  platform-standard window frame and system menu bar are permitted in this feature.
- **FR-008**: The app MUST stop producing frames when its content is not visible (backgrounded,
  minimised, occluded, or its scene disconnected) and resume when it becomes visible again.
- **FR-009**: The rendering surface MUST expose an accessible description to assistive technology so
  that it is identifiable rather than an unlabelled region.

**Architecture**

- **FR-010**: The codebase MUST be organised into three separated layers — game/simulation logic,
  rendering, and platform/UI integration — with dependencies pointing inward only: platform/UI may
  depend on rendering and logic; rendering may depend on logic; logic MUST depend on neither.
- **FR-011**: The logic layer MUST be free of any rendering or platform-UI dependency, such that it
  builds and its tests run with no graphics device and no running app.
- **FR-012**: The rendering layer MUST receive the state it draws through an explicit, typed
  interface owned by the logic layer, rather than reading platform or UI state directly.
- **FR-012a**: That interface MUST actually carry state every frame in this feature, not merely exist
  as an unused type. Simulation State MUST hold at least the accumulated tick count, and the renderer
  MUST read it on every frame — so the hand-off and its cross-domain transfer (FR-030) are proven
  rather than declared.
- **FR-012b**: The state carried across that interface MUST NOT include presentation concepts. In
  particular the quad's colour MUST NOT come from Simulation State — it belongs to the rendering layer.
  The tick count MUST NOT affect visible output; the surface stays uniformly black (FR-002).
- **FR-012c**: Simulation State and Time Accumulator MUST be value types, and advancing the simulation
  MUST be a pure function of current state and a whole number of ticks. The logic layer MUST NOT contain
  actors, global actors, locks, or any other concurrency construct — isolation is the frame loop's
  responsibility (FR-028), not a property of the types the logic layer owns.
- **FR-012d**: Consequently the logic layer's tests MUST be able to advance the simulation synchronously,
  with no asynchrony and no isolation context, which is what makes FR-011 and SC-013 achievable. Transfer
  safety across the FR-030 boundary MUST come from value semantics rather than from added annotations.
- **FR-013**: Layer separation MUST be enforced at build time by the module/target structure, so
  that a cross-layer dependency violation fails the build rather than passing review.
- **FR-014**: Platform-specific code (per-platform entry points, windowing, and later input) MUST be
  isolated behind the thinnest possible boundary, with shared code carrying the behaviour.
- **FR-015**: There MUST be no global mutable state outside the logic layer's owned state.

**Project and build**

- **FR-016**: The repository MUST contain a project that opens and builds for both iOS and macOS
  destinations with no manual setup, code generation, or dependency installation step after clone.
- **FR-016a**: The Mac MUST be served by a native macOS target only. The iOS target's Mac destinations
  — Mac Catalyst and "Designed for iPad" — MUST be explicitly disabled, so exactly two destinations
  exist. Leaving them enabled would produce a second Mac variant with iPad window and orientation
  behaviour, contradicting FR-006a and FR-006d.
- **FR-017**: The project MUST include a test target for the logic layer that runs headlessly and
  deterministically, with no graphics device and no UI.
- **FR-018**: The project MUST use no third-party dependencies.
- **FR-019**: Build artefacts, per-user editor state, and machine-local settings MUST be excluded
  from version control.
- **FR-019a**: The repository MUST contain a single checked-in verification script that builds both
  platform destinations and runs the headless test suite, usable on a clean clone with no arguments.
  It MUST exit non-zero if any build or test fails, so it can be adopted as a CI job body verbatim
  once a remote exists. No CI pipeline configuration is in scope for this feature.

**Frame loop**

- **FR-020**: The app MUST pace frames to the display's actual refresh rate, and MUST NOT allocate
  heap memory per frame in the draw path.
- **FR-021**: The app MUST render continuously while its surface is visible — drawing one frame per
  display refresh whether or not anything changed — and MUST stop the loop entirely when the surface
  is not visible (per FR-008). No idle throttling or change-detection short-circuit may be introduced
  in this feature.
- **FR-021a**: The simulation MUST advance on a fixed timestep, decoupled from the render rate. Each
  frame, elapsed real time accumulates and the simulation advances zero or more whole ticks of that
  fixed size, with the remainder carried to the next frame. The tick rate MUST be 60 Hz — a named
  constant, independent of any display's refresh rate.
- **FR-021b**: Accumulated time MUST be clamped to at most 4 catch-up ticks per frame, discarding any
  excess, so a long stall (breakpoint, resume from background, display sleep) cannot trigger an
  unbounded catch-up loop that starves the frame budget. Both the tick rate and the clamp MUST be named
  constants in one place, not scattered literals.
- **FR-021c**: Render-side interpolation between simulation states MUST NOT be implemented in this
  feature. With no content to interpolate it would be untestable speculation (Principle V); the fixed
  timestep exists now so later logic is written against a stable contract.

**Performance instrumentation**

- **FR-021d**: The app MUST include instrumentation that reports per-frame timing and draw-path
  allocation counts, sufficient to evidence SC-003 and SC-004 and to serve as the standing mechanism
  for Principle III's before/after measurements in later features.
- **FR-021e**: That instrumentation MUST be compiled into debug and profiling builds only, MUST be
  provably absent from release builds, and MUST emit to the log — never to the rendered surface or any
  platform-UI view (FR-001, FR-007 remain absolute).
- **FR-021f**: The instrumentation itself MUST NOT allocate on the per-frame path, so that measuring
  the frame budget does not perturb it.

**Platform support**

- **FR-022**: The app MUST support minimum platform versions of iOS 26 and macOS 26. Older OS
  versions are explicitly out of scope, and no compatibility paths or availability fallbacks for
  them may be added.
- **FR-023**: The performance-gate baseline referenced by SC-001, SC-003, and SC-005 MUST be the
  oldest iPhone supported by iOS 26 and the oldest Mac supported by macOS 26. The specific models
  MUST be named in the plan so the gate is reproducible.

**Renderer failure**

- **FR-024**: When the rendering pipeline cannot be initialised, the app MUST present a minimal
  platform-UI notice stating the reason in human-readable terms, and MUST terminate once the user
  dismisses it. This notice is the only user-visible content the platform-UI layer may draw
  (exception to FR-007). It MUST be text-only — no graphics, no branding, no recovery controls beyond
  dismissal.
- **FR-025**: The failure notice MUST be readable by assistive technology and MUST respect Dynamic
  Type, so the one path where the user needs to read something is not the one path that is
  inaccessible.
- **FR-026**: The app MUST also emit a diagnostic identifying the failure cause, so the reason is
  recoverable from logs after the notice is dismissed. Debug builds MUST additionally trap at the
  point of failure.
- **FR-027**: The app MUST NOT fall back to a non-pipeline black surface when rendering is
  unavailable. A total rendering failure MUST NOT be able to masquerade as a correct black screen.
- **FR-027a**: Failure to acquire a drawable for a given frame MUST be treated as transient
  backpressure, not as an error: the app MUST skip that frame — no draw, no present — and continue to
  the next display callback. It MUST NOT terminate, MUST NOT show the FR-024 notice, and MUST NOT
  block or retry within the frame waiting for a drawable.
- **FR-027b**: Unconsumed time MUST be retained in the accumulator across a skipped frame, so an isolated
  skipped frame costs a presented image but no simulation time. Sustained skipping remains subject to the
  FR-021b clamp — once accumulated time exceeds 4 ticks the excess is discarded, exactly as for any other
  stall — so time is preserved across brief skips, not across arbitrarily long ones. Skipped frames MUST
  be counted by the debug instrumentation (FR-021d) so a high skip rate is diagnosable, and MUST NOT be
  surfaced to the user.
- **FR-027c**: The spec distinguishes two failure modes, and they MUST NOT be conflated in measurement: a
  **skipped frame** is one the app declined to draw because no drawable was available (FR-027a), and a
  **dropped frame** is one that missed its display deadline because the work overran the frame budget.
  The instrumentation (FR-021d) MUST report them separately.

**Concurrency**

- **FR-028**: The frame loop — elapsed-time measurement, simulation advance, and draw — MUST run in a
  dedicated isolation domain off the main thread. Its scheduling priority MUST be high enough to meet the
  frame budget under contention; the specific quality-of-service class MUST be named in the plan so the
  choice is reviewable rather than left to "appropriate". The main thread MUST be responsible only for
  window/scene lifecycle and platform event delivery.
- **FR-029**: Platform events that the loop must react to (surface resize, backing-scale change,
  visibility change, orientation change, impending termination) originate on the main thread and MUST
  be handed to the loop's isolation domain through an explicit, non-blocking mechanism. The main
  thread MUST NOT block waiting for a frame to complete, so UI responsiveness cannot be coupled to the
  frame budget.
- **FR-030**: Every type that crosses between the main thread and the loop's isolation domain MUST be
  safe to transfer, and that safety MUST be enforced by the compiler under strict concurrency checking
  rather than by review or convention.
- **FR-031**: A surface resize or backing-scale change MUST be applied at a frame boundary, never
  mid-draw. An event arriving while a frame is being drawn takes effect on the following frame.
- **FR-032**: On termination or scene disconnect, the loop MUST be stopped and drained — no frame in
  flight — before any graphics resource is released. Teardown ordering MUST be explicit, not left to
  deallocation order.
- **FR-033**: Simulation determinism (SC-013) MUST hold regardless of thread scheduling. The loop MUST
  read the clock exactly once per frame to feed the accumulator, and the simulation MUST NOT consult
  wall-clock time, thread identity, or scheduling order anywhere else.

### Key Entities

These are the conceptual boundary objects the layer split depends on. They carry no persisted data
in this feature. All four are value types — Simulation State and Time Accumulator by FR-012c, and Frame
Tick and Render Surface because they are plain descriptions of a duration and a drawable region with no
identity or behaviour of their own. Simulation State, Frame Tick, and Time Accumulator
are *held* by the frame loop and therefore only ever touched inside its isolation domain (FR-028) — the
isolation belongs to the loop, not to these types, which carry no concurrency constructs of their own.
Render Surface is the one that crosses from the main thread, so it is subject to FR-030's transfer-safety
requirement and FR-031's frame-boundary rule.

- **Simulation State**: The logic layer's snapshot of what should currently be shown, and the single
  typed hand-off the renderer consumes. In this feature it holds only the accumulated tick count —
  enough to make the hand-off real (FR-012a) without carrying any presentation concept (FR-012b).
  Owned exclusively by the logic layer.
- **Frame Tick**: One advance of the simulation by the fixed timestep. Its size is a constant, not a
  measured elapsed time, so a given sequence of ticks always produces the same result. Testable
  without any clock tied to a display.
- **Time Accumulator**: The unconsumed real time carried between frames, which decides how many ticks
  a frame advances. Defined by the logic layer, clamped per FR-021b, and testable synchronously by
  feeding it synthetic elapsed-time values.
- **Render Surface**: The drawable region the renderer presents into, described by its pixel
  dimensions and backing scale. Supplied by the platform layer; the renderer knows only its
  dimensions, not what kind of window or view it belongs to.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: On both platforms, the app reaches a fully black visible surface within 1 second of
  launch on the baseline device, and no observer sees a non-black frame at any point.
- **SC-002**: Whenever the app is running normally, 100% of visible pixels in its content area
  originate from the rendering pipeline; a code audit finds zero user-visible content drawn by
  platform-UI views other than the FR-024 failure notice.
- **SC-003**: The app holds its frame budget (60 fps → 16.6 ms per frame, or the display's native
  rate) over a 60-second idle session on the baseline device of each platform, with zero dropped frames
  and zero skipped frames as those terms are defined in FR-027c. An idle session involves no resizing or
  memory pressure, so neither count should be non-zero; a non-zero skip count here indicates a real
  problem rather than routine backpressure.
- **SC-004**: Zero heap allocations occur in the per-frame draw path, evidenced by the built-in
  instrumentation over a sustained run.
- **SC-004a**: A release build contains none of the instrumentation from FR-021d, confirmed by
  inspecting the built product rather than by reading the source.
- **SC-005**: Idle memory footprint is measured on the baseline device of each platform and recorded
  as the documented baseline that all later features are measured against. Additionally, a loose
  absolute ceiling — named in the plan, set well above what a bare shell should need, and intended as
  a bloat tripwire rather than a tuning target — is not exceeded on either platform.
- **SC-006**: Rotating an iOS device repeatedly between both supported landscape orientations, and
  driving the macOS window through its full size range including full screen, produces zero visual
  artefacts and zero crashes. (Concurrency behaviour under sustained resizing is covered separately by
  SC-016.)
- **SC-007**: The headless test suite runs to completion in under 10 seconds on a developer machine
  with no graphics device available, and passes deterministically across 10 consecutive runs.
- **SC-008**: An engineer with a fresh clone can open the project and run the app on both platforms
  in under 10 minutes, performing no setup steps beyond opening the project and pressing run.
- **SC-008a**: On a fresh clone, the verification script runs to completion with no arguments,
  builds both destinations, runs the headless suite, and returns zero — and returns non-zero when a
  test is deliberately broken.
- **SC-009**: Each of the three forbidden dependency directions (logic→rendering, logic→platform,
  rendering→platform) is proven once to be rejected by the build, and the evidence is recorded in the
  feature's quickstart. This is a one-time verification, not a standing automated gate: the module
  topology is the enforcement mechanism, and the proof confirms the topology is correct.
- **SC-010**: The app has zero third-party dependencies.
- **SC-011**: With a screen reader enabled, the rendering surface is reported with a meaningful
  description rather than being skipped or announced as unlabelled.
- **SC-012**: With renderer initialisation forced to fail, the app shows the failure notice naming the
  cause, exits on dismissal, and leaves a matching diagnostic in the log — verified on both platforms,
  and with a screen reader active.
- **SC-013**: Advancing the simulation through an identical sequence of ticks produces byte-identical
  resulting state across 10 consecutive headless runs, and the same sequence fed as one long elapsed
  span versus many short ones yields the same tick count (subject to the FR-021b clamp). Feeding a
  10-second elapsed span advances exactly 4 ticks, not 600.
- **SC-014**: No second window can be opened by any means — the New Window command and Window menu
  are absent on macOS, and the app offers no multi-window option on iPadOS.
- **SC-015**: The project builds clean under strict concurrency checking with zero warnings, and a
  sustained run under thread and address sanitisers reports zero data races and zero memory errors on
  both platforms.
- **SC-016**: Resizing the macOS window continuously for 10 seconds under thread sanitiser produces zero
  data races and no main-thread stall exceeding one frame interval — confirming that FR-029's non-blocking
  marshalling and FR-031's frame-boundary application actually hold under load.
- **SC-017**: Launching and quitting the app 20 consecutive times, including quits issued mid-draw,
  produces zero crashes and zero hangs on exit.
- **SC-018**: The project exposes exactly two run destinations — one iOS, one macOS. No Mac Catalyst or
  "Designed for iPad" destination is offered or buildable.
- **SC-019**: A frame capture confirms each presented frame contains a shader-backed draw call covering
  the full surface — not a clear-only pass — on both platforms.
- **SC-020**: The renderer observes a monotonically increasing tick count across frames, confirming the
  logic→render hand-off carries live state every frame, while the surface remains uniformly black.
- **SC-021**: With drawable acquisition forced to fail intermittently, the app continues running, each
  skip is counted separately from dropped frames by the debug instrumentation, and nothing is shown to
  the user. For skip runs short enough to stay within the FR-021b clamp, the simulation's tick count over
  the run matches elapsed time as if no frames had been skipped; for longer runs it falls behind by
  exactly the clamped excess, which is the documented behaviour rather than a defect.

## Assumptions

- **A platform UI framework is unavoidable, so SwiftUI is used.** The user asked to drop SwiftUI and
  UIKit if neither is needed. Neither platform can produce an application window or app lifecycle
  without one of them (or AppKit on macOS), so one is required — and per the user's instruction and
  the constitution, that one is SwiftUI. Its role is strictly limited to lifecycle, window/scene
  hosting, and the renderer-failure notice; in normal operation it draws nothing the user sees
  (FR-007, FR-024). UIKit and AppKit are not used as UI frameworks,
  though the minimal view-hosting bridge SwiftUI needs in order to embed a rendering surface
  necessarily touches the platform view type.
- **"Clean architecture" is interpreted as the constitution's three-layer split** with
  inward-pointing dependencies — logic at the centre with no outward knowledge, rendering consuming
  logic through an explicit interface, platform/UI at the outermost edge. No additional
  ports-and-adapters ceremony is introduced beyond what the layer boundary requires (Principle V).
- **Both platforms ship in this feature.** The constitution mandates iOS and macOS; the user named
  the Mac window explicitly. macOS is P1 and iOS is P2, but both are in scope here.
- **Rendering is 2D only.** No 3D pipeline, depth buffer, or camera concepts are introduced.
- **The project is checked into version control directly**, rather than generated by an external
  project-generation tool — this avoids a third-party dependency (FR-018, Principle V).
- **Test coverage in this feature is thin by nature.** There is almost no logic to test yet; the test
  target exists to prove headless testability (FR-017, FR-011). Rendering code is exempt from
  mandatory unit tests per Principle II, and is verified visually plus through the performance gate.
- **Memory and frame-budget numbers established here become the baseline** that later features are
  measured against under Principle III; this feature sets them rather than inheriting them. Default
  regression margin: a later feature may not raise idle footprint more than 10% above this baseline
  without a justification recorded in the plan's Complexity Tracking table.
- **The off-main-thread frame loop is a deliberate complexity choice and MUST be justified in the
  plan's Complexity Tracking table.** Running the loop on the main actor would have satisfied every
  requirement in this feature with materially less machinery — no marshalling boundary, no transfer
  safety, no drain-on-teardown ordering. The off-main model was chosen for headroom as the simulation
  grows. Principle V requires the rejected simpler alternative and the reason to be recorded, so the
  plan must carry that entry rather than presenting FR-028–FR-033 as the obvious default.
- **The constitution's CI requirement is deferred, with reason.** Principle II requires tests to run
  headlessly in CI. No git remote is configured for this repository yet, so there is nowhere for a
  pipeline to execute. This feature therefore delivers CI-*ready* tests plus the verification script
  CI will call (FR-019a), and the pipeline itself is deferred to whenever a remote is added. This is a
  recorded deviation, not an oversight.
- **No localisation.** The FR-024 failure notice — the only user-facing string in the feature — is
  English-only. Strings are not externalised into a catalogue yet. Adding localisation later affects one
  string, so deferring costs nothing.
- **No branding or icon assets.** No app icon, no launch imagery, no naming or visual identity work is
  in scope; the platform's default icon placeholder is accepted. FR-004a already requires the launch
  appearance to be black and empty, which is the only launch-time visual this feature specifies. Where
  the user stories say "taps the swiftSky icon", that refers to whatever placeholder the platform shows.
- **No persistence, networking, audio, input handling, or gameplay** is included. Input arrives in a
  later feature, which is why FR-010's data-flow direction is specified now but not exercised.

## Dependencies

- An Apple developer toolchain capable of building for both iOS and macOS destinations (present on
  the development machine: Xcode 27, Swift 6.4).
- A Mac for macOS verification, plus an iOS device or simulator for iOS verification.
- A graphics-capable device for visual and performance verification; the headless test suite requires
  none.
