---

description: "Task list for 005-game-space-camera"
---

# Tasks: Game Space and Camera

**Input**: Design documents from `/specs/005-game-space-camera/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/camera.md, quickstart.md

**Tests**: Required. FR-014 and the ticket's "done when" call for headless unit tests of the camera,
and constitution Principle II requires tests for non-trivial logic. There is no drawing code in this
feature.

**Organization**: tasks are grouped by user story, so that each story can be implemented and
validated on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US4)
- Paths are relative to the repository root. `R<n>` refers to research.md, `C<n>` to
  contracts/camera.md and `check <n>` to quickstart.md.

## Path Conventions

- The camera is `Sources/SwiftSkyRendering/Camera.swift`, the ship length
  `Sources/SwiftSkyRendering/GameSpace.swift`, the tests `Tests/SwiftSkyRenderingTests/CameraTests.swift`.
  Nothing in `Sources/SwiftSkyPlatform/`, `Renderer.swift` or `Shaders.metal` changes (R6).
- Every mapping takes and returns `Vector2` from `SwiftSkySimulation` (R2). Test files that name
  `Vector2` add `import SwiftSkySimulation` beside `@testable import SwiftSkyRendering`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: let the rendering tests name `Vector2` under `verify.sh`'s explicit import check (R8).

- [X] T001 In `Package.swift`, add `"SwiftSkySimulation"` to the `SwiftSkyRenderingTests` test target's `dependencies`, and rewrite its comment's "Depends on SwiftSkyRendering ONLY" sentence to say it depends on the rendering layer and the logic layer: the logic layer is GPU-free, so the target stays headless; it is declared so camera tests can name `Vector2` under `--explicit-target-dependency-import-check=error` (005 research R8)

**Checkpoint**: `swift build --build-system swiftbuild --build-tests` succeeds; all existing tests pass.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the `Camera` type, its validation and the ship length (data-model.md, C1–C3).

**⚠️ CRITICAL**: no user story work can begin until this phase is complete.

- [X] T002 Create `Sources/SwiftSkyRendering/Camera.swift`: `public struct Camera: Sendable, Equatable` with `public let halfWidth: Double` and `public let halfHeight: Double` (points), computed `public var widthPoints` / `heightPoints` (`2 * half…`), and `public init?(surface: RenderSurface)` that returns `nil` unless `surface.isRenderable` and `surface.backingScale.isFinite && surface.backingScale > 0`, then sets `halfWidth = Double(surface.widthPixels) / surface.backingScale / 2` (likewise height) — division, never a reciprocal (R3, R4). `safeAreaInsets` is not read (FR-003). *(Extended in code review: it also returns `nil` when either computed half-extent is not a normal number, so an extreme finite scale that overflows to ∞ or underflows to a subnormal gives no camera — contract C2a.)* No import beyond `SwiftSkySimulation` (for `Vector2`). Type doc comment: one unit = one point, the fixed camera with the origin at the centre of the whole surface, the three spaces and their axes (data-model.md table), "no camera" for a zero-area surface (001 FR-027a, 005 FR-008), and that it is a plain value rebuilt when the surface changes, never updated in place and never allocating (FR-007)
- [X] T003 [P] Create `Sources/SwiftSkyRendering/GameSpace.swift`: caseless `public enum GameSpace` with `public static let shipLength: Double = 40` (world units, FR-009). Doc comments record: 1 world unit = 1 point, so the 80 × 80 px sprite draws at 40 × 40 pt, pixel-exact on 2× displays; the world is unbounded (no edges, wrapping or collisions, FR-002); and the note for SKY-27 — the sprite's top edge is the ship's front, so it is drawn rotated by `heading − π/2`, i.e. −90° (a quarter turn clockwise) at heading zero (FR-010, R7). Shared by SKY-27 and SKY-30's ship highlight
- [X] T004 Create `Tests/SwiftSkyRenderingTests/CameraTests.swift` with `@Suite("Camera") struct CameraTests`, a file-private helper `func surface(widthPoints: Double, heightPoints: Double, scale: Double = 2, insets: SurfaceInsets = .zero) -> RenderSurface` that builds pixel counts as `UInt32(widthPoints * scale)`, and tests for C1–C3: `nil` for width 0, height 0, both 0, and for backing scales `0`, `-2`, `.nan`, `.infinity` (extended in code review with `-0.0`, `-.infinity`, and extreme scales overflowing or underflowing each half-extent on its own — C2a) — these built directly as `RenderSurface(widthPixels: 2560, heightPixels: 1440, backingScale: …)`, never through the helper, whose `UInt32(…)` conversion traps on a non-finite product; a 2560 × 1440 px surface at 2× gives `halfWidth == 640`, `halfHeight == 360`, `widthPoints == 1280`, `heightPoints == 720`; a fractional point size, 1,001 × 667 px at 2×, gives exactly `halfWidth == 250.25` and `halfHeight == 166.75`, unrounded (spec Edge Cases, FR-004); and `GameSpace.shipLength == 40` (check 6, 7). Depends on T001, T002, T003

**Checkpoint**: `swift test --build-system swiftbuild --filter Camera` passes.

---

## Phase 3: User Story 1 - Place a world point on screen (Priority: P1) 🎯 MVP

**Goal**: world → view points and world → clip (FR-004, C6–C8, C10).

**Independent Test**: `swift test --build-system swiftbuild --filter Camera` — the mapping tests
compare mapped points against the centre, corners and edges of known surfaces (check 3).

### Tests for User Story 1

- [X] T005 [US1] In `Tests/SwiftSkyRenderingTests/CameraTests.swift`, add a parameterised test over 1920 × 1080, 1,001 × 667 and portrait 768 × 1024 point surfaces: `view(fromWorld: .zero)` is exactly `(w/2, h/2)`; `(−w/2, +h/2)` → `(0, 0)`, `(+w/2, +h/2)` → `(w, 0)`, `(−w/2, −h/2)` → `(0, h)`, `(+w/2, −h/2)` → `(w, h)` exactly; `clip(fromWorld: .zero)` is `(0, 0)` and the four corners are exactly `(±1, ±1)` with +1 at the top and right (SC-001, US1-1…3)
- [X] T006 [US1] In the same file, add: on a 1920 × 1080 pt surface, moving the world point `(37, −12)` to `(38, −12)` moves its view position by exactly +1 in x, and to `(37, −11)` by exactly −1 in view y (one unit = one point, +y up; US1-4; whole numbers, so every sum is exact); the world points `(±1e6, ±1e6)`, beyond the surface, map to view positions outside it and to clip values beyond ±1, all finite (C10); a `.nan` or `.infinity` world component yields a non-finite result on that axis (C11)

### Implementation for User Story 1

- [X] T007 [US1] In `Sources/SwiftSkyRendering/Camera.swift`, add `public func view(fromWorld world: Vector2) -> Vector2` returning `Vector2(x: halfWidth + world.x, y: halfHeight - world.y)` and `public func clip(fromWorld world: Vector2) -> Vector2` returning `Vector2(x: world.x / halfWidth, y: world.y / halfHeight)`, each doc-commented with its formula in spec terms (w/2 + x, h/2 − y; x ÷ (w/2), y ÷ (h/2)), the result's space and axes, and — for clip — why it divides rather than multiplies (R4). No clamping (FR-002). Depends on T002

**Checkpoint**: US1 tests pass; SKY-27 has everything it needs to place the ship.

---

## Phase 4: User Story 2 - Turn a screen position into a world point (Priority: P2)

**Goal**: view points → world, the inverse of US1 (FR-004, FR-005, C9).

**Independent Test**: `swift test --build-system swiftbuild --filter Camera` — known positions map
to known world points, and 1,000 positions round-trip (check 4).

### Tests for User Story 2

- [X] T008 [US2] In `Tests/SwiftSkyRenderingTests/CameraTests.swift`, add: on a 1,001 × 667 pt surface `world(fromView: (500.5, 333.5))` is exactly `.zero`, `(0, 0)` gives `(−500.5, +333.5)` and `(1001, 667)` gives `(+500.5, −333.5)` (US2-1, US2-2); and a round-trip test over a fixed 40 × 25 grid (1,000 positions) spanning −1× to +2× the surface in each axis, asserting `abs(view(fromWorld: world(fromView: v)) − v) <= 1e-9` per axis (SC-002, US2-3, US2-4, R5)

### Implementation for User Story 2

- [X] T009 [US2] In `Sources/SwiftSkyRendering/Camera.swift`, add `public func world(fromView view: Vector2) -> Vector2` returning `Vector2(x: view.x - halfWidth, y: halfHeight - view.y)`, doc-commented: the inverse of `view(fromWorld:)` within 1e-9 points (FR-005), positions off the surface are legal and give the world point that would be there (FR-002), and that SKY-10 and SKY-11 turn taps and clicks into world points with it. Depends on T007

**Checkpoint**: US1 and US2 tests pass.

---

## Phase 5: User Story 3 - The same world on every display and window size (Priority: P3)

**Goal**: backing-scale independence, resize to the new centre, insets ignored (FR-003, FR-006,
FR-007, C4, C5).

**Independent Test**: `swift test --build-system swiftbuild --filter Camera` (check 5).

### Tests for User Story 3

- [X] T010 [US3] In `Tests/SwiftSkyRenderingTests/CameraTests.swift`, add: cameras for 1,001 × 667 pt at scales 1, 2 and 3 are `==`, and map the world points `.zero`, `(123.25, −45.5)` and `(−500.5, 333.5)` to identical view and clip values (SC-003, US3-1, C5); a camera for 1280 × 720 pt then one for 1,001 × 667 pt maps `.zero` to `(640, 360)` then exactly `(500.5, 333.5)` (SC-004, US3-2); a surface with `SurfaceInsets(top: 59, left: 0, bottom: 34, right: 0)` and the same surface with `.zero` insets give `==` cameras (US3-3, C4). No implementation task: these pass on T002, T007 and T009 — if one fails, fix `Camera.swift`, not the test

**Checkpoint**: all camera tests pass (checks 3–7).

---

## Phase 6: User Story 4 - The running app is unchanged (Priority: P4)

**Goal**: nothing visible changes and nothing on the frame path is touched (FR-013, SC-006).

**Independent Test**: `./Scripts/verify.sh`, and launching the app (check 11).

- [X] T011 [US4] Confirm `git diff main -- Sources/SwiftSkyPlatform Sources/SwiftSkyRendering/Renderer.swift Sources/SwiftSkyRendering/Shaders.metal` is empty, and that nothing outside the tests constructs a `Camera` (`grep -rn "Camera(" Sources/`) (check 9, R6)

**Checkpoint**: the draw and frame paths are byte-identical to `main`.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T012 [P] In `Sources/SwiftSkySimulation/Ship.swift`, replace `ShipLimits.default`'s "Provisional. Retune once SKY-23 fixes what a world unit is on screen." with a line saying one world unit is one point (005 FR-001), so the defaults read as 200 pt/s², 180 °/s and 360 °/s², and were kept as they are (005 FR-012). No value changes (check 10, R9)
- [X] T013 [P] Update `CLAUDE.md`: add `specs/005-game-space-camera` to the "Built so far" paragraph (one world unit = one point, unbounded world, fixed camera centred on the whole surface), and add `Sources/SwiftSkyRendering/Camera.swift` and `GameSpace.swift` to Key locations (world → view, view → world, world → clip; `GameSpace.shipLength`; `nil` for a zero-area surface)
- [X] T014 Run `./Scripts/verify.sh`, then `swift test --build-system swiftbuild` 10 times in a row, and record checks 1, 2, 3–7 and 8–10 in `specs/005-game-space-camera/quickstart.md`'s Evidence table (check 8: read `Camera.swift` for reference or growable storage). Depends on T001–T013
- [X] T015 Record check 11 in `specs/005-game-space-camera/quickstart.md`: launch Debug, Debug with `--no-debug-overlay`, and Release on both platforms if a session allows; otherwise record it as not run with the structural evidence from T011. Depends on T014
- [X] T016 Mark `.tickets/23.yaml` `status: done`. Depends on T014

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001)** → **Foundational (T002–T004)** → **US1 (T005–T007)** → **US2 (T008–T009)** →
  **US3 (T010)** → **US4 (T011)** → **Polish (T012–T016)**.
- US2 depends on US1 only through the round trip (it uses `view(fromWorld:)`); US3's tests use all
  three mappings. US4 and T012–T013 depend on nothing and may run at any point.

### Within each story

- Tests and implementation live in two files; write the test first where convenient (Principle II
  recommends, does not mandate). All test tasks touch `CameraTests.swift`, so they are sequential.

### Parallel opportunities

- T003 alongside T002 (different files).
- T012 and T013 alongside any phase (different files, no dependency).
- T011 at any time.

## Parallel Example

```text
# Foundational
Task: "T002 Create Sources/SwiftSkyRendering/Camera.swift"
Task: "T003 Create Sources/SwiftSkyRendering/GameSpace.swift"

# Anytime
Task: "T012 Update ShipLimits.default doc comment in Sources/SwiftSkySimulation/Ship.swift"
Task: "T013 Update CLAUDE.md"
```

## Implementation Strategy

### MVP first (User Story 1)

1. T001 → T002–T004 → T005–T007.
2. **Stop and validate**: `swift test --filter Camera`. SKY-27 is unblocked.

### Incremental delivery

1. + US2 (T008–T009): SKY-10 and SKY-11 are unblocked.
2. + US3 (T010): the scale, resize and inset guarantees are locked in.
3. + US4 and Polish: the app is proven unchanged, docs and the ticket updated.
