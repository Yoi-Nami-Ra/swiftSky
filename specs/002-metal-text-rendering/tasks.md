---

description: "Task list for 002-metal-text-rendering"
---

# Tasks: Metal Text Rendering

**Input**: Design documents from `/specs/002-metal-text-rendering/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/text-rendering.md, quickstart.md

**Tests**: Required. FR-019 and User Story 4 call for headless tests, and constitution Principle II
requires tests for layout logic. Rendering and shader code is exempt; it is validated by the
quickstart checks instead.

**Organization**: tasks are grouped by user story, so that each story can be implemented and
validated on its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US4)
- Paths are relative to the repository root. `R<n>` refers to research.md and `check <n>` to
  quickstart.md.

## Path Conventions

- Layer sources are under `Sources/SwiftSky{Simulation,Rendering,Platform}/`, tests under
  `Tests/`, and scripts under `Scripts/`. See plan.md for the project structure.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: the new test target, the folders, and the headless guard.

- [X] T001 Add `.testTarget(name: "SwiftSkyRenderingTests", dependencies: ["SwiftSkyRendering"], swiftSettings: layerSettings)` to `Package.swift`, with a comment in the style of the existing test target: it depends on SwiftSkyRendering **only**, and its tests must never create a Metal device (R7)
- [X] T002 [P] Create `Sources/SwiftSkyRendering/Text/`, `Sources/SwiftSkyRendering/Debug/` and `Tests/SwiftSkyRenderingTests/`. SwiftPM needs at least one source per target, so add `Tests/SwiftSkyRenderingTests/TextMetricsTests.swift` containing a single placeholder `@Test` that T024 replaces
- [X] T003 [P] Add a `run_stage` guard to `Scripts/verify.sh`, run before `swift test`. It must fail if `grep -rnE 'MTLCreateSystemDefaultDevice|makeBuffer|makeTexture|makeCommandQueue' Tests/` finds anything, and must print the offending lines (R7, FR-019)

**Checkpoint**: `./Scripts/verify.sh` passes, with the new, empty test target running.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the pure, Metal-free text core that every story depends on (data-model.md). None of
these files may import Metal.

**⚠️ CRITICAL**: no user story work can begin until this phase is complete.

- [X] T004 [P] Add a `SurfaceInsets` value type (`top`, `left`, `bottom`, `right` in points; `Sendable, Equatable`; `static let zero`) and a `safeAreaInsets: SurfaceInsets` field on `RenderSurface`, with `.zero` as the init default so existing call sites compile unchanged, in `Sources/SwiftSkyRendering/RenderSurface.swift` (FR-006a, contracts/text-rendering.md)
- [X] T005 [P] Implement `@frozen public struct GlyphInstance { x, y, cell, padding: UInt16 }` in `Sources/SwiftSkyRendering/Text/GlyphInstance.swift`. Document that its layout is mirrored in `Shaders.metal` and must stay exactly 8 bytes (data-model.md)
- [X] T006 [P] Implement `TextRenderingError` (`bitmapContextUnavailable`, `atlasTextureUnavailable`, `pipelineUnavailable(underlying:)`, `bufferUnavailable`; `Error, Sendable, Equatable`) in `Sources/SwiftSkyRendering/Text/TextRenderingError.swift`. Document that none of these may ever be mapped to `RendererError` (FR-018, R12)
- [X] T007 Implement `TextMetrics` in `Sources/SwiftSkyRendering/Text/TextMetrics.swift` (depends on T005; R3):
  - `make(font:scale:)`, which takes the advance of the glyph for `M` (`CTFontGetAdvancesForGlyphs`), ascent, descent, leading and cap height, plus the union of the 95 printable glyphs' bounding rects (`CTFontGetBoundingRectsForGlyphs`);
  - rounding: advance and line height to whole pixels, and the cell size to the union rounded out plus 1 px of padding per side;
  - `cellOriginOffsetX/Y`;
  - an internal memberwise initialiser, so tests can use synthetic metrics.
- [X] T008 Implement `GlyphAtlasBitmap` in `Sources/SwiftSkyRendering/Text/GlyphAtlasBitmap.swift` (depends on T006, T007; R2, FR-003, FR-004, FR-009):
  - `make(font:scale:) throws`: one 8-bit `DeviceGray` `CGContext` with a 16 × 6 grid of cells. White glyphs on black via `CTFontDrawGlyphs`, each at a whole-pixel position. Anti-aliasing on; font smoothing, subpixel positioning and subpixel quantisation off.
  - Store the result as a `[UInt8]` row-major array. Throw `.bitmapContextUnavailable` if the context cannot be created.
  - `static func cell(for asciiCode: UInt8) -> UInt16`: returns `code − 0x20` for 0x20–0x7E, and 31 (`?`) for anything else.
- [X] T009 Implement `TextBuffer` in `Sources/SwiftSkyRendering/Text/TextBuffer.swift` (depends on T005, T007, T008; R6, FR-005, FR-011, FR-012, FR-013):
  - **Storage**: a `final class` with a fixed store of 1,024 `GlyphInstance`s, allocated once with `UnsafeMutableBufferPointer` and freed in `deinit`. `count`, `remainingCapacity` and a sticky `didOverflow`.
  - **Pen**: `clear()`, `begin(at:)` (points to pixels, rounded, per FR-009), and `newline()`.
  - **`write(StaticString, limit:)`**: iterates UTF-8 bytes. A lead byte ≥ 0xC0 becomes one `?`, and continuation bytes are skipped.
  - **`write(String, limit:)`**: iterates `Character`s. `"\n"` and `"\r\n"` are line feeds, and anything that is not a single printable ASCII scalar becomes `?`.
  - **`write(UInt64, minimumDigits:, limit:)`**: extracts digits into a 20-byte stack tuple, pads with zeros, and never cuts digits.
  - **Coordinates**: clamped to `0...65535`, and characters beyond capacity are dropped.
  - **Allocation**: no allocation in any write path except `write(String)`'s iteration.

**Checkpoint**: the text core builds, and US4's tests can start in parallel with US1.

---

## Phase 3: User Story 1 - Developer sees crisp text on macOS (Priority: P1) 🎯 MVP

**Goal**: in a macOS Debug build launched with `--debug-text`, the four-line test string is drawn
sharply 8 pt in from the safe-area top-left, at 2× and at 1×. Without the argument, and in every
Release build, the surface stays black.

**Independent Test**: quickstart checks 5, 6, 9, 10, 12 to 14 and 21. That means capturing at native
resolution on a 2× display and on a 1× display, and comparing the cap height and stroke weight
against 13-pt system monospaced text (SC-001).

### Implementation for User Story 1

- [X] T010 [US1] Add `text_vertex` and `text_fragment` to `Sources/SwiftSkyRendering/Shaders.metal` (contracts/text-rendering.md, R3, R4, FR-007):
  - a `GlyphInstance` struct matching T005 byte for byte, and a uniforms struct holding viewport pixels, cell pixels and the atlas grid;
  - **vertex**: expands `vertex_id` 0–3 into the instance's cell-sized quad, pixel space to clip space, and outputs atlas texel coordinates;
  - **fragment**: samples the `r8Unorm` atlas with a `nearest` sampler and returns premultiplied `(a, a, a, a)` with `a = srgbToLinear(coverage)`.
- [X] T011 [US1] Implement `TextRenderer` in `Sources/SwiftSkyRendering/Text/TextRenderer.swift` (depends on T008–T010; R2, R5, FR-004, FR-012):
  - **`init(device:library:pixelFormat:font:) throws(TextRenderingError)`**: builds a pipeline with blending `one` / `oneMinusSourceAlpha`, a nearest sampler, a ring of 3 `.storageModeShared` 8 KB instance buffers, and a `DispatchSemaphore(value: 3)`. It stores the completion handler once, as a `@convention(block)` property. There is no atlas yet, because the scale isn't known (R8).
  - **`prepareAtlas(scale:) throws(TextRenderingError) -> TextMetrics`**: builds `GlyphAtlasBitmap` and uploads it to an `r8Unorm` texture in the default storage mode via `replace(region:…)`. It is called on the first frame and on every scale change, and returns the new metrics.
  - **`encode(_ buffer: TextBuffer, surface:, encoder:, commandBuffer:) -> Bool`**: when `count == 0`, returns `true` immediately **without taking a slot**, so Release and no-text frames never touch the semaphore. Otherwise it takes a slot with `wait(timeout: .now())` and returns `false` if none is free. It then `memcpy`s `count × 8` bytes, sets the uniforms with `setVertexBytes`, and issues one instanced draw. It must allocate nothing.
- [X] T012 [P] [US1] Implement `DebugTextPattern` with `Mode` (both cases declared, but only `.testString` implemented now; `.fill` comes in T020), FPS measurement, and `write(into:surface:timestamp:)` in `Sources/SwiftSkyRendering/Debug/DebugTextPattern.swift` (depends on T009; R13, FR-006b, FR-014). *Changed during implementation: FPS replaced the frame counter, at the user's request.*
  - wrap the whole file in `#if SWIFTSKY_INSTRUMENTATION`;
  - anchor at the safe-area top-left plus 8 pt;
  - write the three `StaticString` character lines, then `fps ` and the rate, or `fps --` before the first full second;
  - measure FPS over windows of at least 1 s, restarting after a gap of more than 0.25 s, using the timestamp `Renderer.render` receives from `FrameLoop`;
  - pass `now` from `Sources/SwiftSkyPlatform/FrameLoop.swift` into `Renderer.render(…, timestamp:)`.
