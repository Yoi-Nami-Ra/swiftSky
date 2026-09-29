<!--
Sync Impact Report (v1.1.0 — 2026-07-26)
- Version change: 1.0.0 → 1.1.0 (MINOR — materially expanded guidance)
- Amended: Principle II. The CI clause assumed a remote exists, which this repository does not yet
  have. Determinism and headlessness remain unconditional; a new requirement for a single checked-in
  test command is added; CI becomes mandatory the moment a remote exists, and its absence must be
  recorded in Complexity Tracking until then. Net effect is stricter, not looser: the original
  imposed no obligation at all when CI was unavailable.
- Templates requiring updates: none — plan-template.md's Constitution Check gate is generic and
  inherits the amended wording.
- Follow-up TODOs: wire the checked-in command into CI when a remote is added.

Sync Impact Report (v1.0.0 — 2026-07-24)
- Version change: TEMPLATE (unversioned) → 1.0.0
- Ratification: Initial adoption of the swiftSky constitution
- Modified principles:
    [PRINCIPLE_1_NAME] → I. Architecture Discipline
    [PRINCIPLE_2_NAME] → II. Test Coverage Discipline
    [PRINCIPLE_3_NAME] → III. Performance & Resource Efficiency
    [PRINCIPLE_4_NAME] → IV. Accessibility & Platform UX
    [PRINCIPLE_5_NAME] → V. Simplicity & YAGNI
- Added sections:
    Technology & Platform Standards (replaces [SECTION_2_NAME])
    Development Workflow & Quality Gates (replaces [SECTION_3_NAME])
- Removed sections: none
- Templates requiring updates:
    ✅ .specify/templates/plan-template.md — Constitution Check gate is generic and
       inherits these principles; no change required.
    ✅ .specify/templates/spec-template.md — no principle-specific slots; compatible.
    ✅ .specify/templates/tasks-template.md — defers test inclusion to spec/plan, which
       this constitution now drives; compatible.
    ✅ .claude/skills/speckit-*/ — commands use generic guidance; no agent-specific
       references needed updating.
- Follow-up TODOs: none
-->

# swiftSky Constitution

swiftSky is a cross-platform game for iOS and macOS built in Swift with a Metal rendering
pipeline. This constitution defines the non-negotiable engineering principles that govern how
features are specified, planned, implemented, and reviewed.

## Core Principles

### I. Architecture Discipline

The codebase MUST maintain clear separation between three layers: game/simulation logic,
rendering (Metal), and platform/UI integration (SwiftUI and platform entry points).

- Game logic MUST NOT depend on Metal types or SwiftUI types; it MUST be exercisable in tests
  without a GPU or a running app.
- Rendering code MUST consume simulation state through explicit, well-typed interfaces rather
  than reaching into UI or platform state directly.
- Shared, platform-agnostic code MUST live in a common target; platform-specific code
  (iOS vs. macOS entry points, input handling, windowing) MUST be isolated behind protocols
  or `#if os(...)` boundaries kept as thin as possible.
- Data flow MUST be unidirectional: input → simulation update → render. Global mutable state
  outside the simulation is prohibited.

**Rationale**: A Metal game mixes real-time rendering, input, and simulation. Without enforced
layer boundaries the render loop and game logic become entangled, making the game untestable,
platform-locked, and unsafe to change.

### II. Test Coverage Discipline

Automated tests are REQUIRED for all non-trivial game and simulation logic. Test-first is
RECOMMENDED but NOT mandated.

- Every unit of simulation logic (physics, state transitions, scoring, spawning, timing,
  serialization) MUST have unit tests covering nominal and boundary behavior.
- A change to logic-bearing code MUST NOT merge without accompanying or updated tests.
- Rendering, shader, and view code are EXEMPT from mandatory unit tests where behavior is
  purely visual; such code SHOULD instead be validated via the performance gate (Principle III)
  and manual/visual verification recorded in the feature's quickstart.
- Tests MUST run deterministically and headlessly, with no GPU dependency.
- Tests MUST be runnable by a single checked-in command that requires no arguments and no
  machine-specific setup, so that every environment executes them identically.
- Once the repository has a remote, that command MUST be wired into CI and MUST gate merges. Until a
  remote exists, the checked-in command is the required substitute, and the absence of CI MUST be
  recorded in the plan's Complexity Tracking table.

**Rationale**: The team chose required-but-not-first testing. Mandating coverage for logic —
where correctness bugs hide — while exempting purely visual glue keeps the suite meaningful and
fast without imposing strict red-green-refactor on rendering code.

