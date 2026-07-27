---

description: "Task list for 001-metal-app-shell"
---

# Tasks: Metal App Shell

**Input**: Design documents from `/specs/001-metal-app-shell/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/](./contracts/), [quickstart.md](./quickstart.md)

**Tests**: Test tasks ARE included. Tests are explicitly required by FR-017 (headless test target),
SC-007 (deterministic across 10 runs) and SC-013 (byte-identical state), and mandated by Principle II
for logic-bearing code. Rendering code is exempt per Principle II and has no unit tests here — it is
verified visually and through the performance gate.

**Organization**: Tasks are grouped by user story. See the honest dependency note under
[Phase 4](#phase-4-user-story-2---player-launches-the-app-on-ios-and-sees-a-black-screen-priority-p2)
about US2's reliance on US1.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- Exact file paths included in every task
- Execution order is given by phase placement, not by task ID. IDs are append-only, so tasks added
  after the first generation (T056, T057) sit in the phase where they belong rather than at the end —
  this keeps earlier ID references stable

## Path Conventions

Per [plan.md](./plan.md) Project Structure: layer libraries in `Sources/<Layer>/`, app entry points in
`Apps/<platform>/`, tests in `Tests/`, scripts in `Scripts/`. All paths are repository-root-relative.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Package manifest, layer targets, and the build configuration that later requirements
depend on. Under topology B (research.md R1 revised) the layer targets live in `Package.swift`; the
Xcode project holds only the two app targets, so T004, T007 and T008 land with the app entry points.

- [X] T001 Create the root `Package.swift` declaring the layer targets and platform floor (topology B, research.md R1 revised). The three Xcode build configurations — Debug, Release, Profiling — move to `swiftSky.xcodeproj` when the app targets are added in T004 (per research.md R12)
- [X] T002 [P] Create the directory skeleton: `Sources/SwiftSkySimulation/`, `Sources/SwiftSkyRendering/`, `Sources/SwiftSkyPlatform/`, `Apps/iOS/`, `Apps/macOS/`, `Tests/SwiftSkySimulationTests/`, `Scripts/`
- [X] T003 Declare the three library targets in `Package.swift` — `SwiftSkySimulation` (no dependencies), `SwiftSkyRendering` (depends on Simulation), `SwiftSkyPlatform` (depends on Rendering + Simulation) — establishing FR-013's compile-time enforcement
- [ ] T004 Add the two app targets `swiftSky (iOS)` and `swiftSky (macOS)` to `swiftSky.xcodeproj`, each depending on `SwiftSkyPlatform`
- [X] T005 [P] Set Swift 6 language mode and strict concurrency checking on every target via `swiftLanguageMode(.v6)` in `Package.swift` (FR-030, SC-015)
- [X] T006 [P] Set the platform floor to iOS 26.0 and macOS 26.0 in `Package.swift` (requires `swift-tools-version: 6.2`), with no availability fallbacks (FR-022)
- [ ] T007 [P] Define the `SWIFTSKY_INSTRUMENTATION` custom Swift compilation condition in `swiftSky.xcodeproj` for Debug and Profiling only, never Release (FR-021e)
- [ ] T008 [P] Restrict the iOS target's Supported Destinations in `swiftSky.xcodeproj` to iPhone and iPad — remove "Mac (Designed for iPad)" and do not enable Mac Catalyst (FR-016a, SC-018)
- [X] T009 [P] Extend `.gitignore` to cover Xcode project user state (`*.xcodeproj/xcuserdata/`, `*.xcodeproj/project.xcworkspace/xcuserdata/`) (FR-019)

**Checkpoint**: `Package.swift` resolves, the layer dependency graph is in place, and
`swift build`/`swift test` become meaningful once Phase 2 supplies target sources

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The logic layer's value types and the render layer's boundary types. These are the
compile-time boundary itself, so every story depends on them.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [X] T010 [P] Implement `FixedTimestep` constants — `tickRate` 60, `tickDuration` 1.0/60.0, `catchUpClamp` 4 — in `Sources/SwiftSkySimulation/FixedTimestep.swift` (FR-021a, FR-021b)
- [X] T011 [P] Implement `SimulationState` value type holding only `tickCount: UInt64` in `Sources/SwiftSkySimulation/SimulationState.swift` (FR-012a, FR-012b, data-model.md)
- [X] T012 Implement `TimeAccumulator` value type with `consume(elapsed:) -> Int`, clamping at 4 ticks and discarding excess, in `Sources/SwiftSkySimulation/TimeAccumulator.swift` (depends on T010; FR-021a, FR-021b)
- [X] T013 Implement the pure `Simulation.advance(_:ticks:)` function in `Sources/SwiftSkySimulation/Simulation.swift` (depends on T011; FR-012c, FR-033)
- [X] T014 Audit all three layers for forbidden constructs — zero `import` statements and no `actor`, `@MainActor`, or lock usage in `Sources/SwiftSkySimulation/`; no `static var`, `nonisolated(unsafe)`, or top-level `var` in any layer; no interpolation between simulation states in `Sources/SwiftSkyRendering/` — and record in `specs/001-metal-app-shell/quickstart.md` checks 18 and 42 (FR-012c, FR-015, FR-021c)
- [X] T015 [P] Implement `RenderSurface` value type with `widthPixels`, `heightPixels`, `backingScale`, and `isRenderable` in `Sources/SwiftSkyRendering/RenderSurface.swift` (data-model.md)
- [X] T016 [P] Implement `RendererError` with all initialisation failure cases and `userFacingDescription` in `Sources/SwiftSkyRendering/RendererError.swift` (FR-024, FR-026, contracts/layer-interfaces.md)

**Checkpoint**: Foundation ready — the simulation layer is complete and independently compilable, so
US3's test tasks (T038–T040) may begin in parallel with US1 from here

---

## Phase 3: User Story 1 - Player launches the app on macOS and sees a black window (Priority: P1) 🎯 MVP

**Goal**: A resizable 1280×720 macOS window whose content area is uniformly black, produced by a real
shader-backed draw call on a display-paced off-main frame loop. This story carries the shared rendering
engine, because it is the story that proves it.

**Independent Test**: Build and run the macOS target; observe a black window; resize through its full
range including to the 640×360 minimum and full screen; move between displays; close it and confirm the
app quits. No non-black frame at any point.

**Note on tests**: This story adds no unit tests. Its deliverables are rendering and platform-hosting
code, exempt from mandatory unit testing under Principle II and verified visually plus through the
performance gate.

### Implementation for User Story 1

- [ ] T017 [US1] Write the vertex and fragment shaders — full-screen quad in clip space, fragment returns `(0, 0, 0, 1)` — in `Sources/SwiftSkyRendering/Shaders.metal` (FR-002a, FR-002c, research.md R11)
- [ ] T018 [US1] Implement `FullscreenQuad` creating the vertex buffer and pipeline state exactly once at initialisation in `Sources/SwiftSkyRendering/FullscreenQuad.swift` (depends on T017; FR-002b)
- [ ] T019 [US1] Implement `Renderer` — throwing `init(device:pixelFormat:)` and allocation-free `render(state:surface:into:) -> Bool` returning `false` when no drawable is available — in `Sources/SwiftSkyRendering/Renderer.swift` (depends on T015, T016, T018; FR-002a, FR-020, FR-027a, contracts/layer-interfaces.md)
- [X] T020 [P] [US1] *(completed early with Phase 2 — SwiftPM requires every declared target to have sources, and `SwiftSkyPlatform` was otherwise empty)* Implement the `SurfaceEvent` enum with `resized`, `backingScaleChanged`, `visibilityChanged`, `willTerminate` in `Sources/SwiftSkyPlatform/SurfaceEvent.swift` (FR-029, data-model.md)
- [ ] T021 [P] [US1] Implement `MetalSurfaceView` — a bare `NSView`/`UIView` backed by a `CAMetalLayer` configured `bgra8Unorm_srgb`, opaque, sRGB — that draws nothing itself and exposes an accessibility description, in `Sources/SwiftSkyPlatform/MetalSurfaceView.swift` (FR-001, FR-002c, FR-007, FR-009, research.md R6, R10)
- [ ] T022 [P] [US1] Implement allocation-free `Instrumentation` recording frame duration, draw-path allocation count, and separate skipped-frame and dropped-frame counters, gated on `SWIFTSKY_INSTRUMENTATION`, in `Sources/SwiftSkyPlatform/Instrumentation.swift` (FR-021d, FR-021e, FR-021f, FR-027c)
- [ ] T056 [US1] Log the `SimulationState.tickCount` the renderer received each frame from `Sources/SwiftSkyPlatform/Instrumentation.swift` under `SWIFTSKY_INSTRUMENTATION`, so the live logic→render hand-off is observable, and verify quickstart check 40 (depends on T022; SC-020, FR-012a)
- [ ] T023 [US1] Implement `MetalSurfaceRepresentable` as `NSViewRepresentable` for macOS in `Sources/SwiftSkyPlatform/MetalSurfaceRepresentable.swift` (depends on T021; FR-007)
- [ ] T024 [US1] Implement `FrameLoop` — serial `.userInteractive` queue, `CAMetalDisplayLink` callback on that queue, and the normative six-step per-frame sequence — in `Sources/SwiftSkyPlatform/FrameLoop.swift` (depends on T012, T013, T019, T020, T022; FR-020, FR-021, FR-028, FR-031, FR-033, contracts/frame-loop.md)
- [ ] T025 [US1] Implement non-blocking `post(_:)` event marshalling and frame-boundary event application in `Sources/SwiftSkyPlatform/FrameLoop.swift` (depends on T024; FR-029, FR-031)
- [ ] T026 [US1] Implement skipped-frame handling — retain accumulated time, count the skip, never terminate or notify — in `Sources/SwiftSkyPlatform/FrameLoop.swift` (depends on T024; FR-027a, FR-027b)
- [ ] T027 [US1] Implement `stopAndDrain()` with explicit teardown ordering — loop stopped and drained before any graphics resource is released — in `Sources/SwiftSkyPlatform/FrameLoop.swift` (depends on T024; FR-032)
- [ ] T028 [US1] Implement start/stop on visibility change so no frames are produced while content is not visible, in `Sources/SwiftSkyPlatform/FrameLoop.swift` (depends on T025; FR-008, FR-021)
- [ ] T029 [P] [US1] Implement `RendererFailureNotice` — text-only, no graphics or branding, dismiss-only, Dynamic Type and screen-reader readable — in `Sources/SwiftSkyPlatform/RendererFailureNotice.swift` (FR-024, FR-025)
- [ ] T030 [US1] Implement renderer construction on the main thread before loop start, routing any `RendererError` to the notice plus an FR-026 diagnostic and a debug-build trap, with no fallback surface, in `Sources/SwiftSkyPlatform/FrameLoop.swift` (depends on T019, T029; FR-024, FR-026, FR-027, contracts/frame-loop.md)
- [ ] T031 [US1] Implement the macOS app entry point using a SwiftUI `Window` scene (not `WindowGroup`) with `.defaultSize(width: 1280, height: 720)`, content `.frame(minWidth: 640, minHeight: 360)` and `.windowResizability(.contentMinSize)` in `Apps/macOS/SwiftSkyApp.swift` (depends on T023, T030; FR-006, FR-006a, FR-006c, FR-006d, research.md R7, R8)
- [ ] T032 [P] [US1] Configure `Apps/macOS/Info.plist` with a black initial window background so no light frame appears before the first draw (FR-004a)
- [ ] T033 [US1] Run quickstart checks 1, 2, 4, 5, 6, 7, 8, 9, 10, 13 against the macOS build and record outcomes in `specs/001-metal-app-shell/quickstart.md`

**Checkpoint**: macOS app launches to a black window drawn by a real shader pass; MVP is deliverable

---

## Phase 4: User Story 2 - Player launches the app on iOS and sees a black screen (Priority: P2)

**Goal**: The same shared code driving a black full-screen surface on iOS, landscape-only, through a
different platform entry point.

**Independent Test**: Build and run the iOS target on a device and a simulator; observe a black
full-screen surface; rotate between landscape orientations; confirm portrait is refused; background and
foreground the app.

**⚠️ Honest dependency note**: US2 is *not* independent of US1. The spec's own rationale for US2 is that
it "exercises the same shared code through a different platform entry point" — so the rendering engine
built in Phase 3 is a prerequisite. What US2 adds is genuinely small and iOS-specific: an entry point,
plist configuration, and a representable variant. Treating it as independently *startable* would be
false; it is independently *testable*, which is what matters for the checkpoint.

### Implementation for User Story 2

- [ ] T034 [US2] Add the `UIViewRepresentable` variant for iOS to `Sources/SwiftSkyPlatform/MetalSurfaceRepresentable.swift` (depends on T023; FR-005, FR-007)
- [ ] T035 [US2] Implement the iOS app entry point with a single scene in `Apps/iOS/SwiftSkyApp.swift` (depends on T034, T030; FR-005, FR-006c)
- [ ] T036 [P] [US2] Configure `Apps/iOS/Info.plist` — supported orientations limited to `UIInterfaceOrientationLandscapeLeft` and `UIInterfaceOrientationLandscapeRight`, `UIApplicationSupportsMultipleScenes` set to `false`, and a `UILaunchScreen` dictionary with a black background and no image (FR-004a, FR-006b, FR-006c, research.md R13)
- [ ] T037 [US2] Wire iOS scene visibility and orientation/size changes into `SurfaceEvent` delivery, tolerating arbitrary surface dimensions including portrait-shaped iPad multitasking sizes, in `Sources/SwiftSkyPlatform/MetalSurfaceView.swift` (depends on T035; FR-006b, FR-008, FR-029)
- [ ] T038 [US2] Run quickstart checks 3, 11, 12 against the iOS build and record outcomes in `specs/001-metal-app-shell/quickstart.md`

**Checkpoint**: Both platforms present an identical black surface from shared code

---

## Phase 5: User Story 3 - Developer adds and tests logic without a GPU or a running app (Priority: P3)

**Goal**: A headless, deterministic test suite for the simulation layer, and one-time proof that all
three forbidden dependency directions fail to compile.

**Independent Test**: Run the test suite with no GPU and no simulator UI; it passes in under 10 seconds
and identically across 10 runs. Introduce a violating import in each forbidden direction and confirm
each fails to build.

**Parallel opportunity**: T039–T041 depend only on Phase 2 and can be worked in parallel with Phase 3.

### Tests for User Story 3

- [ ] T039 [US3] Add the `SwiftSkySimulationTests` test target to `swiftSky.xcodeproj` using Swift Testing, depending on `SwiftSkySimulation` only, with no app host (FR-017, research.md R9)
- [ ] T040 [P] [US3] Write `TimeAccumulator` tests covering sub-tick accumulation returning zero ticks, exact multiples, remainder carry, and the clamp — including that a 10-second span advances exactly 4 ticks, not 600 — in `Tests/SwiftSkySimulationTests/TimeAccumulatorTests.swift` (depends on T039; FR-021b, SC-013)
- [ ] T041 [P] [US3] Write `Simulation` determinism tests asserting identical tick sequences produce byte-identical state, and that one long elapsed span and many short ones agree subject to the clamp, in `Tests/SwiftSkySimulationTests/SimulationTests.swift` (depends on T039; SC-013)

### Implementation for User Story 3

- [ ] T042 [US3] Write `Scripts/verify.sh` — builds both destinations and runs the headless suite with no arguments on a clean clone, exiting non-zero on any build or test failure (depends on T039; FR-019a, SC-008a)
- [ ] T043 [US3] Prove each forbidden direction fails to build (logic→rendering, logic→platform, rendering→platform) by temporarily adding a violating import, then revert, and paste the three compiler errors into the SC-009 evidence block in `specs/001-metal-app-shell/quickstart.md` (SC-009, FR-013)
- [ ] T044 [US3] Run quickstart checks 15–23 and record outcomes in `specs/001-metal-app-shell/quickstart.md`

**Checkpoint**: All three user stories independently functional and verified

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: The measurement, failure-path, accessibility and concurrency gates that span all stories

- [ ] T045 Confirm the macOS baseline device model against <https://support.apple.com/en-us/122867> and correct R2 in `specs/001-metal-app-shell/research.md` if the oldest supported Mac differs from `MacBook Pro (16-inch, 2019)`
- [ ] T046 [P] Build Release and confirm via symbol inspection (`nm`/`strings`) that no symbols from `Sources/SwiftSkyPlatform/Instrumentation.swift` are present in the built product, recording the result in `specs/001-metal-app-shell/quickstart.md` check 27 (SC-004a, FR-021e)
- [ ] T047 [P] Measure idle memory footprint on both baseline devices, confirm it is under 150 MB (iOS) / 250 MB (macOS), and record the measured values in the SC-005 baseline block in `specs/001-metal-app-shell/quickstart.md`
- [ ] T048 [P] Measure median frame time over a 60-second idle session on both baseline devices, confirm zero dropped and zero skipped frames, and record values in `specs/001-metal-app-shell/quickstart.md` (SC-003, SC-004)
- [ ] T049 Confirm `swiftSky.xcodeproj` builds with zero strict-concurrency warnings, then run a 10-second continuous macOS resize under Thread Sanitizer and a sustained run under Address Sanitizer, expecting zero races, zero memory errors, and no main-thread stall beyond one frame interval; record results in `specs/001-metal-app-shell/quickstart.md` checks 28–30 (SC-015, SC-016)
- [ ] T050 Launch and quit the app 20 consecutive times on both platforms, including quits issued mid-draw, confirming zero crashes and zero hangs on exit and that `stopAndDrain()` in `Sources/SwiftSkyPlatform/FrameLoop.swift` ordering holds; record in `specs/001-metal-app-shell/quickstart.md` check 31 (SC-017, FR-032)
- [ ] T051 [P] Temporarily force intermittent drawable-acquisition failure in `Sources/SwiftSkyRendering/Renderer.swift`, confirm the app keeps running with skips counted separately from drops, nothing shown to the user, and tick count tracking elapsed time within the clamp; revert and record in `specs/001-metal-app-shell/quickstart.md` check 35 (SC-021, FR-027a–c)
- [ ] T052 [P] Temporarily rename a shader function in `Sources/SwiftSkyRendering/Shaders.metal` to force renderer initialisation failure, confirm on both platforms that the text-only notice names the cause, exits on dismissal, leaves a matching diagnostic, traps in debug builds, and is readable with a screen reader active; revert and record in `specs/001-metal-app-shell/quickstart.md` checks 32–34 (SC-012, FR-024–FR-026)
- [ ] T053 [P] Verify with VoiceOver that the accessibility description set in `Sources/SwiftSkyPlatform/MetalSurfaceView.swift` is reported meaningfully rather than skipped or announced as unlabelled, and that enabling Reduce Motion changes nothing and raises no assertion; record in `specs/001-metal-app-shell/quickstart.md` checks 36–37 (SC-011, FR-009)
- [ ] T057 [P] Audit `Sources/SwiftSkyPlatform/` for user-visible drawing — grep for `backgroundColor`, `NSColor`, `UIColor`, `draw(`, `.background(`, `Rectangle(`, `Color.` — confirming zero matches outside `RendererFailureNotice.swift`, and record in `specs/001-metal-app-shell/quickstart.md` check 41 (SC-002, FR-001, FR-007)
- [ ] T054 [P] Confirm zero third-party package dependencies in `swiftSky.xcodeproj` and that `git status` is clean after a full build (SC-010, FR-018, FR-019)
- [ ] T055 Complete a full pass of all 42 checks in `specs/001-metal-app-shell/quickstart.md`, with the SC-009 and SC-005 fill-in blocks populated

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **User Story 1 (Phase 3)**: Depends on Phase 2. Carries the shared rendering engine.
- **User Story 2 (Phase 4)**: Depends on Phase 2 **and Phase 3** — see the honest dependency note in
  Phase 4. It is independently testable, not independently startable.
- **User Story 3 (Phase 5)**: Depends on Phase 2 only. **Can run fully in parallel with Phase 3.**
- **Polish (Phase 6)**: Depends on Phases 3 and 4 (measurement needs a running app on both platforms)

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational. The MVP.
- **US2 (P2)**: Depends on US1's engine (T019–T030). Adds ~5 iOS-specific tasks.
- **US3 (P3)**: Depends only on Foundational — genuinely independent of US1 and US2, and the best
  candidate for parallel work.

### Within Each User Story

- Shaders before pipeline state before renderer (T017 → T018 → T019)
- Boundary types before the loop that transfers them (T020 → T024)
- Loop core before its lifecycle behaviours (T024 → T025, T026, T027, T028)
- Renderer and notice before failure wiring (T019, T029 → T030)
- Everything before its quickstart verification task

### Parallel Opportunities

- Phase 1: T002, T005–T009 in parallel after T001; T003 before T004
- Phase 2: T010, T011, T015, T016 all in parallel; then T012 (needs T010) and T013 (needs T011)
- Phase 3: T020, T021, T022 in parallel; T029 and T032 in parallel with the loop work
- Phase 5: T040 and T041 in parallel once T039 lands
- Phase 6: T046, T047, T048, T051, T052, T053, T054, T057 all in parallel
- **Cross-phase**: all of Phase 5 in parallel with all of Phase 3

---

## Parallel Example: Phase 2 Foundational

```bash
# Launch the four independent value types together:
Task: "Implement FixedTimestep constants in Sources/SwiftSkySimulation/FixedTimestep.swift"
Task: "Implement SimulationState in Sources/SwiftSkySimulation/SimulationState.swift"
Task: "Implement RenderSurface in Sources/SwiftSkyRendering/RenderSurface.swift"
Task: "Implement RendererError in Sources/SwiftSkyRendering/RendererError.swift"
```

## Parallel Example: User Story 1 platform pieces

```bash
# Independent files, no shared dependencies:
Task: "Implement SurfaceEvent in Sources/SwiftSkyPlatform/SurfaceEvent.swift"
Task: "Implement MetalSurfaceView in Sources/SwiftSkyPlatform/MetalSurfaceView.swift"
Task: "Implement Instrumentation in Sources/SwiftSkyPlatform/Instrumentation.swift"
Task: "Implement RendererFailureNotice in Sources/SwiftSkyPlatform/RendererFailureNotice.swift"
```

## Parallel Example: US3 alongside US1

```bash
# Different developer, only needs Phase 2:
Task: "Add SwiftSkySimulationTests target using Swift Testing"
Task: "Write TimeAccumulator tests in Tests/SwiftSkySimulationTests/TimeAccumulatorTests.swift"
Task: "Write Simulation determinism tests in Tests/SwiftSkySimulationTests/SimulationTests.swift"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup — project and targets
2. Complete Phase 2: Foundational — the simulation layer and boundary types
3. Complete Phase 3: User Story 1 — the engine plus the macOS shell
4. **STOP and VALIDATE**: run quickstart checks 1, 2, 4–10, 13
5. A black macOS window drawn by a real shader pass is a demonstrable milestone

### Incremental Delivery

1. Setup + Foundational → the compile-time layer boundary exists
2. Add US1 → macOS black window → **MVP**
3. Add US2 → iOS black screen from the same shared code
4. Add US3 → headless determinism suite and the boundary proofs
5. Polish → measurement baselines, sanitiser gates, failure and accessibility paths

### Parallel Team Strategy

With two developers, after Phase 2 completes:

- **Developer A**: Phase 3 (US1) — the rendering engine and macOS shell, then Phase 4 (US2)
- **Developer B**: Phase 5 (US3) — test target, determinism suite, `verify.sh`, boundary proofs

This split is genuine: US3 touches only `Tests/`, `Scripts/`, and the simulation layer that Phase 2
already finished, so it cannot conflict with US1's work in `Sources/SwiftSkyRendering/` and
`Sources/SwiftSkyPlatform/`.

---

## Notes

- Total: **57 tasks** — 9 setup, 7 foundational, 18 US1, 5 US2, 6 US3, 12 polish (T056 and T057 were
  added by `/speckit-analyze` to close SC-020 and SC-002 coverage gaps)
- [P] tasks touch different files with no incomplete dependencies
- Rendering code has no unit tests by design (Principle II exemption); it is gated on visual
  verification and the performance criteria instead
- T014 and T043 exist because FR-012c and FR-013 are enforced by structure and audit rather than by a
  standing automated test — a permanently failing build cannot be committed (SC-009)
- The off-main frame loop (T024–T028) is the feature's largest complexity and is justified in
  [plan.md](./plan.md) Complexity Tracking; keep it confined to `FrameLoop.swift` so FR-012c holds
- Commit after each task or logical group; stop at any checkpoint to validate independently
