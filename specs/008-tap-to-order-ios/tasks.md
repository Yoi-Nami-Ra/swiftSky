---

description: "Task list for 008-tap-to-order-ios"
---

# Tasks: Tap to Order the Ship on iOS

**Input**: Design documents from `/specs/008-tap-to-order-ios/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/tap-to-order.md, quickstart.md

**Tests**: Required. FR-013 calls for headless tests of the tap → world conversion and of applying an
order request, and constitution Principle II requires tests for non-trivial logic. Gesture recognition,
VoiceOver and logging are platform glue, checked through quickstart.md.

**Organization**: Tasks are grouped by user story, so each story can be implemented and validated on
its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US4)
- Paths are relative to the repository root. `R<n>` refers to research.md, `C<n>` to the guarantees
  in contracts/tap-to-order.md, and `check <n>` to quickstart.md.

## Path Conventions

- Platform layer: `Sources/SwiftSkyPlatform/`, tests in `Tests/SwiftSkyPlatformTests/`. Tests use
  `import SwiftSkyRendering`, `import SwiftSkySimulation`, `import Testing` and
  `@testable import SwiftSkyPlatform`.
- Tests never create a view, a layer, a `FrameLoop` or a Metal device: `verify.sh`'s headless guard
  fails the run on `MTLCreateSystemDefaultDevice`, `.makeCommandQueue(`, `.makeBuffer(` or `.makeTexture(`.
- "State unchanged" assertions use `SimulationState`'s `==`: no NaN can enter the state
  (`setOrder(to:)` rejects non-finite destinations), so `==` is exact here. `StateBits.swift` belongs
  to the simulation test target and is not reachable from the platform tests.
- The logic layer (`Sources/SwiftSkySimulation/`) and the rendering layer (`Sources/SwiftSkyRendering/`)
  MUST NOT change (FR-009, quickstart check 3).
- Run the tests with `swift test --build-system swiftbuild --explicit-target-dependency-import-check=error`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Let the platform tests name the rendering and logic types (R8).

- [ ] T001 Change `Package.swift`: give the `SwiftSkyPlatformTests` target `dependencies: ["SwiftSkyPlatform", "SwiftSkyRendering", "SwiftSkySimulation"]`, and extend its comment: it now also tests `MoveOrderRequest` (008 FR-013), which needs `RenderSurface`, `Vector2` and `SimulationState` named under `--explicit-target-dependency-import-check=error`; both extra modules are GPU-free to link (008 research R8)

**Checkpoint**: `swift build` and `swift test` pass unchanged.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The order request, its event and its application in the loop, which every story uses.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T002 Create `Sources/SwiftSkyPlatform/MoveOrderRequest.swift` (imports `SwiftSkyRendering`, `SwiftSkySimulation`): `public struct MoveOrderRequest: Sendable, Equatable` with `public let viewPoint: Vector2`, `public init(viewPoint: Vector2)`, and `func apply(to state: inout SimulationState, on surface: RenderSurface) -> MoveOrderOutcome` exactly as contracts/tap-to-order.md: `guard let camera = Camera(surface: surface) else { return .noCamera }`, `let destination = camera.world(fromView: viewPoint)`, `state.setOrder(to: destination) ? .ordered(destination: destination) : .invalidDestination`. Plus `enum MoveOrderOutcome: Equatable { case ordered(destination: Vector2), noCamera, invalidDestination }`. Doc comments: what it is ("order the ship to the world point under this view position"), view space (points, top-left origin, +y down, 005 FR-004), why it lives in the platform layer (the only layer that may name both `Camera` and `SimulationState`, R3), that it is platform-neutral and shared with SKY-11's click (FR-010), that a dropped request leaves the state untouched (FR-006, FR-007), and that it is pure and allocation-free (FR-011, FR-012)
- [ ] T003 Change `Sources/SwiftSkyPlatform/SurfaceEvent.swift`: add `case moveOrderRequested(MoveOrderRequest)` with a doc comment (a tap now, a click in SKY-11; carried as a view position and converted in the loop against the surface applied up to that event, R1, R2; FR-004, FR-005), and widen the enum's doc comment to say it carries input as well as surface changes, through the same one channel so the order between them is kept (R1). Depends on T002
- [ ] T004 Change `Sources/SwiftSkyPlatform/FrameLoop.swift`: in `applyPendingEvents()`, handle `case .moveOrderRequested(let request): _ = request.apply(to: &state, on: surface)` (the outcome is used for logging in T009). Update the doc comments: the class's isolation note (the queue now also carries order requests), `applyPendingEvents()` (events apply in queue order, so a request uses the surface as it stands after every earlier event in the same drain, C12), and the frame-ordering comment on `metalDisplayLink(_:needsUpdate:)` step 1 (an order applied here is flown by this frame's step-4 advance, C13, SC-005). Depends on T003

**Checkpoint**: `swift build` passes with no warnings; the existing tests pass. Nothing posts the event yet.

---

## Phase 3: User Story 1 - Tap to send the ship (Priority: P1) 🎯 MVP

**Goal**: A tap anywhere on the iOS surface sends the ship there and it comes to rest.

**Independent Test**: `./Scripts/verify.sh` runs C1, C2, C5 and C10; on the iPhone simulator, quickstart
checks 4, 6, 8, 9 and 10.

### Tests for User Story 1

- [ ] T005 [P] [US1] Create `Tests/SwiftSkyPlatformTests/MoveOrderRequestTests.swift` with a `@Suite("Move order request")` and tests for: C1 (the centre of a 393 × 852 pt surface at 3× gives `.ordered(destination: (0, 0))`); C2 (several view points on a 2× surface give `(vx − w/2, h/2 − vy)`, equal to `Camera(surface:)!.world(fromView:)`, and points right of / above centre give positive x / y); C5 (after `.ordered(d)`, `state.autopilot.order?.destination == d` and `state.autopilot.phase != nil`); C10 (apply a request, then `Simulation.advance(_, ticks: 1)`; compare with a copy on which `setOrder(to: d)` was called directly, then advanced: equal). A small helper `surface(widthPoints:heightPoints:scale:)` builds a `RenderSurface` with `widthPixels = UInt32(w × s)`, `heightPixels = UInt32(h × s)`

### Implementation for User Story 1

- [ ] T006 [US1] Change `Sources/SwiftSkyPlatform/MetalSurfaceView.swift`, iOS only (`#if os(iOS)`): in `configure(device:)`, call a new `registerForTaps()` that adds a `UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))` with `numberOfTapsRequired = 1` and `numberOfTouchesRequired = 1`; `@objc private func tapped(_ recognizer: UITapGestureRecognizer)` takes `recognizer.location(in: self)` and calls `onSurfaceChange?(.moveOrderRequested(MoveOrderRequest(viewPoint: Vector2(x: Double(p.x), y: Double(p.y)))))` (add `import SwiftSkySimulation`). Doc comments: the system recogniser is the platform's definition of a tap and leaves system gestures alone (FR-001, FR-003, R4); `location(in:)` is in this view's points, the camera's view space, and the view fills the window so the whole surface is tappable (FR-002); the action runs on the main thread and only posts (FR-004). Widen `onSurfaceChange`'s doc comment, and the `attach` doc comment in `Sources/SwiftSkyPlatform/MetalSurfaceRepresentable.swift`, to say the sink now also carries taps (R4)
- [ ] T007 [US1] Change `Sources/SwiftSkyPlatform/MetalSurfaceView.swift` `configureAccessibility()`: on iOS set `accessibilityTraits = [.image, .allowsDirectInteraction]`, label unchanged, with a comment (with VoiceOver on, taps on the surface reach the game and order the ship, FR-014, R5, clarification). macOS unchanged. Depends on T006 (same file)
- [ ] T008 [P] [US1] Change `Sources/SwiftSkyPlatform/Instrumentation.swift`: add `import SwiftSkySimulation`; under `SWIFTSKY_INSTRUMENTATION` add `func recordOrder(_ outcome: MoveOrderOutcome, viewPoint: Vector2)`, logging at `notice` with `privacy: .public` either `order view=(x, y) world=(x, y)` or `order dropped view=(x, y) reason=no-camera` / `reason=invalid-destination`, and `func recordArrival(position: Vector2, tickCount: UInt64)`, logging `arrived world=(x, y) ticks=n`. Both only ever called on frames with a tap or an arrival, so nothing is formatted per frame (FR-011, FR-015, R6). Add matching `@inline(__always)` empty no-ops in the Release `#else` branch. Update the type's doc comment (it now also logs orders and arrivals)
- [ ] T009 [US1] Change `Sources/SwiftSkyPlatform/FrameLoop.swift`: in `applyPendingEvents()`, pass the outcome and the request's `viewPoint` to `instrumentation.recordOrder(_:viewPoint:)`; add a loop-thread `private var arrivalLogged = true` (no order at launch, so nothing to log) under `#if SWIFTSKY_INSTRUMENTATION`; set it to `false` whenever an outcome is `.ordered`; in `metalDisplayLink(_:needsUpdate:)` after the step-4 advance, if `state.autopilot.phase == .arrived && !arrivalLogged`, call `instrumentation.recordArrival(position: state.ship.position, tickCount: state.tickCount)` and set it to `true`, and if the phase is anything other than `.arrived`, set it to `false`. All of it under `#if SWIFTSKY_INSTRUMENTATION`, so Release does no comparison. Comment: a flag rather than a before/after comparison, because `setOrder` evaluates the phase at once and an order to the ship's own position is already arrived before the advance; each arrival is logged once, including that one (R6, SC-007b). Depends on T004, T008
- [ ] T010 [US1] Run `./Scripts/verify.sh`, then quickstart check 4 on the iPhone and the iPad simulators, and checks 6, 8, 9 and 10 on the iPhone simulator, and record them in the Evidence section of `specs/008-tap-to-order-ios/quickstart.md`

**Checkpoint**: Tapping sends the ship; the log shows each order and arrival. MVP complete.

---

## Phase 4: User Story 2 - A new tap changes the plan (Priority: P2)

**Goal**: A tap mid-flight replaces the order; several taps in one frame leave the last.

**Independent Test**: `./Scripts/verify.sh` runs C8 and C9; quickstart check 5.

### Tests for User Story 2

- [ ] T011 [US2] Add to `Tests/SwiftSkyPlatformTests/MoveOrderRequestTests.swift`: C8 (on a state with the ship flying towards A, after a few ticks of `Simulation.advance`, apply request B: the order is B's destination, and the state equals a copy on which `setOrder(to: B)` was called directly; applying A then B in one go leaves B, as two requests drained in one frame would); C9 (a request at the view position of the ship's own world point, at rest at the origin, orders it there, and after `Simulation.advance(_, ticks: 60)` the phase is `.arrived` and the position is unchanged within the arrival tolerance)

### Implementation for User Story 2

- [ ] T012 [US2] No code: confirm by review that `FrameLoop.applyPendingEvents()` applies every drained event in order (the loop over `events`), so a burst of taps ends with the last (US2-2, C12). Run quickstart check 5 on the iPhone simulator and record it in the Evidence section of `specs/008-tap-to-order-ios/quickstart.md`

**Checkpoint**: Re-ordering mid-flight works and is tested.

---

## Phase 5: User Story 3 - Every iPhone and iPad layout (Priority: P3)

**Goal**: The conversion is right on every surface shape, scale and resize, and drops taps on a surface
with no camera.

**Independent Test**: `./Scripts/verify.sh` runs C3, C4, C6 and C7; quickstart checks 7 and 11.

### Tests for User Story 3

- [ ] T013 [US3] Add to `Tests/SwiftSkyPlatformTests/MoveOrderRequestTests.swift`, parameterised with `@Test(arguments:)`: C3 (the four corners and the centre on 393 × 852, 852 × 393, 320 × 1,194 and 1,001 × 667 point surfaces at 2×, within 1e-9 of (±w/2, ±h/2) and (0, 0)); C4 (one view point on the same size in points at scales 1, 2 and 3 gives identical destinations, using sizes whose pixel counts are whole at every scale); C6 (zero width, zero height, and a backing scale of 0 and `.nan`, give `.noCamera`, with a state that already has an order left `==` to before); C7 (`viewPoint` with `.infinity` or `.nan` components gives `.invalidDestination`, state `==` to before)

### Implementation for User Story 3

- [ ] T014 [US3] No code: the conversion is the camera's, applied against the loop's current surface (R2). Run quickstart check 7 (iPhone landscape) and check 11 (iPad Split View at every width, Slide Over, resize mid-flight) on the simulators and record them in the Evidence section of `specs/008-tap-to-order-ios/quickstart.md`

**Checkpoint**: Every layout is covered by tests and checked on the iPad simulator.

---

## Phase 6: User Story 4 - The macOS click can reuse it (Priority: P4)

**Goal**: The order request and its conversion are platform-neutral and verified on macOS.

**Independent Test**: quickstart check 13.

### Implementation for User Story 4

- [ ] T015 [US4] Review `Sources/SwiftSkyPlatform/MoveOrderRequest.swift`, `SurfaceEvent.swift` and `FrameLoop.swift` for iOS-only code: there must be none outside `MetalSurfaceView.swift`'s `#if os(iOS)` blocks (FR-010, C16). Add one sentence to `MoveOrderRequest`'s doc comment telling SKY-11 what is left to do (post `.moveOrderRequested` from a click's location in the view's points, flipped from AppKit's bottom-left origin unless the view is flipped). Run quickstart check 13 (`./Scripts/verify.sh` builds the macOS app and runs `MoveOrderRequestTests` on the Mac host) and record it in the Evidence section of `specs/008-tap-to-order-ios/quickstart.md`

**Checkpoint**: SKY-11 can start from a posted event.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T016 [P] Update `CLAUDE.md`: add `specs/008-tap-to-order-ios` to "Built so far" (a tap on iOS orders the ship; macOS click is SKY-11), add `MoveOrderRequest.swift` and the `.moveOrderRequested` event to "Key locations" (pure, platform-neutral, converted in the loop against the applied surface), note that the platform tests now depend on the rendering and logic layers, and that Debug builds log `order …` and `arrived …` lines under subsystem `com.swiftsky.app`
- [ ] T017 [P] Update `.tickets/10.yaml` `status` to `done`
- [ ] T018 Run quickstart check 12: Profiling builds of `main` (before, e.g. from a `git worktree`) and of this branch (after) on the same iOS destination, 30 s each, the after run with a tap every ~2 s; record both runs' frame summaries and Allocations results side by side (Principle III); run check 14 (Release logs no `order` or `arrived` lines; `strings` on the Release binary finds neither) and check 3 (`git diff main --stat -- Sources/SwiftSkySimulation Sources/SwiftSkyRendering` is empty). Record them in the Evidence section
- [ ] T019 Run `./Scripts/verify.sh` and fill in the rest of the Evidence section of `specs/008-tap-to-order-ios/quickstart.md`, marking any check not run with its reason

---

## Dependencies & Execution Order

- **Setup (Phase 1)**: T001. Blocks the tests.
- **Foundational (Phase 2)**: T002 → T003 → T004. Blocks every story.
- **US1 (Phase 3)**: after Phase 2. T005 ∥ T006 ∥ T008; T006 → T007; T004 + T008 → T009; T010 last. MVP.
- **US2 (Phase 4)**: after Phase 2 for the tests; after US1 for check 5 (needs the recogniser).
- **US3 (Phase 5)**: after Phase 2 for the tests; after US1 for checks 7 and 11.
- **US4 (Phase 6)**: after Phase 2.
- **Polish (Phase 7)**: after all stories.

### Parallel Opportunities

- T005 ∥ T006 ∥ T008; T016 ∥ T017.
- T005, T011 and T013 share one file: they are parallel only across separate branches, with a merge.

### Parallel Example: User Story 1

```text
Task: "T005 Create MoveOrderRequestTests.swift (C1, C2, C5, C10)"
Task: "T006 Add the iOS tap recogniser to MetalSurfaceView.swift"
Task: "T008 Add recordOrder / recordArrival to Instrumentation.swift"
```

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 + Phase 2: the build passes with all existing tests.
2. Phase 3: taps send the ship. **Stop and validate**: checks 4 and 6.

### Incremental Delivery

US2 (replace mid-flight) → US3 (every layout) → US4 (macOS-ready) → Polish. Each phase ends green and
is committed on its own.
