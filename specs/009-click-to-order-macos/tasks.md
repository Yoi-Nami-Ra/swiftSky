---

description: "Task list for 009-click-to-order-macos"
---

# Tasks: Click to Order the Ship on macOS

**Input**: Design documents from `/specs/009-click-to-order-macos/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/click-to-order.md, quickstart.md

**Tests**: Required. FR-008 calls for headless tests of the click-position flip together with 008's
conversion (Principle II). Recognition, modifiers, inactive windows and VoiceOver are platform glue,
checked through quickstart.md.

**Organization**: Tasks are grouped by user story, so each story can be implemented and validated on
its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US3)
- Paths are relative to the repository root. `R<n>` refers to research.md, `C<n>` to the guarantees
  in contracts/click-to-order.md, and `check <n>` to quickstart.md.

## Path Conventions

- Platform layer: `Sources/SwiftSkyPlatform/`, tests in `Tests/SwiftSkyPlatformTests/` (imports
  `SwiftSkyRendering`, `SwiftSkySimulation`, `Testing`, `@testable import SwiftSkyPlatform`, as
  `MoveOrderRequestTests.swift`).
- Tests never create a view, a window or a Metal device (`verify.sh`'s headless guard).
- `MoveOrderRequest.swift`, `SurfaceEvent.swift`, `FrameLoop.swift`, `Instrumentation.swift`, the logic
  layer and the rendering layer MUST NOT change (FR-007, quickstart check 2). In `MetalSurfaceView.swift`
  only `#if os(macOS)` code changes.
- Run the tests with `swift test --build-system swiftbuild --explicit-target-dependency-import-check=error`.

---

## Phase 1: Setup (Shared Infrastructure)

No setup: the platform test target already depends on the rendering and logic layers (008 T001).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The pure flip every story uses.

- [X] T001 Create `Sources/SwiftSkyPlatform/ClickPosition.swift` (imports `SwiftSkySimulation` only, no AppKit): `enum ClickPosition` with `static func viewPoint(fromBottomLeft position: Vector2, heightPoints: Double) -> Vector2` returning `Vector2(x: position.x, y: heightPoints - position.y)`. Doc comments: the two spaces (the Mac reports positions from the surface's bottom-left corner, +y up; 008's order request takes view space, top-left, +y down, 005 FR-004); why the flip is here rather than by flipping the view (R3); why `bounds.height` is the right height (the surface is reported synchronously from `setFrameSize`, so it matches what the loop converts against, R3); that it is pure and passes any value through for `MoveOrderRequest.apply` to judge (FR-004, FR-008)

**Checkpoint**: `swift build` passes with no warnings.

---

## Phase 3: User Story 1 - Click to send the ship (Priority: P1) 🎯 MVP

**Goal**: A primary click anywhere in the Mac window sends the ship there.

**Independent Test**: `./Scripts/verify.sh` runs C1, C4 and C5; quickstart checks 3, 4, 6 and 7.

### Tests for User Story 1

- [X] T002 [P] [US1] Create `Tests/SwiftSkyPlatformTests/ClickPositionTests.swift` with `@Suite("Click position")` and tests for: C1 (on a 1,280 × 800 pt surface, the bottom-left, top-left, top-right and bottom-right corners and the centre flip to (0, 800), (0, 0), (1,280, 0), (1,280, 800) and (640, 400)); C4 (a click at y = 700 orders the ship to positive world y, and one at y = 100 to negative, through `MoveOrderRequest.apply` at 2×); C5 (`(100.25, 50.5)` on h = 800 gives exactly `(100.25, 749.5)`)

### Implementation for User Story 1

- [X] T003 [US1] Change `Sources/SwiftSkyPlatform/MetalSurfaceView.swift`, macOS only (`#if os(macOS)`): in `configure(device:)` call a new `registerForClicks()` (macOS) that adds an `NSClickGestureRecognizer(target: self, action: #selector(clicked(_:)))` with `buttonMask = 0x1` and `numberOfClicksRequired = 1`; `@objc private func clicked(_ recognizer: NSClickGestureRecognizer)` returns when `NSEvent.modifierFlags.contains(.control)`, else computes `let p = recognizer.location(in: self)` and posts `onSurfaceChange?(.moveOrderRequested(MoveOrderRequest(viewPoint: ClickPosition.viewPoint(fromBottomLeft: Vector2(x: Double(p.x), y: Double(p.y)), heightPoints: Double(bounds.height)))))`. Add `override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }` with a comment (the first click on an inactive window only activates it, clarification, FR-003, R2). Doc comments: primary button only, Control-click is a secondary click by convention and AppKit delivers it as a primary event (R1, clarification); the recogniser fails on drags and takes trackpad tap to click (FR-001); each click is one order, so a double-click is two (FR-002); it does not touch size, scale or occlusion reporting (FR-005). Widen `onSurfaceChange`'s doc comment to mention clicks on macOS. In `configure(device:)`, call `registerForClicks()` inside a new `#if os(macOS)` block beside the existing `#if os(iOS)` block that calls `registerForScaleChanges()` and `registerForTaps()`. Depends on T001
- [X] T004 (checks 3, 4, 6, 7 not run: no event-posting access; see Evidence) [US1] Run `./Scripts/verify.sh`, then quickstart checks 3, 4, 6 and 7 on the Mac and record them in the Evidence section of `specs/009-click-to-order-macos/quickstart.md`. Depends on T002, T003