- [X] T013 [US1] Extend `Renderer` in `Sources/SwiftSkyRendering/Renderer.swift` (depends on T004, T011, T012; contracts/text-rendering.md, R8, R12, FR-001, FR-010, FR-011, FR-018):
  - **Init**: add `textFont: CTFont` to `init`. Build the `TextRenderer` and `TextBuffer` in a `do/catch` that logs `TextRenderingError` through `os.Logger` (subsystem `com.swiftsky.app`, category `text`, level `error`) and continues without text. Never throw a `RendererError` for text. Expose `isTextAvailable`.
  - **Debug pattern**: add `#if SWIFTSKY_INSTRUMENTATION public var debugTextPattern: DebugTextPattern? #endif`.
  - **In `render`**:
    - compare `surface.backingScale` with the atlas scale. There is no atlas before the first frame, so the first frame always mismatches. On a mismatch call `prepareAtlas`; on the first frame create the one `TextBuffer(metrics:)`, and after that assign `textBuffer.metrics`. On failure, disable text and log, and still draw the frame (FR-004, FR-010, FR-018);
    - when a pattern is set, `clear()` and then write the pattern;
    - encode the text after the quad, in the same encoder;
    - return `false` if `TextRenderer.encode` reports no free slot;
    - log a single static `notice` the first time `didOverflow` is set in a run.
  - **Atlas log**: under `SWIFTSKY_INSTRUMENTATION`, log `text atlas scale=<s> cell=<w>×<h>px capHeight=<pt>` at `notice` on every atlas build (R10, used by quickstart checks 5 to 7).
