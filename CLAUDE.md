# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **GitHub Spec Kit** project (v0.14.1) initialized with the Claude integration and
Spec-Driven Development (SDD) workflow. The project is named `swiftSky`: a **cross-platform game for
iOS and macOS built in Swift with a Metal rendering pipeline** (SwiftUI shell). It is a git
repository (`main`) with `origin` set to `git@github.com:Yoi-Nami-Ra/swiftSky.git`, a private
GitHub repository. On this Mac a plain `git@github.com:` connection signs in as a different account
and gets "Repository not found", so the repo's local `.git/config` rewrites it:
`git config url."git@yoinamira-github:".insteadOf "git@github.com:"`, where `yoinamira-github` is a
host alias in `~/.ssh/config` that signs in with the `Yoi-Nami-Ra` key. `git remote -v` therefore
prints the alias form; `git config --get remote.origin.url` shows the stored URL. A fresh clone needs
the rule set again.

Built so far: `specs/001-metal-app-shell` (a black Metal surface on both platforms, three layers,
an off-main frame loop, instrumentation), `specs/002-metal-text-rendering` (Metal-drawn text from
a glyph atlas), `specs/003-debug-overlay` (live frame statistics drawn on screen in Debug and
instrumented Release builds), `specs/004-ship-newtonian-motion` (one ship with frictionless Newtonian motion
in the logic layer, driven by a per-tick control input; not drawn yet) and
`specs/005-game-space-camera` (one world unit = one point, an unbounded world, and a fixed camera
with the origin at the centre of the whole surface; nothing wired in yet) and
`specs/006-ship-autopilot` (a move order and the autopilot that flies it — turn, burn, flip, brake,
then keep station — in the logic layer; nothing issues orders yet) and
`specs/007-ship-sprite-rendering` (the ship drawn from `ship.png` at its position and heading, over the
black background and under the debug overlay) and
`specs/008-tap-to-order-ios` (a tap on the iOS surface orders the ship to the point under the finger)
and `specs/009-click-to-order-macos` (a primary click does the same on macOS, through the same order
request) and `specs/010-ship-path-prediction` (giving an order also predicts its planned path in the
logic layer; nothing draws it yet) and `specs/011-draw-allocation-counter` (001 FR-021d's draw-path
allocation counts in the frame summary; check 25, zero allocations per frame, PASS on iOS and, by SKY-4, on macOS) and `specs/012-main-thread-stall-probe` (the main thread's worst busy
stretch in the frame summary; check 29's continuous resize: no races, no stall mid-drag) and
`specs/013-render-interpolation` (the ship drawn between its last two ticks, so it moves smoothly on
120 Hz displays) and `specs/014-order-overlay` (while an order is flown: a marker at the destination, a
ring around the ship and the remaining planned path, in every build) and
`specs/015-debug-overlay-ship-order` (the debug overlay's ship and order lines under its frame
statistics) and `specs/016-frame-budget-learner` (the frame budget learned only from adjacent agreeing
gaps, never below the display's fastest interval) and `specs/018-ci-verify-workflow` (CI: `verify.sh`
run on every push to `main` and every pull request, on a self-hosted runner on this Mac) and
`specs/019-instrumented-build-script` (the Profiling configuration removed; `Scripts/build-instrumented.sh`
makes the optimised build with the instrumentation, and `verify.sh` checks it has it and Release has not) and
`specs/020-autopilot-rest-phase` (a ship at rest is never "against its motion" when the phase is named, so a
re-order after arrival starts `aligning` or `burning`, not `flipping` or `braking`) and
`specs/021-ios-gpu-frame-capture` (001's checks 4 and 5 closed on iOS, and by SKY-19 on macOS, by an lldb
probe instead of a GPU capture; no code changes).
Layer libraries and tests live in the root `Package.swift`, and the two app targets live in
`swiftSky.xcodeproj`, which has two build configurations, Debug and Release.
`./Scripts/verify.sh` is the single checked-in verification command.

**The instrumented build** (019): `./Scripts/build-instrumented.sh [ios|macos|both]` builds Release with
`SWIFTSKY_INSTRUMENTATION` added for Swift and C on the `xcodebuild` command line, which reaches every
package target, into `.build/instrumented/`, and prints each app's path (the iOS one for the simulator).
It is optimised and carries the frame summaries, the allocation counter, the debug overlay and the debug
launch arguments: take every frame-time and allocation measurement with it. There is no Profiling build
any more: SwiftPM knows only debug and release, so an Xcode configuration of that name reached the app
module only and carried none of the instrumentation (011 R1). Plain Release carries none of it either;
`verify.sh` checks both (`dropped=` in the instrumented macOS executable, none of 001 check 27's strings in
Release). Both builds pass `CLANG_MODULES_PRUNE_AFTER=0`: otherwise Xcode prunes a warm folder's
explicit-module `.pcm` files after four days unread (an unchanged checkout never reads them), and every
later Release build gets dsymutil's `….pcm: No such file or directory` warnings (019 research R10).

The project constitution (`.specify/memory/constitution.md`, v1.1.0) is ratified and enforces
five principles: **Architecture Discipline** (logic / Metal rendering / platform-UI layers kept
separate, unidirectional data flow), **Test Coverage Discipline** (tests required for non-trivial
logic; test-first recommended but not mandated; visual/render code exempt; tests must be runnable by
a single checked-in command, wired into CI that gates merges), **Performance &
Resource Efficiency** (frame budget, no hot-path allocations, memory budgets), **Accessibility &
Platform UX** (Dynamic Type/VoiceOver/HIG, reduced-motion), and **Simplicity & YAGNI**.

Before writing any feature code, expect to go through the SDD cycle below. The first real work is
likely to fill in the constitution and create the first spec.

## The Spec-Driven Development workflow

Work flows through ordered phases, each invoked as a skill (slash command). Run them in order;
`specify → plan → tasks` each gate on human review before the next:

1. `/speckit.constitution` — establish/update project principles in `.specify/memory/constitution.md`
   (currently **v1.1.0**; amendments must bump the version and add a Sync Impact Report. Note that
   amendments also invalidate version references in `plan.md`'s Constitution Check, this file, and
   feature checklists — grep for the old version after any bump).
2. `/speckit.specify` — create a feature spec. This creates `specs/NNN-short-name/spec.md` and its branch.
3. `/speckit.clarify` — (optional) ask targeted questions to de-risk the spec before planning.
4. `/speckit.plan` — generate design artifacts (`plan.md`, and supporting docs) for the feature.
5. `/speckit.tasks` — generate `tasks.md`, a dependency-ordered actionable task list.
6. `/speckit.analyze` — (optional) cross-check spec.md ↔ plan.md ↔ tasks.md for consistency.
7. `/speckit.implement` — execute tasks.md.

Supporting commands: `/speckit.checklist` (custom quality checklist), `/speckit.converge` (assess
codebase vs. spec and append remaining work to tasks.md), `/speckit.taskstoissues` (export tasks to
GitHub issues). The bundled `speckit` workflow (`.specify/workflows/speckit/workflow.yml`) runs
specify → plan → tasks → implement end-to-end with review gates.

## Feature numbering (IMPORTANT)

When creating a new spec, feature directories/branches are numbered sequentially (`001-`, `002-`, …).
The user's global instruction requires: **always check remote branches first** to determine the
latest spec number so numbers don't collide across machines/branches —
`git fetch --prune && git branch -r | grep -E 'spec|[0-9]{3}-'` — do **not** rely only on the local
`specs/` directory. (`main` is pushed to `origin`; spec branches are merged and deleted locally, so
check the remote list too.)

## Scripts

Spec Kit shell scripts live in `.specify/scripts/bash/` (this project uses `sh` scripts, invoke
separator `-`). They are normally called by the skills, not by hand, but for reference:

- `create-new-feature.sh` — computes the next feature number, branch name, and scaffolds
  `specs/NNN-*/spec.md`. Flags: `--json`, `--dry-run`, `--short-name <name>`, `--number N`,
  `--timestamp`, `--allow-existing-branch`.
- `setup-plan.sh`, `setup-tasks.sh` — scaffold plan/tasks artifacts for the current feature.
- `check-prerequisites.sh` — validates that required prior artifacts exist before a phase runs.
- `common.sh` — shared helpers (repo-root resolution prioritizes `.specify/`, feature-state
  persistence to `.specify/feature.json`, template resolution).

Feature state is tracked via `.specify/feature.json` and the `SPECIFY_FEATURE` /
`SPECIFY_FEATURE_DIRECTORY` env vars, so downstream phases know which feature is active.

## Templates

Phase artifacts are generated from `.specify/templates/` (`spec-template.md`, `plan-template.md`,
`tasks-template.md`, `checklist-template.md`, `constitution-template.md`). When editing generated
artifacts, keep them consistent with these templates.

## Key locations

- `.specify/memory/constitution.md` — project constitution (fill this before serious feature work).
- `.specify/templates/` — source templates for all generated artifacts.
- `.specify/scripts/bash/` — workflow scripts.
- `.specify/workflows/` — workflow definitions and registry.
- `specs/NNN-*/` — per-feature spec/plan/tasks and quickstart validation evidence.
- `Sources/SwiftSky{Simulation,Rendering,Platform}/` — the three layers. Text rendering is in
  `Sources/SwiftSkyRendering/Text/`, and the test pattern and debug overlay (Debug and instrumented Release only)
  are in `Sources/SwiftSkyRendering/Debug/`. The overlay's measurement (one-second frame-time
  window, 4 Hz refresh) sits beside `Instrumentation.swift` in the platform layer.
