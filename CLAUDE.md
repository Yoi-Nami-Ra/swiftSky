# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a **GitHub Spec Kit** project (v0.14.1) initialized with the Claude integration and
Spec-Driven Development (SDD) workflow. The project is named `swiftSky`: a **cross-platform game for
iOS and macOS built in Swift with a Metal rendering pipeline** (SwiftUI shell). It is a git
repository (`main`), with no remote configured yet.

Built so far: `specs/001-metal-app-shell` (a black Metal surface on both platforms, three layers,
an off-main frame loop, instrumentation), `specs/002-metal-text-rendering` (Metal-drawn text from
a glyph atlas) and `specs/003-debug-overlay` (live frame statistics drawn on screen in Debug and
Profiling builds) and `specs/004-ship-newtonian-motion` (one ship with frictionless Newtonian motion in
the logic layer, driven by a per-tick control input; not drawn yet). Layer libraries and tests live in the root `Package.swift`, and the two app targets
live in `swiftSky.xcodeproj`. `./Scripts/verify.sh` is the single checked-in verification command.

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
  input and the per-tick rule. `ShipMotion.swift` is the logic layer's only file with an import
  (`Darwin`, for `cos`/`sin`). Angles are radians in code; tests compare states bit for bit with
  `Tests/SwiftSkySimulationTests/StateBits.swift`.
- `Tests/SwiftSkySimulationTests/`, `Tests/SwiftSkyRenderingTests/`, `Tests/SwiftSkyPlatformTests/`
  — headless Swift Testing suites. The platform tests cover pure measurement structs only.
  They must never create a Metal device; `verify.sh` enforces this.
- Debug launch arguments (Debug/Profiling builds only): the live debug overlay is shown by default,
  and `--no-debug-overlay` hides it, leaving the uniformly black surface that 001's and 002's
  visible-output checks expect. `--debug-text` draws the test string with live FPS, and
  `--debug-text-fill` fills the 1,024-character text capacity. Either one replaces the overlay.
- `.claude/skills/speckit-*/` — the skill definitions backing each `/speckit.*` command.