- [X] T014 [P] [US1] macOS safe area: include `safeAreaInsets` (converted from `NSEdgeInsets`) in `currentSurface` in `Sources/SwiftSkyPlatform/MetalSurfaceView.swift`. The existing `setFrameSize` and `viewDidChangeBackingProperties` paths already report it (R8, FR-006a)
- [X] T015 [US1] Update `Sources/SwiftSkyPlatform/GameSurfaceView.swift` (depends on T013; R1, R9, FR-002, FR-007, FR-015, FR-016):
  - **Font**: in `buildSetup()`, resolve the font as `NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)` on macOS and `UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)` on iOS, bridged to `CTFont`. Both branches are needed so `verify.sh` keeps building both destinations. Pass it to `Renderer`.
  - **Opt-in**: under `#if SWIFTSKY_INSTRUMENTATION`, add a private `DebugTextMode` (`none`, `testString`). Parse `ProcessInfo.processInfo.arguments` once for `--debug-text`, and set `renderer.debugTextPattern` before the loop starts.
- [X] T016 [US1] Run quickstart checks 5, 6, 9, 10, 12, 13, 14 and 21 on macOS, and record the evidence in `specs/002-metal-text-rendering/quickstart.md`. This includes the capture-resolution outcome of R10: if low-resolution captures are upscaled, state that only an external 1× display is valid, and correct `research.md` R10. **Done (2026-10-06, SKY-33)**: all eight PASS on macOS (14 on 2026-10-05). R10: captures were taken on a real 1× external display and at 2×, at the backing resolution, not upscaled, so R10 needs no correction; the Open in Low Resolution fallback was not needed.
- [X] T017 [US1] Run failure-path checks 19 and 20 with a temporary forced throw in `GlyphAtlasBitmap.make`. Remove the hook afterwards and confirm with `git diff` that none of it remains. Record the evidence in `specs/002-metal-text-rendering/quickstart.md` (FR-018). **Done (2026-10-06, SKY-33)**: check 19 PASS 2026-10-05, check 20 PASS 2026-10-06 with `sky33-check20-hook.patch`, built in its own derived-data folder and reverted before any commit.