- `Sources/SwiftSkySimulation/Ship.swift` and `ShipMotion.swift` — the ship, its limits, the control
  input and the per-tick rule. `ShipMotion.swift` imports
  `Darwin` for `cos`/`sin`. Angles are radians in code; tests compare states bit for bit with
  `Tests/SwiftSkySimulationTests/StateBits.swift`.
- `Sources/SwiftSkySimulation/Autopilot.swift` and `AutopilotLaw.swift` — the move order, phases,
  arrival tolerances and the autopilot value held in `SimulationState`, and the per-tick law.
  `Simulation.advance(_:ticks:)` is flown by the autopilot when there is an order;
  `advance(_:ticks:input:)` takes an explicit input and leaves the order alone. `AutopilotLaw.swift` is
  the logic layer's second file with a `Darwin` import. Its tuning history is research R11. When naming
  the phase, a speed of at most `settleSpeed` is rest (020, SKY-46); the hold rule's direction test does
  not use that rule, so autopilot-flown inputs are unchanged, but after explicit-input ticks a phase named
  from rest can change a later input through the hold rule.
- `Sources/SwiftSkySimulation/PlannedPath.swift` — the current order's planned path, held in
  `SimulationState.plannedPath` and written only by `setOrder(to:)`: up to 256 positions in an
  `InlineArray` (no heap, so the state is ~4.2 KB), the tick of every point (`startTick`, `spacing`,
  `endTick`), thinned by halving when full, capped at 3,600 ticks. The prediction flies copies of the ship
  and autopilot with `Simulation.tick`, the one tick `advance(_:ticks:)` also uses, and stops on the first
  state that reports arrived. Debug and instrumented Release builds add `predicted=… ticks=… points=… arrives=…` to
  the order log line; the arrival line, written once per frame, can come a tick or two later on
  multi-tick frames.
