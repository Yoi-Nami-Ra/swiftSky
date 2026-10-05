# Tasks: Draw the Order Overlay

**Input**: Design documents from `/specs/014-order-overlay/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/order-overlay.md, quickstart.md

**Tests**: requested by the spec (FR-017): the pure rules get headless Swift Testing tests. The Metal
drawing is render code and exempt (Principle II); it is checked by the quickstart.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an unfinished task)
- **[Story]**: US1, US2, US3 from spec.md

## Phase 1: Setup

- [ ] T001 Confirm the baseline: run `./Scripts/verify.sh` on `014-order-overlay` before any change and note the test count

## Phase 2: Foundational (blocking prerequisites)

**Purpose**: the point-tick rule and the `poseTick` plumbing every story needs.

- [ ] T002 [P] Add `PlannedPath.tick(ofPoint:)` per contract C1 (`startTick + index × spacing`, `endTick` for the last point, precondition `0..<count`) in Sources/SwiftSkySimulation/PlannedPath.swift
- [ ] T003 [P] Add tests for C1 in Tests/SwiftSkySimulationTests/PlannedPathTests.swift: a one-point path, a short path (spacing 1), a thinned path (spacing 2+) whose last point is off the grid, a capped path, and strictly increasing ticks
- [ ] T004 Add the `poseTick: UInt64` parameter to `Renderer.render(state:shipPose:poseTick:surface:drawable:timestamp:)` (contract C3; unused until T009) in Sources/SwiftSkyRendering/Renderer.swift, and compute it in Sources/SwiftSkyPlatform/FrameLoop.swift beside the drawn pose from the same `interpolates` flag: `tickCount − 1` (0 at tick 0) when interpolating, `tickCount` otherwise (contract C4)

**Checkpoint**: `verify.sh` passes; the app draws exactly as before.

## Phase 3: User Story 1 — The player sees where the ship is going (Priority: P1) 🎯 MVP

**Goal**: marker, ring and remaining path drawn while an order is flown, gone on arrival, on both platforms.

**Independent Test**: quickstart checks 2, 3, 5, 6 and 7 on the iOS simulator and on macOS.

- [ ] T005 [US1] Create `OrderOverlayStyle` (research R7: marker radius 7 pt and stroke 2 pt, highlight radius 28 pt and stroke 1.5 pt, line width 1.5 pt, colour sRGB (0.35, 0.95, 0.80) at 85 % as linear premultiplied, converted once) and `OrderOverlay` with `init?(state:shipPose:poseTick:surface:)` per data-model.md and contract C2 (`InlineArray<258, Vector2>` line points, marker centre, highlight centre from `ShipSpritePlacement.centrePixels`, scale, surface size; `while` loops, no allocation) in Sources/SwiftSkyRendering/OrderOverlay.swift
- [ ] T006 [P] [US1] Add the overlay shaders per contract C5 to Sources/SwiftSkyRendering/Shaders.metal: `OverlayUniforms` and `OverlayRing` records, `swiftsky_overlay_line_vertex` (instance `i` = segment `points[i] → points[i+1]`, quad grown by half width + 1 px, pixel → clip), `swiftsky_overlay_ring_vertex` (square of half side radius + half width + 1 px), and `swiftsky_overlay_fragment` (distance to segment, coverage `clamp(halfWidth + 0.5 − |d − radius|, 0, 1)`, colour × coverage)
- [ ] T007 [US1] Create `OrderOverlayPipelines` in Sources/SwiftSkyRendering/OrderOverlayPipelines.swift: two `MTLRenderPipelineState`s (line, ring) sharing the fragment function, blending `max` with factors `one`/`one` (research R5), built once, throwing `RendererError.shaderFunctionMissing` / `.pipelineStateCreationFailed` like `ShipSprite`
- [ ] T008 [US1] Build the pipelines in `Renderer.init` (a failure is a `RendererError`, as for the ship) in Sources/SwiftSkyRendering/Renderer.swift
- [ ] T009 [US1] Add `encodeOrderOverlay(state:shipPose:poseTick:surface:encoder:)` to Sources/SwiftSkyRendering/Renderer.swift and call it after the background quad and before `encodeShip` (FR-009): build `OrderOverlay`, copy its points into a stack `InlineArray<258, SIMD2<Float>>`, set the uniforms, the points (`8 × lineCount` bytes) and the two ring records with `setVertexBytes`, draw `lineCount − 1` line instances and 2 ring instances as 4-vertex triangle strips; not gated by `drawsShip` or `SWIFTSKY_INSTRUMENTATION` (FR-003)
- [ ] T010 [US1] Run quickstart checks 2, 3, 5, 6 and 7 on the iPhone 17 Pro simulator (tap, `simctl io screenshot`, log stream) and record the results in specs/014-order-overlay/quickstart.md
- [ ] T011 [US1] Run quickstart checks 2, 3, 5, 6 and 7 on macOS (clicks by hand) and record the results in specs/014-order-overlay/quickstart.md

**Checkpoint**: the overlay is visible and correct on both platforms (SC-001 to SC-004 by eye).

## Phase 4: User Story 2 — The overlay geometry is tested (Priority: P2)

**Goal**: the rules behind the picture are pinned by headless tests (FR-017).

**Independent Test**: `./Scripts/verify.sh`; the new suite runs without a Metal device.

- [ ] T012 [P] [US2] Create Tests/SwiftSkyRenderingTests/OrderOverlayTests.swift covering contract C2: `nil` with no order, when arrived, and with no camera (zero-area surface); marker centre equals the destination's view × scale exactly; highlight centre equals `ShipSpritePlacement.centrePixels`; first line point is the drawn ship position; last point equals the marker centre, both when the path reaches arrival and when it is capped
- [ ] T013 [P] [US2] Add reached-point tests to Tests/SwiftSkyRenderingTests/OrderOverlayTests.swift: at `poseTick` before the start every path point is drawn; partway, exactly the points with tick > `poseTick`, in order; past the last point only ship and destination remain; a new order (state rebuilt) gives the new destination
- [ ] T014 [US2] Add the full-capacity case to Tests/SwiftSkyRenderingTests/OrderOverlayTests.swift: an order long enough to fill all 256 path points gives 258 line points at `poseTick` before the start. (Allocations are measured by 011 check 25 in T015/T016: the counter is linked only into the platform tests.)

**Checkpoint**: `verify.sh` passes with the new tests.

## Phase 5: User Story 3 — The overlay costs nothing per frame (Priority: P3)

**Goal**: zero heap allocations per frame and frame times within budget with orders flown (SC-005).

**Independent Test**: 011 check 25 with orders flown for 60 s on each platform.

- [ ] T015 [US3] Run 011's check 25 on the iOS simulator with the optimised instrumented build, flying orders for 60 s, and record `allocs=` from the frame summaries in specs/014-order-overlay/quickstart.md
- [ ] T016 [US3] Run 011's check 25 on macOS the same way (orders by hand) and record the result in specs/014-order-overlay/quickstart.md

## Phase 6: Polish & cross-cutting

- [ ] T017 [P] Run the remaining quickstart checks 4 and 8–11 (marker within half a pixel, off-screen and capped orders, resize/rotation, Release build, `--no-interpolation`) and record them in specs/014-order-overlay/quickstart.md
- [ ] T018 [P] Update CLAUDE.md: add spec 014 to the "Built so far" list and a key-locations entry for `OrderOverlay.swift` / `OrderOverlayPipelines.swift` (the `poseTick` rule, `max` blending over black only, the style constants)
- [ ] T019 Run `./Scripts/verify.sh` and confirm all suites pass and both apps build with no warnings (quickstart check 1)

## Dependencies & Execution Order

- **Setup (T001)** → **Foundational (T002–T004)** → user stories.
- **US1** (T005–T011): T005 needs T002; T006 is independent of T005; T007 needs T006; T008 needs T007;
  T009 needs T004, T005 and T008; T010 and T011 need T009.
- **US2** (T012–T014): needs T005 only, so it can run alongside T006–T009.
- **US3** (T015–T016): needs T009.
- **Polish**: T017 needs T009; T018 any time after T009; T019 last.

## Parallel Example

```text
After T004:  T005 (OrderOverlay.swift)  ∥  T006 (Shaders.metal)
After T005:  T012, T013 (OrderOverlayTests.swift)  ∥  T007–T009 (pipelines and encoding)
```

## Implementation Strategy

1. **MVP**: Phases 1–3 — the overlay drawn and checked on both platforms.
2. Pin it with US2's tests (written alongside T005 where convenient: test-first is recommended, not
   mandated).
3. Prove the cost with US3, then polish and run the full verification.

Commit at the end of each phase.