**Merge gate (Principle II)**: US1 contains logic (`TextBuffer`, `TextMetrics`, `GlyphAtlasBitmap`
and the `.testString` pattern), so it MUST NOT merge until its tests T024 to T029 pass. Those tests
are listed under US4 but depend only on Phase 2 and T012.

**Checkpoint**: US1 is fully functional. Text is sharp on macOS at 1× and 2×, Debug without the
argument and Release are both black, and text failures degrade gracefully.

---

## Phase 4: User Story 2 - Developer sees crisp text on iOS (Priority: P2)

**Goal**: the same test string, equally sharp on iOS at 2× and 3×, and always clear of cutouts and
rounded corners in every orientation and iPad multitasking size.

**Independent Test**: quickstart checks 7, 8 and the iOS half of 21, on a 2× device and on a 3× device
with a camera cutout.

### Implementation for User Story 2

- [X] T018 [US2] iOS safe area, in `Sources/SwiftSkyPlatform/MetalSurfaceView.swift` (depends on T014; R8, FR-006a):
  - `currentSurface` reads `window?.safeAreaInsets`, converted from `UIEdgeInsets`, rather than the view's own insets, because the SwiftUI host ignores the safe area;
  - add a `safeAreaInsetsDidChange()` override that calls `surfaceGeometryChanged(scaleChanged: false)`.
- [ ] T019 [US2] **Partly done (2026-10-06)**: 7 and 8 (both landscape orientations) PASS on the iOS simulators. R8 is settled: the insets are read under the host, since the text starts 70.3 pt in on a Dynamic Island phone in landscape (62 pt inset plus the 8 pt margin). Physical devices and iPad Split View and Slide Over are SKY-6; the iOS VoiceOver half of 21 is SKY-39. Run quickstart checks 7, 8 and the iOS VoiceOver half of check 21 on devices, covering both landscape orientations and iPad Split View and Slide Over. Record the evidence, and settle R8's "verify during implementation" item, in `specs/002-metal-text-rendering/quickstart.md`. If `window.safeAreaInsets` reads zero under the host, correct R8 and T018's source of insets.

**Checkpoint**: US1 and US2 both work, sharing one rendering path.

---

## Phase 5: User Story 3 - Text changes every frame without cost (Priority: P3)

**Goal**: 1,024 characters changing every frame, with zero per-frame allocations on our side, zero
skipped frames, frame time within budget, and less than 2 MB of added memory.

**Independent Test**: quickstart checks 15 to 18. These are the Allocations runs with
`--debug-text` and `--debug-text-fill`, and same-device frame-time and memory deltas.

### Implementation for User Story 3

- [X] T020 [US3] Implement `.fill` in `Sources/SwiftSkyRendering/Debug/DebugTextPattern.swift` (depends on T012; R13, FR-015a):
  - repeat the four lines downward from the same anchor, with one blank line between copies, every copy showing the current FPS;
  - write while `remainingCapacity > 0`, using the `limit:` parameter so the last copy is cut to exactly 1,024 characters;
  - `didOverflow` must stay `false`;
  - in the same change, add tests to `Tests/SwiftSkyRenderingTests/DebugTextPatternTests.swift` showing that `.fill` stores exactly 1,024 characters with `didOverflow == false`, on both a large and a narrow surface. This follows Principle II: the `.fill` logic must not merge without its tests.
- [X] T021 [US3] Extend `DebugTextMode` with `fill`, parsed from `--debug-text-fill` and winning over `--debug-text`, in `Sources/SwiftSkyPlatform/GameSurfaceView.swift`. Verify with quickstart check 11 and record the result in `specs/002-metal-text-rendering/quickstart.md` (depends on T015, T020; FR-015a)
- [X] T022 [US3] Run quickstart checks 15 and 16 (Instruments Allocations, 60 s, draw path only, same method as SKY-3 and SKY-4) on macOS and iOS. If the stored completion block allocates (R5), switch to the documented fallback: drop the semaphore and rely on the drawable count, via a note in `Sources/SwiftSkyRendering/Text/TextRenderer.swift`. Record that change in the plan.md Complexity Tracking table, and record the evidence in `specs/002-metal-text-rendering/quickstart.md` (SC-003, FR-012). **Done (SKY-33)**: checks 15 and 16 PASS on iOS and macOS with 011's counter (zero app allocations per frame). R5 was answered by 011 R13: the ring keeps no completion handler, so the fallback was not needed.
- [X] T023 [US3] Run quickstart checks 17 (frame time, three ways, same device) and 18 (idle-footprint delta), and record the numbers in `specs/002-metal-text-rendering/quickstart.md`. Label them as non-baseline hardware while SKY-31 and SKY-32 are open (SC-004, SC-005, Principle III). **Done (SKY-33)**: 17 measured and 18 PASS on macOS, labelled non-baseline in the quickstart.