**Checkpoint**: Clicking sends the ship on the Mac. MVP complete.

---

## Phase 4: User Story 2 - A new click changes the plan (Priority: P2)

**Goal**: A click mid-flight replaces the order.

**Independent Test**: quickstart check 5. The replacement itself is 008's, tested there (008 C8).

### Implementation for User Story 2

- [X] T005 (check 5 not run: no event-posting access) [US2] No code: replacement is 008's `MoveOrderRequest.apply` (008 `replacesMidFlight`, `lastOfTwoWins`). Run quickstart check 5 on the Mac and record it in the Evidence section of `specs/009-click-to-order-macos/quickstart.md`

**Checkpoint**: Re-ordering mid-flight works on the Mac.

---

## Phase 5: User Story 3 - Any window size, full screen and any display (Priority: P3)

**Goal**: The flip and conversion are right at every window size and scale.

**Independent Test**: `./Scripts/verify.sh` runs C2 and C3; quickstart check 8.

### Tests for User Story 3

- [X] T006 [US3] Add to `Tests/SwiftSkyPlatformTests/ClickPositionTests.swift`, parameterised with `@Test(arguments:)`: C2 (on 1,280 × 800, 800 × 1,280, 1,001 × 667 and 1,512 × 982 point surfaces at 1× and 2×, the four corners and the centre flipped through `ClickPosition` then applied through `MoveOrderRequest.apply` give (−w/2, −h/2), (−w/2, h/2), (w/2, h/2), (w/2, −h/2) and (0, 0) within 1e-9); C3 (one click on the same size in points gives the identical destination at 1× and 2×)

### Implementation for User Story 3

- [X] T007 (check 8 not run: no event-posting access) [US3] No code: the height is the view's own, reported synchronously with the surface (R3). Run quickstart check 8 (five window sizes, one taller than wide; full screen; a Retina/non-Retina move if a second display is available) and record it in the Evidence section of `specs/009-click-to-order-macos/quickstart.md`

**Checkpoint**: Every window size is covered by tests and checked on the Mac.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T008 [P] Update `CLAUDE.md`: add `specs/009-click-to-order-macos` to "Built so far" (a click on macOS orders the ship, through 008's request), and to "Key locations" `ClickPosition.swift` (the bottom-left → top-left flip, pure) and the macOS click recogniser in `MetalSurfaceView.swift` (primary button, Control-click ignored, `acceptsFirstMouse` false)
- [ ] T009 [P] Update `.tickets/11.yaml` `status` to `done`
- [ ] T010 Run quickstart check 2 (shared code untouched), check 9 (Profiling builds of `main` and this branch on the same Mac, window frontmost, 30 s each, summaries and Allocations side by side, Principle III) and check 10 (VoiceOver description unchanged); record them in the Evidence section
- [ ] T011 Run `./Scripts/verify.sh` and fill in the rest of the Evidence section of `specs/009-click-to-order-macos/quickstart.md`, marking any check not run with its reason

---

## Dependencies & Execution Order

- **Foundational (Phase 2)**: T001. Blocks every story.
- **US1 (Phase 3)**: T002 ∥ T003 after T001; T004 last. MVP.
- **US2 (Phase 4)**: after US1 (needs the recogniser).
- **US3 (Phase 5)**: T006 after T001; T007 after US1.
- **Polish (Phase 6)**: after all stories.

### Parallel Opportunities

- T002 ∥ T003; T008 ∥ T009.
- T002 and T006 share one file.

### Parallel Example: User Story 1

```text
Task: "T002 Create ClickPositionTests.swift (C1, C4, C5)"
Task: "T003 Add the macOS click recogniser to MetalSurfaceView.swift"
```

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 2: the build passes.
2. Phase 3: clicks send the ship. **Stop and validate**: checks 3 and 4.

### Incremental Delivery

US2 → US3 → Polish. Each phase ends green and is committed on its own.