- `Sources/SwiftSkySimulation/ShipPose.swift` (013) — position and heading, and the blend between two
  poses (linear position, short-arc heading in (−π, π], bit-exact at fraction 0 and for equal inputs).
  `TimeAccumulator.tickFraction` is the blend factor; `Simulation.advance(…, previousPose:)` records the
  pose before a frame's last tick, which `FrameLoop` keeps. The loop passes the drawn pose to
  `Renderer.render(state:shipPose:…)`: anything drawn from the ship's pose (SKY-30, SKY-42) uses that
  argument, never `state.ship`, so it never drifts from the sprite. `--no-interpolation` draws the tick
  pose instead; like every debug argument it needs `SWIFTSKY_INSTRUMENTATION` in the package, so Debug
  or the instrumented Release build (`Scripts/build-instrumented.sh`).
- `Sources/SwiftSkyRendering/OrderOverlay.swift` and `OrderOverlayPipelines.swift` (014) — the order
  overlay. `OrderOverlay` is the tested placement (like `ShipSpritePlacement`): `nil` with no order, when
  `arrived`, or with no camera; otherwise up to 258 line points in pixels (drawn ship, the planned-path
  points after `poseTick`, the destination), the marker centre and the highlight centre (the sprite's
  whole-pixel centre). `poseTick` is a `render` argument from `FrameLoop`: `tickCount − 1` when
  interpolating, `tickCount` under `--no-interpolation`; `PlannedPath.tick(ofPoint:)` gives each point's
  tick. Two pipelines share one distance-field fragment shader and blend with `max`, which is right only
  over the black background. Sizes and colour are `OrderOverlayStyle` (no design yet). Drawn between the
  background and the ship.