### III. Performance & Resource Efficiency

The game MUST minimize CPU and memory usage and hold a stable frame rate on target hardware.

- The render loop MUST sustain the target frame budget (60 fps → 16.6 ms/frame, or the
  documented target for the feature) on the minimum supported device.
- Per-frame heap allocation in the update/render hot path MUST be avoided; reuse buffers and
  pools. Allocations in the hot path MUST be justified in the plan's Complexity Tracking.
- Memory footprint targets (asset budgets, texture/buffer sizes) MUST be stated in the plan and
  MUST NOT regress without justification.
- Any feature touching the hot path MUST report a before/after measurement (frame time and/or
  allocations) as part of its acceptance evidence.

**Rationale**: Real-time games live or die by frame stability and battery/thermal behavior on
mobile. Efficiency is a first-class acceptance criterion, not an afterthought.

### IV. Accessibility & Platform UX

Non-gameplay UI MUST be accessible, and the game MUST respect each platform's conventions.

- SwiftUI menus, settings, and HUD chrome MUST support Dynamic Type, VoiceOver labels, and
  sufficient contrast; they MUST NOT rely on color alone to convey state.
- The game MUST honor system settings for reduced motion and MUST provide an alternative when
  motion-heavy effects are core to an interaction.
- iOS and macOS builds MUST follow their respective Human Interface Guidelines for input
  (touch/gesture vs. keyboard/mouse/trackpad), window/scene behavior, and expected controls.
- Gameplay-critical information MUST be perceivable through more than one channel where feasible
  (e.g., visual + haptic/audio).

**Rationale**: Accessibility and platform-native feel are correctness for a shipping app across
two platforms; retrofitting them is far more expensive than building them in.

### V. Simplicity & YAGNI

Solutions MUST be the simplest thing that satisfies the current, specified requirement.

- Abstractions, engines, generalized systems, and configuration knobs MUST NOT be introduced for
  speculative future needs. Build for the requirement in the spec, not an imagined one.
- Third-party dependencies MUST be justified; prefer the platform SDK (Swift, Metal, SwiftUI)
  before adding external packages.
- Any deviation adding structural complexity MUST be recorded in the plan's Complexity Tracking
  table with the simpler alternative it rejects and why.

**Rationale**: Games accrete premature "engine" complexity quickly. Enforcing YAGNI keeps the
codebase small enough to reason about, test, and keep performant.

## Technology & Platform Standards

- **Language & platforms**: Swift, targeting iOS and macOS from a shared multiplatform codebase.
- **Rendering**: Metal is the rendering backend. Shaders and GPU resource management MUST be
  contained within the rendering layer defined in Principle I.
- **UI shell**: SwiftUI for menus, settings, and chrome; the Metal surface is hosted within it.
- **Testing**: The native Swift test toolchain (XCTest and/or Swift Testing) run headlessly.
- **Source layout**: A shared/common target for simulation and rendering-agnostic code, with
  thin per-platform targets for entry points and platform integration.

## Development Workflow & Quality Gates

- All feature work follows the Spec-Driven Development cycle: `specify → plan → tasks →
  implement`, with the constitution's Principles enforced at the plan's **Constitution Check**
  gate before and after design.
- A change MUST NOT be considered complete unless it: (a) passes the required tests
  (Principle II), (b) includes performance evidence when it touches the hot path
  (Principle III), and (c) meets accessibility/platform expectations for any UI it adds
  (Principle IV).
- Complexity that violates Principle V MUST be justified in the plan's Complexity Tracking table
  or removed.
- Reviews MUST verify constitution compliance; unjustified violations block merge.

## Governance

This constitution supersedes ad-hoc engineering practice for swiftSky. It applies to all
features, refactors, and dependencies.

- **Amendments**: Proposed via a change to this file describing the amendment and its rationale.
  Amendments take effect once merged and MUST update the version and Sync Impact Report.
- **Versioning**: Semantic versioning of the constitution itself —
  MAJOR for backward-incompatible governance/principle removals or redefinitions,
  MINOR for a new principle/section or materially expanded guidance,
  PATCH for clarifications and non-semantic refinements.
- **Compliance**: Every plan MUST pass the Constitution Check gate; every review MUST confirm
  compliance. Violations MUST be justified in Complexity Tracking or resolved before merge.

**Version**: 1.1.0 | **Ratified**: 2026-07-24 | **Last Amended**: 2026-07-26