**Checkpoint**: the Principle III evidence is recorded, and SKY-29 can rely on the path's cost.

---

## Phase 6: User Story 4 - Developer verifies text layout without a GPU (Priority: P4)

**Goal**: the layout, metrics, atlas-bitmap and pattern logic is covered by deterministic headless
tests, run by `./Scripts/verify.sh`.

**Independent Test**: `./Scripts/verify.sh` exits 0, and 10 consecutive
`swift test --filter SwiftSkyRenderingTests` runs pass (checks 1 to 4).

T024 to T028 depend only on Phase 2, so they can run in parallel with Phases 3 to 5.

### Tests for User Story 4

- [X] T024 [P] [US4] Replace the placeholder in `Tests/SwiftSkyRenderingTests/TextMetricsTests.swift` with tests for:
  - `MemoryLayout<GlyphInstance>.size == 8` and `.stride == 8`;
  - rounding of advance and line height at scales 1, 2 and 3 from synthetic font values;
  - `begin(at:)` snapping fractional points to whole pixels;
  - `make(font:scale:)` giving positive cell and line values for a real fixed-pitch `CTFont` (FR-009, R3).
- [X] T025 [P] [US4] Write `Tests/SwiftSkyRenderingTests/TextBufferLayoutTests.swift`, using synthetic metrics (FR-003, FR-005, SC-007). Cover:
  - consecutive cell positions;
  - `\n` and `\r\n` returning the pen to the left edge one line lower;
  - consecutive line feeds and a trailing line feed;
  - `é`, an emoji and a control character each becoming exactly one `?` cell through `write(String)`;
  - a UTF-8 lead byte becoming one `?` through `write(StaticString)`;
  - an empty string storing nothing;
  - coordinates beyond 65,535 being clamped.
- [X] T026 [P] [US4] Write `Tests/SwiftSkyRenderingTests/TextBufferCapacityTests.swift` (FR-011, US4-2). Cover:
  - 1,100 characters storing exactly 1,024 and setting `didOverflow`;
  - exactly 1,024 characters not setting it;
  - line feeds not counting toward capacity;
  - `limit:` capping a write;
  - `clear()` resetting `count` and `didOverflow`.
- [X] T027 [P] [US4] Write `Tests/SwiftSkyRenderingTests/NumberWritingTests.swift` (FR-013). Cover:
  - `0`;
  - `123` with `minimumDigits: 6` giving `000123`;
  - `UInt64.max` written in full (20 digits);
  - a 7-digit value with `minimumDigits: 6` never being cut short.
- [X] T028 [P] [US4] Write `Tests/SwiftSkyRenderingTests/GlyphAtlasBitmapTests.swift` using `CTFontCreateUIFontForLanguage(.userFixedPitch, 13, nil)` at scales 1, 2 and 3 (R2, R7, SC-007). Cover:
  - the bitmap measuring `16 × cellWidth` by `6 × cellHeight`;
  - every non-space cell containing a non-zero pixel;
  - all 95 cells being pairwise distinct;
  - `cell(for:)` mapping 0x20→0, 0x7E→94, and 0x0A, 0x7F and 0xC3 to 31.
- [X] T029 [P] [US4] Write `Tests/SwiftSkyRenderingTests/DebugTextPatternTests.swift` for `.testString` (depends on T012 only; FR-014, R13). T020 adds the `.fill` tests to the same file. Cover:
  - `.testString` storing the 95 printable characters in code order, split into lines of 33, 32 and 30 characters;
  - the FPS line reading `fps --` before a full second, then `fps 30`, `fps 60` and `fps 120` at those rates, with a pause restarting the measurement;
- [X] T030 [US4] Run `./Scripts/verify.sh`, then `swift test --filter SwiftSkyRenderingTests` 10 times in a row, and record checks 1 to 4 in `specs/002-metal-text-rendering/quickstart.md` (SC-008)