- The debug overlay's ship and order lines (015), in `DebugOverlay.swift`: `pos`, `vel`, `speed`,
  `heading`, `turn`, then `order   none` or the phase with `dest` and `dist`. `DebugOverlayShip` is taken
  in `FrameLoop` step 3a, at the 4 Hz refresh, from `state` before that frame's advance — the latest tick,
  never the drawn pose. Numbers use `TextBuffer.writeSignedHundredths` (nine columns, no `-0.00`); heading
  and turn are in degrees, and a heading rounding to −180.00 is written `180.00`. The Release strings
  check looks for the labels and units, not the phase names: `AutopilotPhase`'s case names stay in
  reflection metadata in every build.
- `Sources/SwiftSkyRendering/Camera.swift` and `GameSpace.swift` — the camera (world → view points,
  view points → world, world → clip; `init?(surface:)` is `nil` for a zero-area surface or an
  unusable backing scale) and
  `GameSpace.shipLength` (40 units), with the sprite-orientation note for SKY-27. The rendering tests
  also depend on the logic layer, to name `Vector2`.
- `Sources/SwiftSkyRendering/ShipSpritePlacement.swift` (the pure corner maths: camera, whole-pixel
  centre, rotation by heading − π/2, 40 pt square), `ShipImageBitmap.swift` (CPU decode to premultiplied
  sRGB) and `ShipSprite.swift` (pipeline and mipmapped texture, built once). The image is
  `Sources/SwiftSkyRendering/Resources/ship.png`, a byte-identical copy of `design/sprites/ship.png`,
  which is the source of truth: `verify.sh` fails if they differ, so copy the design file over it.
  A missing or unusable image is `RendererError.shipImageUnavailable` (`ship_image_unavailable`).
- `Sources/SwiftSkyPlatform/MoveOrderRequest.swift` — "order the ship to the world point under this
  view position": pure and platform-neutral, posted as `SurfaceEvent.moveOrderRequested` through the frame
  loop's one event queue, and converted in the loop against the surface it has applied up to that event.
  The iOS tap recogniser (one tap, one finger) and the VoiceOver `.allowsDirectInteraction` trait are in
  `MetalSurfaceView.swift`. Debug and instrumented Release builds log `order view=… world=…` and `arrived world=…`
  lines under subsystem `com.swiftsky.app` (category `frame`). Read them with `/usr/bin/log`: in zsh a
  bare `log` is a shell builtin.
