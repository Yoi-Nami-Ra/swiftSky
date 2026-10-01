# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **GitHub Spec Kit** project (v0.14.1) initialized with the Claude integration and
Spec-Driven Development (SDD) workflow. The project is named `swiftSky`: a **cross-platform game for
iOS and macOS built in Swift with a Metal rendering pipeline** (SwiftUI shell). It is a git
repository (`main`), with no remote configured yet.

Built so far: `specs/001-metal-app-shell` (a black Metal surface on both platforms, three layers,
an off-main frame loop, instrumentation), `specs/002-metal-text-rendering` (Metal-drawn text from
a glyph atlas), `specs/003-debug-overlay` (live frame statistics drawn on screen in Debug and
Profiling builds), `specs/004-ship-newtonian-motion` (one ship with frictionless Newtonian motion
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
logic layer; nothing draws it yet). Layer libraries and
tests live in the root `Package.swift`, and the two app targets live in `swiftSky.xcodeproj`.
`./Scripts/verify.sh` is the single checked-in verification command.

The project constitution (`.specify/memory/constitution.md`, v1.1.0) is ratified and enforces
five principles: **Architecture Discipline** (logic / Metal rendering / platform-UI layers kept
separate, unidirectional data flow), **Test Coverage Discipline** (tests required for non-trivial
logic; test-first recommended but not mandated; visual/render code exempt; tests must be runnable by
a single checked-in command, and wired into CI once a remote exists), **Performance &
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
`specs/` directory. (No remote is configured yet, so add one before relying on this check.)

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
  `Sources/SwiftSkyRendering/Text/`, and the Debug/Profiling-only test pattern and debug overlay
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
  the logic layer's second file with a `Darwin` import. Its tuning history is research R11.
- `Sources/SwiftSkySimulation/PlannedPath.swift` — the current order's planned path, held in
  `SimulationState.plannedPath` and written only by `setOrder(to:)`: up to 256 positions in an
  `InlineArray` (no heap, so the state is ~4.2 KB), the tick of every point (`startTick`, `spacing`,
  `endTick`), thinned by halving when full, capped at 3,600 ticks. The prediction flies copies of the ship
  and autopilot with `Simulation.tick`, the one tick `advance(_:ticks:)` also uses, and stops on the first
  state that reports arrived. Debug and Profiling builds add `predicted=… ticks=… points=… arrives=…` to
  the order log line; the arrival line, written once per frame, can come a tick or two later on
  multi-tick frames.
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
  `MetalSurfaceView.swift`. Debug and Profiling builds log `order view=… world=…` and `arrived world=…`
  lines under subsystem `com.swiftsky.app` (category `frame`). Read them with `/usr/bin/log`: in zsh a
  bare `log` is a shell builtin.
- `Sources/SwiftSkyPlatform/ClickPosition.swift` — the Mac click's bottom-left → top-left flip,
  (x, h − y) against the view's `bounds.height`; pure and tested. The macOS click recogniser is in
  `MetalSurfaceView.swift`: primary button only, Control-click ignored (a secondary click by convention),
  and `acceptsFirstMouse` returns `false`, so the first click on an inactive window only activates it.
- `Tests/SwiftSkySimulationTests/`, `Tests/SwiftSkyRenderingTests/`, `Tests/SwiftSkyPlatformTests/`
  — headless Swift Testing suites. The platform tests cover pure structs only (measurement and the move
  order request), and depend on the rendering and logic layers to name `RenderSurface`, `Vector2` and
  `SimulationState`. They must never create a Metal device; `verify.sh` enforces this.
- Debug launch arguments (Debug/Profiling builds only): the live debug overlay is shown by default,
  and `--no-debug-overlay` hides it. `--no-ship` stops the ship being drawn; together with
  `--no-debug-overlay` it leaves the uniformly black surface that 001's and 002's visible-output checks
  expect. `--debug-ship-spin` turns the ship counter-clockwise in place at its top rate. `--debug-text` draws the test string with live FPS, and
  `--debug-text-fill` fills the 1,024-character text capacity. Either one replaces the overlay.
- `.claude/skills/speckit-*/` — the skill definitions backing each `/speckit.*` command.
