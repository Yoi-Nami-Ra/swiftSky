# Quickstart & Validation Guide: Metal Text Rendering

**Feature**: `002-metal-text-rendering` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

This guide covers how to run the text path and verify every success criterion. Entity shapes are in
[data-model.md](./data-model.md), interfaces are in [contracts/text-rendering.md](./contracts/text-rendering.md),
and the reasons behind each decision are in [research.md](./research.md). The 001 checks still
apply unchanged. [001 quickstart](../001-metal-app-shell/quickstart.md) checks 1 to 6 are re-run
here as check 12.

---

## Prerequisites

- The same as 001: Xcode 27, the iOS 26 and macOS 26 SDKs, and the Metal toolchain component.
- **Displays and devices**:
  - a Mac with a 2× display;
  - for 1×, a standard-resolution external display, or the low-resolution fallback in research R10;
  - an iOS device at 2× (for example iPhone 11 or an iPad);
  - an iOS device at 3× (any recent iPhone), ideally one with a camera cutout, for the landscape
    safe-area check.
- **Performance and memory checks (15 to 18)**: before/after deltas on one device are valid on any
  hardware (research R11). Absolute baseline numbers wait for SKY-31 and SKY-32.

## Run it

| Build | How to launch |
|-------|---------------|
| macOS Debug, test string | Xcode scheme **swiftSky (macOS)** → Edit Scheme → Run → Arguments → add `--debug-text` → Run |
| macOS, full capacity | the same, with `--debug-text-fill` instead |
| macOS built app | `open <path>/swiftSky.app --args --debug-text` |
| iOS | scheme **swiftSky (iOS)** with the same arguments, or `xcrun devicectl device process launch --device <id> <bundle-id> --debug-text` |

**Expected**: four lines of white text, 8 pt in from the top-left of the safe area, over black:

```text
 !"#$%&'()*+,-./0123456789:;<=>?@
ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_`
abcdefghijklmnopqrstuvwxyz{|}~
fps 120               ← frames drawn in the past second, updated once a second
```

Without either argument no text is drawn. Since 003 a Debug build shows the debug overlay instead, and
since 007 the ship is drawn too; with `--no-ship --no-debug-overlay` the surface is uniformly black, as in 001.

## One-command verification

```bash
./Scripts/verify.sh
```

The script is unchanged in how it is used. It now also:
- runs the `SwiftSkyRenderingTests` suite, since `swift test` picks up every test target;
- fails if anything under `Tests/` creates a Metal device, buffer or texture (research R7).

---

## Validation matrix

> **Since 003-debug-overlay**: a Debug build shows the live debug overlay by default. Check 12's
> black-surface run therefore takes `--no-debug-overlay`. `--debug-text` and `--debug-text-fill`
> replace the overlay, so checks 5 to 11 are unchanged.
>
> **Since 007-ship-sprite-rendering**: the ship is drawn at the surface centre. Debug runs that expect
> a uniformly black surface take `--no-ship --no-debug-overlay`, and the text checks (5 to 11) add
> `--no-ship`. `--no-ship` is a debug argument, so a Release build always draws the ship (check 13).
>
> **Since 011-draw-allocation-counter**: checks 15 and 16 use 011's "The method"
> ([quickstart](../011-draw-allocation-counter/quickstart.md)), not Instruments.

### Automated (headless)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `./Scripts/verify.sh` | Exits 0, with the layout, metrics, atlas-bitmap and pattern tests passing, and no `warning:` lines | FR-019, SC-008 |
| 2 | Run `swift test --filter SwiftSkyRenderingTests` 10 times in a row | 10 identical passes | SC-008 |
| 3 | Tests cover all 95 glyphs: each non-space cell has ink, and no two cells are identical. A non-ASCII input maps to the `?` cell. | Pass | SC-007, FR-003 |
| 4 | Tests cover capacity: 1,100 characters store exactly 1,024 and set `didOverflow`, and `.fill` stores exactly 1,024 without setting it | Pass | FR-011, FR-015a |

### Visible output

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 5 | macOS, 2× display, `--debug-text`. Capture the window with `screencapture -l <id> -o` and inspect it at 100 %. | Capital `H` height in pixels = the `capHeight` from the `text atlas` log line × 2, ±1 px. Next to 13-pt system monospaced text (for example in TextEdit), there is no blur, doubling or heavier stroke, and the text is white. | SC-001, FR-007, FR-009 |
| 6 | Drag the window to a 1× display, and confirm the log line `text atlas scale=1`. Capture again. | Redrawn within 1 s. Cap height = the logged `capHeight` × 1, ±1 px, and equally sharp. | SC-001, FR-010, US1-2 |
| 7 | iOS at 2× and at 3×, `--debug-text`, screenshot | The same cap-height and sharpness checks at ×2 and ×3 | SC-002 |
| 8 | iOS with a camera cutout: rotate to both landscape orientations. On iPad, also enter Split View and Slide Over. | Text is always fully visible, 8 pt in from the safe-area top-left, and never under the cutout or a rounded corner | FR-006a, FR-006b, US2-2 |
| 9 | macOS: resize the window, then enter and leave full screen (on a display with a camera housing, if available) | Text keeps its size, and its anchor moves with the safe area | FR-008, FR-006a |
| 10 | Watch the FPS line, and compare it with the `frames=` count per second in the instrumentation log | `fps --` for the first second, then the display's rate (for example 120 on a 120 Hz display, 60 on 60 Hz), matching the log to within 1. It is updated once a second. | FR-014 |
| 11 | Launch with both `--debug-text` and `--debug-text-fill` | The fill pattern appears | FR-015a |
| 12 | Launch Debug with `--no-ship --no-debug-overlay` and neither text argument, and screenshot or capture the surface | Uniformly black: no text is drawn. (001's own checks are tracked in the 001 quickstart; its GPU-capture checks are SKY-18 and SKY-19.) | SC-006, FR-015, FR-017 |
| 21 | With `--debug-text`, inspect the surface with Accessibility Inspector (macOS) and VoiceOver (iOS) | Only the 001 label "swiftSky game surface" is exposed. None of the test string's text is announced or listed as an element. | FR-020, 001 FR-009 |

### Release

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 13 | Build Release and launch it with `--debug-text-fill` | Black, with only the ship drawn, centred and facing right (007 FR-014): every non-black pixel lies inside the ship's 40-pt square at the centre. No text. | SC-006, FR-016 |
| 14 | Inspect the Release binary with `nm` and `strings` | No `DebugTextPattern` or `debug-text` symbols or strings, while `TextBuffer` **is** present | FR-016, SC-006 |

### Performance and memory (Principle III)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 15 | 011's "The method": an optimised instrumented build (Release plus `SWIFTSKY_INSTRUMENTATION`), a 60 s run with `--debug-text`, read from the frame summaries | `allocation counter ready`, and `allocs=0 allocframes=0` in every summary after the first. Research R5's stored-block question is settled by 011 research R13: a completion handler is re-bridged into a heap block on every call, so the instance ring has none. | SC-003, FR-012 |
| 16 | The same with `--debug-text-fill` | As check 15, and every summary shows `skipped=0` | SC-003, SC-004 |
| 17 | Frame time three ways on one device: no argument, `--debug-text`, `--debug-text-fill` (60 s each, instrumentation log) | Mean and worst stay within budget in all three. Record the before/after numbers here. | SC-004 |
| 18 | Idle footprint without text, then with `--debug-text-fill`, on the same device and build | Delta ≤ 2 MB, and the first frame is still visible within 1 s | SC-005 |

### Failure paths

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 19 | Temporarily force `GlyphAtlasBitmap.make` to throw on the first frame's atlas build (for example with a debug-only environment hook added for this check and then removed), and launch with `--debug-text` | The app runs, the surface is black, one `error` line in category `text` names the cause, and there is no failure notice and no crash | FR-018 |
| 20 | Force the same failure on the rebuild after a scale change, then move the window to another display | Text disappears rather than showing at the wrong density, and the failure is logged | FR-018, FR-010 |

## Evidence to record

Under each check, add the date, the device, the result, and any measured numbers (checks 5 to 7 and
15 to 18). The "Verify during implementation" items in research R5, R8 and R10 are settled by checks
15 and 16, check 8, and checks 5 and 6 respectively. Record their outcome here, and correct
research.md if an assumption fails.

### Evidence, 2026-09-30 (implementation session, Apple silicon MacBook Pro, macOS 27, Xcode 27 RC)

This is non-baseline hardware, so the performance numbers are indicative only (SKY-31, SKY-32).

**Known unrelated failure**: `./Scripts/verify.sh` fails on `main` too, even from a clean `.build`,
because swiftbuild emits `warning: missing creator for mutated node: …SwiftSkyRendering.bundle/Contents/MacOS`
with this toolchain. It is a build-system diagnostic, not a compiler one, and it predates this
feature. It is being handled in a separate task. Every other stage passes, and the checks below
count "only that warning" as passing.

| # | Result | Notes |
|---|--------|-------|
| 1 | **PASS** (apart from the known warning) | The headless guard, 33 rendering tests, 23 simulation tests, and both app builds all pass |
| 2 | **PASS** | 10 of 10 consecutive `swift test --filter SwiftSkyRenderingTests` runs passed |
| 3 | **PASS** | `GlyphAtlasBitmapTests` at 1×, 2× and 3×: every non-space cell has ink, and all 95 cells are distinct. Non-ASCII input maps to the `?` cell. |
| 4 | **PASS** | `TextBufferCapacityTests` and the `.fill` tests in `DebugTextPatternTests` |
| 5, 6 | **Partly done: log only, no image** | Log: 2× built-in display `scale=2 cell=19×30px capHeight=9.16pt`; 1× external display `scale=1 cell=11×17px`. Window capture was refused (Screen Recording permission is not granted to the session), so the pixel measurement and the side-by-side comparison are still to be done by eye. |
| 7, 8 | **Not run** | The iOS Simulator run was stopped at the user's request, and no devices were attached |
| 9 | **Not run** | Needs a person to resize the window and use full screen |
| 10 | **Not run (visual)** | Log side: `frames=` rates of about 120 per second (built-in display) and about 60 (external). The on-screen `fps` line still needs checking by eye. |
| 11 | **PASS (indirect)** | With both arguments, the frame-time profile matches fill (mean 0.77 ms against 0.69 ms for fill and 0.27 ms for the test string) |
| 12 | **Not run (visual)** | Structurally, with no argument no pattern is set, so `TextBuffer` stays empty and no draw is issued |
| 13 | **PASS (structural)** | Release contains no `DebugTextPattern`, so no argument can produce text. A visual confirmation is still outstanding. |
| 14 | **PASS** | Release binary: 0 `DebugTextPattern` symbols, 0 `debug-text` strings, 0 `text atlas` strings; 52 `TextBuffer` symbols present; `swiftsky_text_vertex` present in the metallib |
| 15, 16 | **Not run** | The `xctrace record --template Allocations` recording failed to attach from the session, so Instruments needs to be run by hand. Indirect evidence: `skipped=0` in every run, so the instance ring never ran dry. Method since 011: `specs/011-draw-allocation-counter/quickstart.md`, "The method" — an optimised build with the counter compiled in, no Instruments (011 R12); a Profiling build carries no instrumentation (011 R1). |
| 17 | **Measured** (macOS, 60 Hz external display, budget 16.7 ms) | No text: mean 0.16 / worst 0.67 ms. `--debug-text`: 0.27 / 0.66 ms. `--debug-text-fill`: 0.69 / 1.79 ms. All with 0 skipped and 0 dropped. |
| 18 | **PASS** (macOS) | `phys_footprint`: 42 MB with no text, 42 MB with the test string, 42 MB with fill, and 43 MB with both arguments. The delta is ≤ 1 MB, within the 2 MB ceiling. |
| 19 | **PASS** | A forced `bitmapContextUnavailable` on the first frame logged `E … [com.swiftsky.app:text] text disabled: bitmapContextUnavailable`. The app kept rendering (0 skipped), with no failure notice and no crash. The temporary hook was removed, and the source was confirmed free of it. |
| 20 | **Not run** | Needs a failure forced after a display change, with a window moved by hand |
| 21 | **Not run** | Needs Accessibility Inspector and VoiceOver |

### Evidence, 2026-10-05 (SKY-33, Apple silicon MacBook Pro, macOS 27, Xcode 27)

The iOS runs used the iPhone 18 Pro simulator (iOS 27.0, 3×, Dynamic Island, landscape 2622 × 1206 px)
and an iPad (A16) simulator created for this check (iOS 27.0, 2×, portrait 1640 × 2360 px). Screenshots
came from `xcrun simctl io <udid> screenshot`, which captures the simulator's framebuffer pixel for pixel,
and logs from `xcrun simctl spawn <udid> log stream`. The host was heavily loaded (load average 30–200),
so the simulators presented about 42–46 frames a second, with `skipped=0 dropped=0`. Pixel figures come
from a small CoreGraphics tool. It takes a glyph's ink box from the screenshot. It renders a reference
`H` with Core Text in the 13-pt system monospaced font at the same scale, with the atlas's settings
(grayscale anti-aliasing, no smoothing, no subpixel positioning). It then compares the two pixel by pixel.

| # | Result | Notes |
|---|--------|-------|
| 7 | **PASS** (iOS simulator, 3× and 2×) | Debug, `--debug-text --no-ship`. **3×** (iPhone 18 Pro): log `text atlas scale=3.000000 cell=27×44px capHeight=9.159668pt`, so the expected height is 27.48 px. The `H` (line 2, 8th glyph) has 28 ink rows, 27 of them at ≥ 50 % coverage, and a coverage-weighted height of **27.48 px**. Against the Core Text reference H it is identical in every measure (186 full and 134 partial pixels, the same stem profile `22,255,255,255,65 … 37,255,255,255,50`), with a mean absolute difference of **0.04/255** over the 20 × 28 box. **2×** (iPad): log `scale=2.000000 cell=19×30px capHeight=9.159668pt`, so 18.32 px expected. The H has 19 ink rows, 18 at ≥ 50 %, and a coverage-weighted height of **18.32 px**. The difference from the reference is **0.00/255** over 14 × 19. White (max RGB 255,255,255), no blur, doubling or extra weight: the drawn glyph *is* the Core Text rasterisation. |
| 8 | **Prepared, not run** | Rotation needs the Simulator's Rotate Left/Right (⌘← / ⌘→), which the agent cannot press. Launched as delivered, the text starts at x = 211 px (70.3 pt) and y = 30 px on the iPhone 18 Pro, clear of the Dynamic Island in that orientation. Procedure: `xcrun simctl launch 17791BD4-BD96-45F0-B617-A325459BD30A com.swiftsky.app --debug-text --no-ship` (Debug build installed). Then press ⌘→ in Simulator, wait 2 s, and take `xcrun simctl io … screenshot`. Repeat with ⌘← for the other landscape orientation. Expected in each: every glyph's ink lies inside the safe area (8 pt in from its top-left), and none sits under the Dynamic Island or a rounded corner. 003 check 9 (the overlay, no argument) can be run in the same pass. **iPad Split View and Slide Over: not run → SKY-6.** No iPad multitasking can be driven from here. |
| 10 | **PASS** (iOS simulator) | Debug, `--debug-text --no-ship`. Log summaries every 120 frames give the rate as 120 ÷ the time between summaries. iPhone 18 Pro: on-screen `fps 42`, `fps 43`, `fps 44` at three moments 5 s apart; the summaries around them give 42.6–43.4, 43.1 and 44.1 frames a second. iPad: `fps 46` and `fps 45`, against 46.4 and 44.2. Each is within 1. The `fps --` first second was not captured: the first screenshot comes 5 s after the first summary. 003's `FrameTimeWindowTests` cover it. |
| 12 | **PASS** (iOS simulator) | Debug, `--no-ship --no-debug-overlay`. Two screenshots 5 s apart while the log showed frames being presented: `2622x1206 nonBlack=0 maxRGB=(0, 0, 0)` in both. macOS: Mac session. |
| 13 | **PASS** (iOS simulator) | Release (no instrumentation), `--debug-text-fill`. Two screenshots: 7,492 non-black pixels, all inside x 1252…1367 and y 543…662, that is, the ship in the 120 × 120 px (40 pt) square at the surface centre (1311, 603). **0** pixels outside that square, and max RGB 240 (the sprite, not white text). macOS: Mac session. |
| 15 | **PASS** (iOS simulator and macOS) | 011's "The method": optimised instrumented builds (Release + `SWIFTSKY_INSTRUMENTATION`), `--debug-text --no-ship`, 60 s. **iOS** (iPhone 18 Pro): `allocation counter ready`, then 24 summaries, **every one** `allocs=0 allocframes=0 eventallocs=0`. Last: `frames=2875 skipped=0 dropped=0 mean=0.156ms worst=2.48ms`. `gfxallocs ÷ frames` = 28.0 (one summary 28.0083). **macOS** (`open -n`, window on the 1× 60 Hz external display, `text atlas scale=1.000000 cell=11×17px`): 18 summaries, every one `allocs=0 allocframes=0`. Last: `frames=2153 skipped=0 dropped=0 mean=0.182ms worst=0.79ms`. That is about 36 frames a second, against 60 in the fill run: the loop pauses while the window is covered, so the window was probably partly covered for part of this run. Every frame presented was counted, and none allocated. `gfxallocs ÷ frames` = 10.0. `eventallocs` was 0 except `eventallocs=1` in the final summary, which covers the quit. Zero allocations on our side in the draw path. Research R5's stored-block question was answered by 011 R13. |
| 16 | **PASS** (iOS simulator and macOS) | As check 15 with `--debug-text-fill` (screenshot confirmed: the test-string block repeated down the surface, 111,335 non-black pixels). **iOS**: 24 summaries, all `allocs=0 allocframes=0 eventallocs=0 skipped=0 dropped=0`. Last: `frames=2878 mean=0.162ms worst=11.04ms`; the worst is one host-load outlier, still under the 16.7 ms budget. **macOS**: 31 summaries, all `allocs=0 allocframes=0 eventallocs=0 skipped=0 dropped=0`. Last: `frames=3713 mean=0.199ms worst=2.27ms`. |
| 20 | **Prepared, not run** | Needs the window dragged between displays by hand. The temporary hook is ready as a patch (not committed): see the Mac session below. Reading the code (`Renderer.prepareText`): a throw from `prepareAtlas` sets `textDisabled`, clears the buffer and logs `text disabled: …`, and the previous atlas is never reused. So the expected result is that the text disappears. |
| 21 | **iOS: not run → SKY-39** | The iOS simulator has no VoiceOver, and SKY-39 holds the physical-device VoiceOver checks. macOS: Mac session. Strong prior: 003 check 12 macOS PASS (SKY-8) exposes only "swiftSky game surface" with the overlay, which uses this same text path. |

Still open after this session (Mac session below): 5, 6, 9, 12 and 13 on macOS, 20, and 21 on macOS.
Then 8 (rotation keypresses only).

### Mac session (SKY-33): the checks that need a person at the Mac

One sitting, about 30 minutes, on this Mac (2× built-in display with a camera housing, plus the 1×
60 Hz external display). The agent has no Screen Recording or Accessibility permission, so the person
captures with ⌘⇧5 (window capture: press Space, then click the window; hold Option to drop the shadow)
and hands over the PNG or MOV files, and the agent does the pixel measurement. Record each result in
the evidence table under a new dated heading.

**Build once** (Debug, and Release for check 13):

```sh
xcodebuild build -project swiftSky.xcodeproj -scheme "swiftSky (macOS)" -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath /tmp/sky33-mac
xcodebuild build -project swiftSky.xcodeproj -scheme "swiftSky (macOS)" -configuration Release \
  -destination 'platform=macOS' -derivedDataPath /tmp/sky33-mac