- `Sources/SwiftSkyPlatform/ClickPosition.swift` — the Mac click's bottom-left → top-left flip,
  (x, h − y) against the view's `bounds.height`; pure and tested. The macOS click recogniser is in
  `MetalSurfaceView.swift`: primary button only, Control-click ignored (a secondary click by convention),
  and `acceptsFirstMouse` returns `false`, so the first click on an inactive window only activates it.
- `Sources/SwiftSkyAllocationCounter/` — a C target, Debug and instrumented Release only (its body is under
  `SWIFTSKY_INSTRUMENTATION`): a libmalloc `malloc_logger` hook that counts the frame-loop thread's heap
  allocations inside each frame, and calls one the graphics framework's when a return address between the
  hook and the frame callback lies in Metal, QuartzCore, IOGPU, IOSurface, MTLSimDriver or an AGX image
  (otherwise the app's — it fails safe). `FrameLoop` installs it, self-tests it (`allocation counter
  ready`) and brackets steps 1–5 of every frame; `FrameAllocationCounts.swift` holds the four summary
  fields `allocs= allocframes= eventallocs= gfxallocs=`. To find an allocation, attach lldb to a running
  app with a breakpoint on `sky_alloc_app_allocation`. Writing a log line allocates (~23 per `Logger`
  call), so lines found inside the stretch are noted and written after `sky_alloc_frame_end`: the order
  lines (`OrderLogLine`) and the arrival line (011 check 10). Measure with the **instrumented Release build**,
  `./Scripts/build-instrumented.sh` (optimised, with the counter; 011 R12, 019) — Debug allocates on every
  unspecialised `for`-loop iterator. In
  the simulator `log show` returns nothing; use `xcrun simctl spawn <udid> log stream`. Inside a counted
  stretch in tests, loop with `while`, not `for _ in 0..<n`. The procedure is "The method" in
  `specs/011-draw-allocation-counter/quickstart.md`.
- `Sources/SwiftSkyPlatform/DisplayIntervalLearner.swift` (016) — the frame budget: a pure value the loop
  feeds one gap per frame (`observe(gap:)`), which reports a new budget for `Instrumentation.updateBudget`.
  A shorter interval needs the very next plausible gap to agree (5%), and is never below the floor
  `1 / maximumFramesPerSecond` of the surface's screen, which `MetalSurfaceView` posts as
  `SurfaceEvent.displayRateChanged` before a geometry event when it changes. A backing-scale change, or a
  floor above the learned interval, forgets it (back to 1/60 s). Gaps are not always whole display
  intervals: a live resize and a display move both produce sustained runs of shorter ones.
- `Sources/SwiftSkyPlatform/MainThreadStallProbe.swift` and `MainThreadStallFigures.swift` (012) — two
  run-loop observers on the main run loop, in the common modes so live resize and menus count, measure each
  busy stretch between two waits; one packed `Atomic<UInt64>` hands the worst (µs) and the count over the
  frame interval to the loop, which logs `mainworst=…ms mainover=…` at the end of every summary. The frame
  figures cannot show this: they are measured on the loop thread. macOS logs `live resize began` / `live
  resize ended` around a drag; the summaries after the first, up to the first after the second, cover it.
  `--debug-main-stall` spins the main thread for 50 ms once, 5 s after launch. The drag procedure (by
  hand: Accessibility is not granted) is `specs/012-main-thread-stall-probe/quickstart.md`. Launch apps
  with `open -n <app>` so the window comes to the front; a covered window pauses the loop.
- The frame loop sets the layer's `drawableSize` when it applies a resize (012 R14); only the first size
  is set on the main thread. While the display link is paused, the loop thread applies queued events on
  each 0.1 s run-loop turn, so a hidden-then-shown window resumes (012 R13). In the allocation counter,
  `previousLogger` is atomic (012 R12).
- The text renderer's instance ring has no completion handler: a handler passed from Swift is re-bridged
  into a heap block on every call. Each slot remembers its last command buffer and is reused once that
  buffer's `status` is `.completed` or `.error` (011 R13).
- `Tests/SwiftSkySimulationTests/`, `Tests/SwiftSkyRenderingTests/`, `Tests/SwiftSkyPlatformTests/`
  — headless Swift Testing suites. The platform tests cover pure structs (measurement and the move
  order request) and the allocation counter through its C API (a `.serialized` suite: the hook is
  process-wide), and depend on the counter, the rendering and the logic layers to name `RenderSurface`, `Vector2` and
  `SimulationState`. They must never create a Metal device; `verify.sh` enforces this.
- Debug launch arguments (Debug and instrumented Release builds only): the live debug overlay is shown by default,
  and `--no-debug-overlay` hides it. `--no-ship` stops the ship being drawn; together with
  `--no-debug-overlay` it leaves the uniformly black surface that 001's and 002's visible-output checks
  expect. `--debug-ship-spin` turns the ship counter-clockwise in place at its top rate. `--no-interpolation`
  draws the ship at its latest tick instead of between ticks (013). `--debug-main-stall`
  stalls the main thread once (012). `--debug-text` draws the test string with live FPS, and
  `--debug-text-fill` fills the 1,024-character text capacity. Either one replaces the overlay.
- `.github/workflows/verify.yml` and `.github/RUNNER.md` (018) — CI. On every push to `main` and every
  pull request against `main`, the `verify` job checks out the commit and runs `./Scripts/verify.sh`,
  nothing else, on a self-hosted runner on this Mac (labels `self-hosted`, `macOS`, `xcode-27`; 30-minute
  limit; a newer push cancels an older pull-request run, never a `main` one). It runs only while the Mac
  is on and the runner service is running; queued jobs wait. **Merge rule**: merge a pull request only
  when `verify / verify` passed for its current head (branch protection is not set up). Installing,
  starting or stopping the runner, pushing, and any GitHub setting are the developer's to do, by hand,
  following `RUNNER.md`. `actionlint .github/workflows/verify.yml` checks the workflow locally;
  `.github/actionlint.yaml` declares the `xcode-27` label. When Xcode changes, change the runner label
  and `runs-on` together.
- `specs/021-ios-gpu-frame-capture/probe.sh` (021) — builds the Debug iOS app, launches it in the first booted
  simulator with `--no-ship --no-debug-overlay`, attaches lldb and counts Metal calls over 10 s (presents,
  draws, pipeline bindings, `setViewport:`, pipeline-state and buffer creation), then samples the bound
  pipeline, vertex buffer and draw twice, 5 s apart, on the frame-loop thread. It exits 1, before the
  samples, when a count breaks 001 check 4 or 5, when a breakpoint resolves to no location, or when the app
  does not launch; the samples are read by hand against the spec's quickstart. iOS simulator only (arm64
  registers, the simulator's `MTLSerializerRenderCommandEncoder`); not part of `verify.sh` or CI. A covered
  simulator window stops the frames: during the counts that is a `no frame was presented` FAIL, during the
  samples the samples part waits. `specs/021-ios-gpu-frame-capture/probe-macos.sh` (SKY-19) is its
  macOS twin: scheme `swiftSky (macOS)`, launched with `open -n`, the same counts and pass/fail rules, and
  samples that match any encoder class (the GPU driver's, `AGXG13XFamilyRenderContext` on an M1 Pro); Apple
  silicon only, and a covered window stops its frames too. It finds, attaches to and stops only the app it
  built (by its executable's path), never another `swiftSky` process. It closed 001's checks 4 and 5 on
  macOS. The lldb runs and the checks both probes share are in `probe-common.sh`, which they source.
- `.claude/skills/speckit-*/` — the skill definitions backing each `/speckit.*` command, plus two
  project-authored variants that read the base skills at run time: `speckit-clarify-auto` (answers what the
  code, constitution and ticket settle, asks only the rest) and `speckit-implement-phased` (one `tasks.md`
  phase per subagent, committed after each). The ticket start flow in `.tickets/project.yaml` runs them.
