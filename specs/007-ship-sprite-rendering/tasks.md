---

description: "Task list for 007-ship-sprite-rendering"
---

# Tasks: Ship Sprite Rendering

**Input**: Design documents from `/specs/007-ship-sprite-rendering/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/ship-sprite.md, quickstart.md

**Tests**: Required. FR-017 calls for headless tests of the placement, and constitution Principle II
requires tests for non-trivial logic: placement maths, image decoding, the error mapping and argument
parsing. The draw itself is visual (exempt) and is checked through quickstart.md.

**Organization**: Tasks are grouped by user story, so each story can be implemented and validated on
its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US4)
- Paths are relative to the repository root. `R<n>` refers to research.md, `C<n>` to the guarantees
  in contracts/ship-sprite.md, and `check <n>` to quickstart.md.

## Path Conventions

- Rendering layer: `Sources/SwiftSkyRendering/`, tests in `Tests/SwiftSkyRenderingTests/`
  (`@testable import SwiftSkyRendering`, as `TestSupport.swift` does). Platform layer:
  `Sources/SwiftSkyPlatform/`, tests in `Tests/SwiftSkyPlatformTests/`.
- No test may call `MTLCreateSystemDefaultDevice`, `.makeCommandQueue(`, `.makeBuffer(` or
  `.makeTexture(`: `verify.sh`'s headless guard fails the run.
- Run the tests with `swift test --build-system swiftbuild --explicit-target-dependency-import-check=error`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Ship the image with the rendering layer and guard it against drift (R1).

- [X] T001 Copy `design/sprites/ship.png` byte for byte to `Sources/SwiftSkyRendering/Resources/ship.png` (`cp`, then `cmp` to confirm)
- [X] T002 Change `Package.swift`: add `resources: [.copy("Resources/ship.png")]` to the `SwiftSkyRendering` target, with a comment giving the reason for `.copy` rather than `.process` (processing may re-encode the PNG, research R1) and naming the `verify.sh` identity check. Update the rendering test target's comment to mention the ship placement and image tests. Depends on T001
- [X] T003 [P] Change `Scripts/verify.sh`: add a stage before the builds, `section "Ship image matches the design file"`, run through `run_stage` with a function that runs `cmp -s design/sprites/ship.png Sources/SwiftSkyRendering/Resources/ship.png`, commented with FR-002, SC-008a and the fix (copy the design file over the bundled one)

**Checkpoint**: `./Scripts/verify.sh` passes, with the new stage green. Nothing is drawn yet.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The error case, the CPU image and the pure placement that every story uses.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [ ] T004 [P] Change `Sources/SwiftSkyRendering/RendererError.swift`: add `case shipImageUnavailable(reason: String)`, with a doc comment covering missing, undecodable, wrong size, and texture or mip failure (FR-005, R7). Its `userFacingDescription` is "swiftSky could not load the ship image (\(reason)). The installation may be incomplete." and its `diagnosticCode` is `"ship_image_unavailable"`
- [ ] T005 [P] Create `Sources/SwiftSkyRendering/ShipImageBitmap.swift` (imports `CoreGraphics`, `Foundation`, `ImageIO`): `enum ShipImageError: Error, Equatable, Sendable { case missing, undecodable, wrongSize(width: Int, height: Int) }` and `struct ShipImageBitmap: Sendable` with `static let sizePixels = 80`, `static var bundledURL: URL? { Bundle.module.url(forResource: "ship", withExtension: "png") }`, `let widthPixels, heightPixels: Int`, `let bytes: [UInt8]`. `init(contentsOf url: URL) throws(ShipImageError)`: `missing` if there is no file at the URL (`FileManager.default.fileExists`); `undecodable` if `CGImageSourceCreateWithURL` or `CGImageSourceCreateImageAtIndex(_, 0, nil)` fails; `wrongSize` unless 80 × 80; else draw into a `CGContext` (80 × 80, 8 bits per component, 320 bytes per row, `CGColorSpace(name: CGColorSpace.sRGB)`, `CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue`) over a zero-filled `[UInt8]` of 25,600, with no interpolation needed (same size). Doc comments: layout (RGBA, row-major, top row first, premultiplied, sRGB-encoded), why the CPU side is separate (headless tests, as `GlyphAtlasBitmap`), and that it runs once at init (FR-003, R2, R3)
- [ ] T006 [P] Create `Sources/SwiftSkyRendering/ShipSpritePlacement.swift` (imports `Foundation` for `cos`/`sin`, and `SwiftSkySimulation`): `struct ShipSpritePlacement: Sendable, Equatable` implementing the contract exactly. `init?(position: Vector2, heading: Double, surface: RenderSurface)`: `guard let camera = Camera(surface:)`; `s = surface.backingScale`; `v = camera.view(fromWorld: position)`; `centrePixels = Vector2(x: (v.x * s).rounded(), y: (v.y * s).rounded())`; `k = GameSpace.shipLength / 2 * s`; `f = (cos h, −sin h)`, `r = (sin h, cos h)`; the four corners as in R6. Store `centrePixels`, the four corners, and `widthPixels`/`heightPixels` as `Double`. `func clip(_ p: Vector2) -> Vector2` gives `(p.x / W * 2 − 1, 1 − p.y / H * 2)`; `var clipCorners: (Vector2, Vector2, Vector2, Vector2)` returns bottom-left, bottom-right, top-left, top-right. Doc comments: the rotation derivation (heading − π/2 in world space, y flipped once for pixels, the `GameSpace` trap), snapping (FR-006a), and no allocation (FR-011)

**Checkpoint**: `swift build` passes with no warnings.

---

## Phase 3: User Story 1 - See the ship at launch (Priority: P1) 🎯 MVP

**Goal**: The ship is drawn at the centre, facing right, 40 × 40 pt, cleanly blended, under the overlay.

**Independent Test**: `swift test --filter ShipImageBitmap` and `--filter ShipSpritePlacement`; then
quickstart checks 8–10 on both platforms.

### Tests for User Story 1

- [ ] T007 [P] [US1] Create `Tests/SwiftSkyRenderingTests/ShipImageBitmapTests.swift` (`@Suite("ShipImageBitmap")`): C11 (the bundled URL exists; it decodes to 80 × 80 with 25,600 bytes) and C12 (every colour byte ≤ its alpha byte; at least one pixel has alpha 0 and at least one has alpha 255)
- [ ] T008 [P] [US1] Create `Tests/SwiftSkyRenderingTests/ShipSpritePlacementTests.swift` (`@Suite("ShipSpritePlacement")`) with a file-private helper `surface(widthPoints:heightPoints:scale:)` and a corner-comparison helper with a tolerance. Tests for this story: C1 (`nil` for zero-width, zero-height and non-finite-scale surfaces, and non-`nil` otherwise); C2 (heading 0: `topLeft.x == topRight.x == c.x + k`, and the top edge runs +y in pixels); a ship at the origin on a 1280 × 720-point 2× surface has `centrePixels == (1280, 720)` and corners at (1240…1320, 680…760); C5 (the centre is whole, within half a pixel of `v·s`, and the mean of the corners)

### Implementation for User Story 1

- [ ] T009 [US1] Change `Sources/SwiftSkyRendering/Shaders.metal`: add a `// MARK: - Ship sprite (007-ship-sprite-rendering)` section with `swiftsky::SpriteRasterizerData { float4 position [[position]]; float2 uv; }`, `vertex swiftsky_sprite_vertex(uint vid [[vertex_id]], constant float2 *corners [[buffer(0)]])` (position `float4(corners[vid], 0, 1)`, uv `float2(vid & 1, 1 - (vid >> 1))`) and `fragment float4 swiftsky_sprite_fragment(SpriteRasterizerData in [[stage_in]], texture2d<float> image [[texture(0)]])`, sampling with `constexpr sampler(filter::linear, mip_filter::linear, address::clamp_to_zero)` and returning the premultiplied sample as-is. Comment on why no maths happens here (R5), sRGB decode and blending (R3), and filtering (R4). Rewrite the file header: the quad is the black background, and the ship and text draw over it (FR-009)
- [ ] T010 [US1] Create `Sources/SwiftSkyRendering/ShipSprite.swift` (`import Metal`): `struct ShipSprite` with `let pipelineState: any MTLRenderPipelineState`, `let texture: any MTLTexture`, and `static let vertexCount = 4`. `init(device:library:pixelFormat:commandQueue:image: ShipImageBitmap) throws(RendererError)`: missing functions → `.shaderFunctionMissing`; the pipeline with `isBlendingEnabled = true`, rgb and alpha `sourceBlendFactor = .one`, `destinationBlendFactor = .oneMinusSourceAlpha`, label `swiftSky.shipSprite` → failure `.pipelineStateCreationFailed`; a texture descriptor `.rgba8Unorm_srgb`, 80 × 80, `mipmapped: true`, `.shaderRead`, default storage, via `device.makeTexture` → `nil` gives `.shipImageUnavailable(reason: "texture could not be created")`; `replace(region:mipmapLevel: 0, withBytes:bytesPerRow: 320)`; then one command buffer with a blit encoder `generateMipmaps(for:)`, `commit()`, `waitUntilCompleted()`, and a failed buffer or encoder, or `status == .error`, gives `.shipImageUnavailable(reason: "mipmaps could not be generated")`. Doc comment: built once and reused (FR-011, R4)
- [ ] T011 [US1] Change `Sources/SwiftSkyRendering/Renderer.swift`: add `private let ship: ShipSprite`. In `init`, after the quad: `guard let url = ShipImageBitmap.bundledURL` else throw `.shipImageUnavailable(reason: "ship.png is missing from the app")`; decode with `ShipImageBitmap(contentsOf:)`, mapping `ShipImageError` to `.shipImageUnavailable(reason:)` (missing / not a readable image / wrong size W×H, 80×80 expected); then `ShipSprite(…, commandQueue: queue, image:)`. Add `#if SWIFTSKY_INSTRUMENTATION public var drawsShip = true #endif`, with a doc comment (`--no-ship`, FR-014). In `render`, between the quad and the text: build `ShipSpritePlacement(position: state.ship.position, heading: state.ship.heading, surface: surface)`; if it exists (and `drawsShip` in Debug), `setRenderPipelineState`, copy `clipCorners` into a local tuple of four `SIMD2<Float>`, `withUnsafeBytes` → `setVertexBytes(_, length: 32, index: 0)`, `setFragmentTexture(ship.texture, index: 0)`, and `drawPrimitives(.triangleStrip, 0, 4)`. Update the class and `render` doc comments: the renderer now draws the ship from the state (FR-001, FR-009, 001 FR-002 superseded) and nothing here allocates (FR-011)
- [ ] T012 [US1] Run `./Scripts/verify.sh` (both app targets must build), then launch the macOS Debug build, with no argument and with `--no-debug-overlay`, and screenshot it: quickstart checks 8 and 10 (centred, facing right, 80 × 80 px at 2×, no fringe, overlay text on top where they overlap). Record the results in quickstart.md's Evidence section

**Checkpoint**: The ship is visible at the centre on macOS. MVP.

---

## Phase 4: User Story 2 - The ship turns the way the simulation says (Priority: P2)

**Goal**: Rotation is correct and undistorted at every heading, and visible with `--debug-ship-spin`.

**Independent Test**: `swift test --filter ShipSpritePlacement` and `--filter DebugShipOptions`; then
quickstart check 11.

### Tests for User Story 2

- [ ] T013 [P] [US2] Add to `Tests/SwiftSkyRenderingTests/ShipSpritePlacementTests.swift`: C3 (at +π/2 the top edge is the smallest y; at π the smallest x; at −π/2 the largest y); C4 as a parameterised test over the 8 headings in steps of π/4 plus 3 arbitrary ones (sides 2k within 1e-6 of each other, and right angles within 1e-6 rad, from dot products); SC-002 (for the 8 headings, each corner within 1e-6 of its expected place, computed independently from the rotation angle heading − π/2); C6 (at the quarter turns, every corner within 1e-9 of a whole pixel, on a 2× surface with odd pixel width 2,001); C9 (π versus `(-Double.pi).nextUp`: corners within 1e-9); and a position test (a ship at (100, −50) on a 2× surface is centred at the camera's view position × 2, per US2-4)
- [ ] T014 [P] [US2] Create `Tests/SwiftSkyPlatformTests/DebugShipOptionsTests.swift` (`@testable import SwiftSkyPlatform`, the whole file inside `#if SWIFTSKY_INSTRUMENTATION`, as the existing launch-argument tests are): C15, a parameterised test over no argument, each argument alone, both together, and each combined with `--no-debug-overlay` and `--debug-text`

### Implementation for User Story 2

- [ ] T015 [US2] Change `Sources/SwiftSkyPlatform/GameSurfaceView.swift`: inside the existing `#if SWIFTSKY_INSTRUMENTATION` block, beside `DebugTextMode`, add `struct DebugShipOptions: Equatable { var spins: Bool; var hidesShip: Bool; static let spinArgument = "--debug-ship-spin"; static let noShipArgument = "--no-ship"; init(arguments:) }`, with a doc comment (FR-013–FR-015, R9: independent of the text arguments, and absent from Release). In `buildSetup()` set `renderer.drawsShip = !options.hidesShip`. Carry `options.spins` to the loop: store it on `Setup` (instrumentation-only field), and in `start(renderer:layer:)` set `created.debugShipSpin` before `created.start()`. Update `DebugTextMode`'s comment: `--no-debug-overlay` leaves a black surface with the ship, and uniformly black only with `--no-ship` (R11)
- [ ] T016 [US2] Change `Sources/SwiftSkyPlatform/FrameLoop.swift`: add `#if SWIFTSKY_INSTRUMENTATION public var debugShipSpin = false #endif` (set once before `start()`, and read only on the loop thread; doc comment names FR-013). In step 4, under instrumentation, `if debugShipSpin { state = Simulation.advance(state, ticks: ticks, input: Self.spinInput) } else { … }`, with `private static let spinInput = ControlInput(thrust: 0, turn: 1)` (C16). Release keeps the single existing line
- [ ] T017 [US2] Run `./Scripts/verify.sh`; launch macOS Debug with `--debug-ship-spin` and, after the first second of spin-up, time five turns (quickstart check 11). Record the result in the Evidence section

**Checkpoint**: The ship spins counter-clockwise, one turn every 2 s, undistorted.

---

## Phase 5: User Story 3 - The same ship in any window (Priority: P3)

**Goal**: Size and shape are independent of the surface's size, aspect ratio and backing scale.

**Independent Test**: `swift test --filter ShipSpritePlacement`; then quickstart checks 12–14.

### Tests for User Story 3

- [ ] T018 [P] [US3] Add to `Tests/SwiftSkyRenderingTests/ShipSpritePlacementTests.swift`: C7 (for 1280 × 720 pt at scales 1, 2 and 3, the camera's view position of the ship is identical, and the side length divided by the scale is 40 within 1e-9, for several poses); C8 (a ship at the origin on 1280 × 720, 390 × 844 and 1,001 × 667 points at 2× is centred at `(W/2, H/2)` in pixels, which is whole in each case, with sides of 80 px); SC-003's far test (positions ±10⁶ on each axis: the centre is whole and within 0.5 px of `v·s`); and C10 (a ship at the origin on 1280 × 720 at 2×: clip corners are symmetric about (0, 0), and the bottom-left and top-right clip x values are negatives of each other)

### Implementation for User Story 3

- [ ] T019 [US3] No new code is expected: the placement already works in points (T006). If T018 exposes a gap, fix it in `Sources/SwiftSkyRendering/ShipSpritePlacement.swift`. Then run quickstart checks 12–13 (Mac resize and iPad Split View on the simulator) and check 14 if a 1× display is available, and record them in the Evidence section

**Checkpoint**: The ship stays centred and 40 × 40 pt through resizes.

---

## Phase 6: User Story 4 - A missing ship image stops the app with a reason (Priority: P4)

**Goal**: Every failure of the image path is a renderer-initialisation failure with one stable code.

**Independent Test**: `swift test --filter ShipImageBitmap` and `--filter RendererError`; then
quickstart check 18.

### Tests for User Story 4

- [ ] T020 [P] [US4] Add to `Tests/SwiftSkyRenderingTests/ShipImageBitmapTests.swift`: C13. A URL in `FileManager.default.temporaryDirectory` with no file throws `.missing`; a temporary file of plain text throws `.undecodable`; a temporary 16 × 16 PNG written with `CGImageDestination` throws `.wrongSize(width: 16, height: 16)`. Remove the temporary files with `defer`
- [ ] T021 [P] [US4] Create `Tests/SwiftSkyRenderingTests/RendererErrorTests.swift` (`@Suite("RendererError")`): C14 (`.shipImageUnavailable(reason:)` with two different reasons gives `diagnosticCode == "ship_image_unavailable"` for both, and each `userFacingDescription` contains "ship image" and its reason); and every existing case still has a distinct code

### Implementation for User Story 4

- [ ] T022 [US4] Run quickstart check 18: build the macOS Debug app, delete `ship.png` from the built `swiftSky_SwiftSkyRendering.bundle` inside it, launch, and confirm the notice and the `ship_image_unavailable` log line (`log show --predicate 'subsystem == "com.swiftsky.app"' --last 1m`). Rebuild afterwards. Record the result in the Evidence section

**Checkpoint**: A missing image fails loudly and names itself.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T023 [P] Update doc comments (R11): `Sources/SwiftSkySimulation/SimulationState.swift` (the renderer now draws the ship from its position and heading, and still nothing from the order until SKY-30); and `Sources/SwiftSkyRendering/GameSpace.swift` (the SKY-27 note now points at `ShipSpritePlacement`, which implements it)
- [ ] T024 [P] Update `CLAUDE.md`: add `specs/007-ship-sprite-rendering` to "Built so far" (the ship drawn from `ship.png` at its pose), the new files in "Key locations" (`ShipImageBitmap.swift`, `ShipSpritePlacement.swift`, `ShipSprite.swift`, `Resources/ship.png` with the `verify.sh` identity check), and the new launch arguments `--debug-ship-spin` and `--no-ship`, noting that the uniformly black checks now take `--no-ship --no-debug-overlay`
- [ ] T025 Run quickstart checks 15–17 (`--no-ship --no-debug-overlay` is uniformly black; Release shows the still ship with any arguments; `strings` and `nm` on the stripped Release binary show no trace of the switches) check 9 on the iOS simulator, and check 18a (the surface's accessible description is unchanged, FR-016a). Record them in the Evidence section
- [ ] T026 Run quickstart check 19 (60 s of frame time and allocations, overlay on, ship drawn, macOS) and compare it with 003's baseline in the Evidence section (Principle III)
- [ ] T027 Run `./Scripts/verify.sh` and check 7 (10 consecutive `swift test` runs); fill in the rest of the Evidence section, marking any check not run with its reason
- [ ] T028 [P] Update `.tickets/27.yaml` `status` to `done`

---

## Dependencies & Execution Order

- **Setup (Phase 1)**: T001 → T002; T003 is independent. Blocks everything: `Bundle.module` needs the resource declared.
- **Foundational (Phase 2)**: T004, T005 and T006 are independent of each other. Blocks every story.
- **US1 (Phase 3)**: after Phase 2. T009 → T010 → T011 → T012; the tests T007 and T008 can be written first. MVP.
- **US2 (Phase 4)**: after US1 (spinning is only visible once the ship is drawn). T015 → T016 → T017; T013 and T014 first.
- **US3 (Phase 5)**: after Phase 2 for the tests, after US1 for the visual checks.
- **US4 (Phase 6)**: after US1 (T011 wires the error).
- **Polish (Phase 7)**: after all stories.

### Parallel Opportunities

- T003 ∥ T001/T002; T004 ∥ T005 ∥ T006; T007 ∥ T008; T013 ∥ T014; T020 ∥ T021; T023 ∥ T024 ∥ T028.
- T008, T013 and T018 share one file: they are parallel only across separate branches, with a merge.

### Parallel Example: Phase 2

```text
Task: "T004 Add RendererError.shipImageUnavailable(reason:)"
Task: "T005 Create ShipImageBitmap.swift"
Task: "T006 Create ShipSpritePlacement.swift"
```

## Implementation Strategy

### MVP First (User Story 1 only)

1. Phase 1 + Phase 2: the build passes with all existing tests.
2. Phase 3: the ship appears. **Stop and validate**: checks 8 and 10.

### Incremental Delivery

US2 (rotation and spin) → US3 (any window) → US4 (failure) → Polish. Each phase ends green and is
committed on its own.