**Checkpoint**: all four stories are complete and verified.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T031 [P] Audit the layers, and record the results in `specs/002-metal-text-rendering/quickstart.md` under check 1 (Principle I, FR-012, FR-016). Confirm that:
  - nothing under `Sources/SwiftSkyRendering/` imports AppKit or UIKit, and nothing under `Sources/SwiftSkySimulation/` changed;
  - `DebugTextPattern` and the argument parsing are only compiled under `SWIFTSKY_INSTRUMENTATION`;
  - the per-frame path (`TextBuffer` StaticString/UInt64 writes, `TextRenderer.encode`, `Renderer.render`) contains no `String` interpolation, `String(describing:)`, arrays built per frame, or closures.
- [X] T032 [P] Reconcile the design documents with what was built: update `specs/002-metal-text-rendering/research.md` (the outcomes of R5, R8 and R10) and `specs/002-metal-text-rendering/contracts/text-rendering.md` for any signature that changed during implementation
- [X] T033 [P] Update `CLAUDE.md` (Key locations) so that it no longer describes the repo as scaffold-only. List `Sources/SwiftSkyRendering/Text/`, the `SwiftSkyRenderingTests` target, and the `--debug-text` / `--debug-text-fill` launch arguments.
- [X] T034 Final `./Scripts/verify.sh`, plus a last read-through of the quickstart "Evidence to record" section to confirm that every check from 1 to 21 has a dated result or an explicit "not run — reason"

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T003)**: no dependencies.
- **Foundational (T004–T009)**: depends on Setup, and blocks all stories.
- **US1 (T010–T017)**: depends on Foundational. This is the MVP.
- **US2 (T018–T019)**: depends on US1, because it needs the renderer, shaders and platform font path from T013 and T015.
- **US3 (T020–T023)**: depends on US1 (T012, T015). It can run in parallel with US2.
- **US4 (T024–T030)**:
  - T024 to T028 depend only on Foundational, and can run alongside US1;
  - T029 needs T012 only, and the `.fill` tests arrive with T020;
  - T030 needs every other US4 task.
- **Polish (T031–T034)**: after all stories.

### Within-phase ordering

- T007 → T008 → T009. T004, T005 and T006 are independent, so they are marked [P].
- T010 → T011 → T013. T012 runs in parallel with T010 and T011, and T013 needs it.
- T013 → T015 → T016 and T017. T014 is independent of T013.

### Parallel opportunities

- **Setup**: T002 ∥ T003.
- **Foundational**: T004 ∥ T005 ∥ T006.
- **After Foundational**: US1's T010 and T012, US4's T024–T028, and T014 can all run at once. T029 follows as soon as T012 is done.
- **After US1**: US2 (T018–T019) ∥ US3 (T020–T023).
- **Polish**: T031 ∥ T032 ∥ T033.

## Parallel Example: straight after Phase 2

```text
Task: "T010 [US1] Add text_vertex/text_fragment in Sources/SwiftSkyRendering/Shaders.metal"
Task: "T012 [US1] DebugTextPattern .testString in Sources/SwiftSkyRendering/Debug/DebugTextPattern.swift"
Task: "T014 [US1] macOS safeAreaInsets in Sources/SwiftSkyPlatform/MetalSurfaceView.swift"
Task: "T025 [US4] TextBufferLayoutTests.swift"
Task: "T026 [US4] TextBufferCapacityTests.swift"
Task: "T027 [US4] NumberWritingTests.swift"
Task: "T028 [US4] GlyphAtlasBitmapTests.swift"
```

## Implementation Strategy

### MVP first (User Story 1)

1. Phase 1, then Phase 2.
2. Phase 3 (US1). Stop and validate with checks 5, 6, 9, 10 and 12 to 14 on macOS.
3. Run the US4 tests T024 to T029 alongside. They are the US1 merge gate (Principle II), because a
   logic change must not merge without its tests.

### Incremental delivery

1. **US1**: sharp text on macOS, which is the MVP.
2. **US2**: iOS plus the safe area.
3. **US3**: full-capacity mode and the Principle III evidence. This is required before SKY-29 starts.
4. **US4**: the 10-run determinism record (T030). The other US4 tests have already landed with US1.
5. **Polish**: reconcile the documents and update CLAUDE.md.

## Notes

- [P] means different files and no dependency on an incomplete task.
- Checks that need hardware which isn't available (a 1× display, a 3× device, a device with a
  camera cutout) are recorded as "not run — reason", never as passed.
- Commit after each task or logical group.