DBG=/tmp/sky33-mac/Build/Products/Debug/swiftSky.app
REL=/tmp/sky33-mac/Build/Products/Release/swiftSky.app
```

Read the text log in another Terminal tab during each run:
`/usr/bin/log stream --style compact --predicate 'subsystem == "com.swiftsky.app" AND category == "text"'`

1. **Check 5 (2×)**: `open -n $DBG --args --debug-text --no-ship`, with the window on the built-in
   display. Confirm the log line `text atlas scale=2.000000 … capHeight=9.159668pt`. Open TextEdit
   beside it with a line `ABCDEFGH` in SF Mono (or Menlo) 13 pt, white on black if possible. Capture
   both windows. Expected: the capital H is 18 px tall (9.16 × 2 = 18.3, ±1), white, with no blur
   or doubling, and no heavier than the TextEdit text.
2. **Check 6 (1×)**: drag the same window onto the external display. Within 1 s the log shows
   `text atlas scale=1.000000 cell=11×17px`. Capture again. Expected: the capital H is 9 px tall
   (9.16 ± 1) and equally sharp.
3. **Check 9 (resize, full screen)**: on the built-in display, record the window with ⌘⇧5 ("Record
   Selected Portion") while you drag it small, then large, then enter full screen (⌃⌘F) and leave it.
   Expected: the text stays the same size and stays 8 pt from the safe area's top-left. In full screen
   it sits below the camera housing, not under it. 003 check 17 and 009 check 8 can be watched in the
   same recording, launched without `--debug-text`.
4. **Check 12 (Mac)**: `open -n $DBG --args --no-ship --no-debug-overlay`. Capture the window.
   Expected: uniformly black.
5. **Check 13 (Mac)**: `open -n $REL --args --debug-text-fill`. Capture the window. Expected: black
   with only the ship, centred and facing right. No text.
6. **Check 21 (Mac)**: `open -n $DBG --args --debug-text --no-ship`. Open Xcode → Open Developer
   Tool → Accessibility Inspector, target swiftSky, and hover over the text. Then turn VoiceOver on
   (⌘F5) and move through the window. Expected: only "swiftSky game surface" (VoiceOver: ", image").
   No test-string text is listed or announced.
7. **Check 20 (forced failure after a display change)**. The agent applies the temporary hook
   `sky33-check20-hook.patch` to the worktree (`git apply …`). It makes `GlyphAtlasBitmap.make`
   throw `bitmapContextUnavailable` on its second call. The agent then rebuilds Debug. Launch
   `open -n $DBG --args --debug-text --no-ship` on the built-in display, and check the log shows
   `text atlas scale=2.000000`. Drag the window to the external display. Expected: the text
   disappears and stays gone, the log shows one `E … [com.swiftsky.app:text] text disabled:
   bitmapContextUnavailable` line and no `text atlas scale=1` line, and the app keeps running with
   no failure notice. Drag the window back to the built-in display: the text stays gone.
   The agent then reverts the hook (`git apply -R …`), and `git status` must be clean.

### Evidence, 2026-10-06 (SKY-33 Mac session)

Debug build of `main` at `e0c9fdd`, launched with `open -n … --args --debug-text --no-ship`, on the
2× built-in display (3456 × 2234 px, 120 Hz) and the 1× external display (60 Hz). Captures were taken
by hand with ⌘⇧5. The capital `H` is the eighth glyph of the second line. It was measured with a
small CoreGraphics tool: rows of ink, rows at ≥ 50 % coverage, and the coverage-weighted height (the sum
over rows of the brightest pixel ÷ 255).

| # | Result | Notes |
| --- | --- | --- |
| 5 | **PASS** (2×) | Captured after dragging the window to the built-in display, after the log showed `text atlas scale=2.000000 cell=19×30px capHeight=9.159668pt`, so 18.32 px expected. The `H` has 19 ink rows, 18 at ≥ 50 %, and a coverage-weighted height of **18.32 px**. Both stems are full white (255) from top to bottom, with one partial row (81) above them; the crossbar is 172–186. White (max RGB 255, 255, 255), no blur or doubling. The TextEdit line beside it was in SF Pro, not SF Mono, so the weight comparison is by eye only: no heavier. The on-screen `fps` read 119. |
| 6 | **PASS** (1×) | The window opened on the external display, and the log showed `text atlas scale=1.000000 cell=11×17px capHeight=9.159668pt`, so 9.16 px expected. The `H` has 10 ink rows, 9 at ≥ 50 %, and a coverage-weighted height of **9.16 px**. The left stem is full white for its 9 rows. The `fps` line read 60. |
| 9 | **PASS** | Three window captures on the built-in display (2×) at three sizes: the captures measure 1504 × 1008, 3208 × 2082 and 3680 × 2392 px (shadow included). In all three the `H` is identical: 19 ink rows, 18 at ≥ 50 %, a coverage-weighted height of 18.32 px, at the same place: the first glyph's ink starts 15 px right of the content's left edge and the first line's ink 20 px below the content's top edge. The size and anchor do not change with the window. **Full screen** (⌘⇧3 of the built-in display, 3456 × 2234 px): the same `H` (18.32 px), the first glyph's ink 17 px from the screen's left edge and the first line's ink 150 px (75 pt) below the top edge, so below the camera housing, not under it. The extra vertical offset against the window is the full-screen safe-area inset, which a capture cannot show directly. The `fps` line read 81 in full screen. |
| 12 | **PASS** (macOS) | Debug, `--no-ship --no-debug-overlay`, window on the 1× external display. Window capture 2032 × 1162 px: every one of the 1,903,584 content pixels checked (below the title bar, 12 px inside the frame and corners) is black, max RGB (0, 0, 0). |
| 13 | **PASS** (macOS) | Release (no instrumentation), `--debug-text-fill`, window on the 1× external display. Window capture 2032 × 1162 px: of the 1,903,584 content pixels checked, 832 are not black, all inside a 38 × 40 px box (the 40 pt ship) centred at (1015, 562). That is the centre of the whole window surface, title bar included (opaque rows 38…1087, columns 56…1975). Max RGB (240, 239, 240), the sprite, not white text. Enlarged, the ship faces right. No text anywhere. |
| 21 | **PASS** (macOS) | Debug, `--debug-text --no-ship`, test string on screen. Reported by the tester: Accessibility Inspector shows only "swiftSky game surface", and VoiceOver announces only the game surface; none of the test text is listed or announced. No screenshot was kept. The iOS half stays with SKY-39. |
| 20 | **PASS** | Debug built with `sky33-check20-hook.patch` applied into its own derived-data folder (`/tmp/sky33-hook`); the source was reverted straight after, so `main`'s tree never carried the hook. Launched with `--debug-text --no-ship` on the 1× external display: `text atlas scale=1.000000 cell=11×17px` (the first build). Dragged to the built-in display at 22:54:41: one `E … [com.swiftsky.app:text] text disabled: bitmapContextUnavailable` line, no second `text atlas` line, and the frame summaries carried on (`skipped=0 dropped=0`, no failure notice, no crash). Dragged back to the external display: no `text atlas` line, and the window capture (1× title bar) is black, so the text stayed gone. Aside, filed under SKY-47: after the move back, the summaries came every 2.0 s per 120 frames (60 Hz) but still reported `budget=8.333333ms`. |
| 10 | **PASS** (macOS) | Rate from the log = 120 frames ÷ the time between two summaries. 1× external display (60 Hz): the capture at 19:20:38 shows `fps 60`; the summaries from 19:20:27 to 19:20:39 give 59.5–60.0. 2× built-in display (120 Hz): the capture at 19:23:42 shows `fps 119`; the summaries ending 19:23:41.7 and 19:23:42.7 give 120.0 and 117.1, and those from 19:23:20 to 19:24:00 give 112.6–120.1. The on-screen value is a one-second window that does not line up with the summaries, so it is compared with the summaries either side of it: within 1 of the nearer one in both cases. |
| 8 | **PASS** (iOS simulator, rotation) | iPhone 17 Pro simulator (iOS 27.0, 3×, Dynamic Island), Debug, `--debug-text --no-ship`, `xcrun simctl io … screenshot` (2622 × 1206 px, oriented). Landscape with the island on the left: ink box x 211…1000, y 30…208, so the text starts 211 px (70.3 pt) from the left edge, past the island's 62 pt inset plus the 8 pt margin, and 30 px from the top. Rotated 180° in the simulator panel, so the island is on the right: the same ink box, x 211…1000, y 30…208 (iOS gives both landscape sides the same horizontal inset). At 30 px from the top, a corner of about 55 pt radius reaches only about 70 px in, so the text at 211 px is clear of it. No glyph under the island or a corner in either orientation. iPad Split View and Slide Over stay with SKY-6. |
