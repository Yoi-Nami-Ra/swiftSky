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

Without either argument the surface is uniformly black, exactly as in 001.

## One-command verification

```bash
./Scripts/verify.sh
```

The script is unchanged in how it is used. It now also:
- runs the `SwiftSkyRenderingTests` suite, since `swift test` picks up every test target;
- fails if anything under `Tests/` creates a Metal device, buffer or texture (research R7).

---

## Validation matrix

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
| 12 | Launch Debug with **no** argument, and re-run 001 checks 1 to 6 | Uniformly black, and 001 checks 1 to 6 pass unchanged | SC-006, FR-015, FR-017 |
| 21 | With `--debug-text`, inspect the surface with Accessibility Inspector (macOS) and VoiceOver (iOS) | Only the 001 label "swiftSky game surface" is exposed. None of the test string's text is announced or listed as an element. | FR-020, 001 FR-009 |

### Release

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 13 | Build Release and launch it with `--debug-text-fill` | Uniformly black, with no text | SC-006, FR-016 |
| 14 | Inspect the Release binary with `nm` and `strings` | No `DebugTextPattern` or `debug-text` symbols or strings, while `TextBuffer` **is** present | FR-016, SC-006 |

### Performance and memory (Principle III)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 15 | Instruments → Allocations, a 60 s run with `--debug-text`, filtered to the frame-loop thread's draw path, using the same method as SKY-3 and SKY-4 | Zero allocations on our side in the draw path. This also settles research R5's stored-block question. | SC-003, FR-012 |
| 16 | The same with `--debug-text-fill` | Zero, and the instrumentation log shows `skipped=0` | SC-003, SC-004 |
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
| 15, 16 | **Not run** | The `xctrace record --template Allocations` recording failed to attach from the session, so Instruments needs to be run by hand. Indirect evidence: `skipped=0` in every run, so the instance ring never ran dry. |
| 17 | **Measured** (macOS, 60 Hz external display, budget 16.7 ms) | No text: mean 0.16 / worst 0.67 ms. `--debug-text`: 0.27 / 0.66 ms. `--debug-text-fill`: 0.69 / 1.79 ms. All with 0 skipped and 0 dropped. |
| 18 | **PASS** (macOS) | `phys_footprint`: 42 MB with no text, 42 MB with the test string, 42 MB with fill, and 43 MB with both arguments. The delta is ≤ 1 MB, within the 2 MB ceiling. |
| 19 | **PASS** | A forced `bitmapContextUnavailable` on the first frame logged `E … [com.swiftsky.app:text] text disabled: bitmapContextUnavailable`. The app kept rendering (0 skipped), with no failure notice and no crash. The temporary hook was removed, and the source was confirmed free of it. |
| 20 | **Not run** | Needs a failure forced after a display change, with a window moved by hand |
| 21 | **Not run** | Needs Accessibility Inspector and VoiceOver |
