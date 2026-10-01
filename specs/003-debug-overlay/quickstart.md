# Quickstart & Validation Guide: Live Debug Overlay

**Feature**: `003-debug-overlay` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

This guide covers how to run the overlay and verify every success criterion. Entity shapes are in
[data-model.md](./data-model.md), interfaces are in [contracts/debug-overlay.md](./contracts/debug-overlay.md),
and the reasons behind each decision are in [research.md](./research.md). The 001 and 002 checks still
apply. The ones that need a black surface now take `--no-debug-overlay` (check 10).

---

## Prerequisites

- The same as 002: Xcode 27, the iOS 26 and macOS 26 SDKs, and the Metal toolchain component.
- A Mac, and an iOS device or simulator. For check 7, the Mac needs a second display with a different
  refresh rate, or the display's refresh rate changed in System Settings → Displays.
- **Performance checks (13 and 14)**: before/after deltas on one device are valid on any hardware.
  Absolute baseline numbers wait for SKY-31 and SKY-32.

## Run it

| Build | How to launch |
|-------|---------------|
| macOS Debug | Xcode scheme **swiftSky (macOS)** → Run. No argument is needed. |
| macOS, overlay hidden | the same, with `--no-debug-overlay` under Edit Scheme → Run → Arguments |
| macOS built app | `open <path>/swiftSky.app`, or `open <path>/swiftSky.app --args --no-debug-overlay` |
| iOS | scheme **swiftSky (iOS)** → Run, or `xcrun simctl launch <device> <bundle-id> [--no-debug-overlay]` |

**Expected**: six lines of white text, 8 pt in from the top-left of the safe area, over black,
refreshing four times a second. For example, on a 120 Hz display:

```text
mean      0.41 ms     ← `--` for the first second
worst     0.97 ms
budget    8.33 ms     ← 16.67 on a 60 Hz display
dropped 0
skipped 0
ticks   61            ← rises 15 per refresh at the 60 Hz tick rate
```

## One-command verification

```bash
./Scripts/verify.sh
```

Its usage is unchanged. `swift test` now also runs the new `SwiftSkyPlatformTests` target, and the
headless guard covers it with the rest of `Tests/`.

---

## Validation matrix

### Automated (headless)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `./Scripts/verify.sh` | Exits 0, with the window, schedule, snapshot, decimal and overlay tests passing, and no `warning:` lines | FR-016, SC-007 |
| 2 | Run `swift test --build-system swiftbuild` 10 times in a row | 10 identical passes | SC-007 |
| 3 | The decimal tests cover the contract's table, including `0.005 → 0.01`, `1234.5` written in full, and NaN | Pass | FR-007 |
| 4 | The window and schedule tests cover: `--` until four buckets close; only the last four count; a 0.3 s frame stays the worst after a 0.3 s gap; a restart on visibility and on budget change; 40 ± 1 refreshes over 10 s at 60 Hz and at 120 Hz; no burst after a 2 s gap | Pass | FR-004, FR-006, FR-008, SC-002 |
| 5 | The overlay tests cover: six lines in order; every line ≤ 33 characters at the normal-range maxima; `UInt64.max` counts written in full; nothing drawn before the first snapshot | Pass | FR-004, FR-005 |

### Visible output

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 6 | macOS Debug, no argument. Watch for 10 s next to `log stream --predicate 'subsystem == "com.swiftsky.app" && category == "frame"' --level notice` | The overlay is drawn from the first second. Its budget, dropped and skipped values match the nearest log line, and `ticks` stays within one refresh of the log's `ticks=`. | SC-001, SC-003, FR-013 |
| 7 | Move the window to a display with a different refresh rate, or change the rate | `budget` changes to the new interval. `dropped` and `skipped` restart with the log's, and `mean` and `worst` show `--` for a second. | US1-4, FR-008 |
| 8 | Screen-record 10 s and count the changes in `ticks` | 38 to 42 | SC-002, FR-006 |
| 9 | iOS, no argument, rotated to both landscape orientations. On iPad, also enter Slide Over. | Always fully inside the safe area and never under the cutout. No line is cut off in Slide Over. | SC-001, US2, FR-005 |
| 10 | Debug with `--no-debug-overlay`: re-run 001 checks 1 to 6 and 002 check 12. Debug with `--debug-text`: re-run 002 checks 5 to 11. | Uniformly black, and the 001 checks pass. With `--debug-text`, the test string appears and the overlay does not. | SC-006, FR-011, FR-012 |
| 11 | Minimise the window (macOS) or background the app (iOS) for 5 s, then return | `mean` and `worst` read `--` for one second, then resume. There is no spike, and no burst of refreshes. | FR-008 |
| 12 | Accessibility Inspector (macOS) and VoiceOver (iOS) with the overlay showing | Only the 001 label "swiftSky game surface" is exposed | FR-010 |
| 17 | macOS: resize the window small and large, then enter and leave full screen | The overlay keeps its size in points and stays 8 pt in from the safe-area top-left | FR-003, US1-5 |

### Failure path

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 18 | 002 check 19's forced atlas failure, launched with **no** argument | The app runs, the surface is black, the text failure is logged, and the instrumentation's `frame` log lines continue | Edge case "Text renderer unavailable", 002 FR-018 |

### Performance (Principle III)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 13 | Instruments → Allocations, a 60 s run with no argument, on the frame-loop thread's draw path, using the method of SKY-3, SKY-4 and 002 check 15 | Zero allocations on our side, including on refresh frames | SC-004, FR-014 |
| 14 | Frame time over 60 s from the instrumentation log, with `--no-debug-overlay` and then with no argument, on the same device | Both within budget. Record both mean and worst here as the before/after pair. | SC-004 |

### Release

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 15 | Build Release and launch it with no argument, then with `--no-debug-overlay` and `--debug-text` | Uniformly black every time | SC-005, FR-009 |
| 16 | Check 27 of 001, extended: `nm` on the stripped (`strip -rSTx`) Release binary, then `strings` | Zero `DebugOverlay`, `FrameTimeWindow` and `OverlayRefreshSchedule` symbols. Zero `no-debug-overlay`, `dropped ` and `skipped ` strings. (Whether the linker keeps the unused `writeHundredths` does not matter: it holds no overlay text.) | SC-005, FR-009 |

## Evidence to record

Under each check, add the date, the device, the result, and any measured numbers (checks 6, 8, 13 and
14). If a check disproves an assumption in research.md, correct research.md.

### Evidence, 2026-09-30 (implementation session, Apple silicon MacBook Pro, 120 Hz built-in display, macOS 27, Xcode 27 RC)

This is non-baseline hardware, so the performance numbers are indicative only (SKY-31, SKY-32).
Window capture is refused in this session (Screen Recording is not granted), exactly as in 002, so
every check that needs eyes on the overlay is still open for a person.

| # | Result | Notes |
|---|--------|-------|
| 1 | **PASS** | `./Scripts/verify.sh`: the headless guard, `swift build`, `swift test` (23 simulation, 47 rendering and 16 platform tests), and both app builds are green, with no `warning:` apart from the exempted swiftbuild line |
| 2 | **PASS** | 10 of 10 consecutive `swift test --build-system swiftbuild` runs passed, with identical counts |
| 3 | **PASS** | `DecimalWritingTests`: every contract row, plus padding, full width, clamping, `limit` and capacity |
| 4 | **PASS** | `FrameTimeWindowTests` and `OverlayRefreshTests`: `--` for a full second; the last four buckets only; a 0.3 s frame survives its gap for exactly four closes; restarts on visibility and on budget change; 40 ± 1 refreshes over 10 s at 30, 60, 90 and 120 Hz; no burst after a 2 s gap; snapshot fields equal the counters; launch-argument precedence |
| 5 | **PASS** | `DebugOverlayTests`: six lines matching the contract's example; `--` alignment; ≤ 33 characters and < 128 in total at the normal-range maxima; `UInt64.max` in full; the anchor at inset + 8 pt; nothing before the first snapshot |
| 6 | **Partly done: log only** | Log unchanged in format and cadence: `frames=3954 skipped=0 dropped=0 mean=0.259593ms worst=4.872083ms budget=8.333333ms ticks=1990`. Comparing it with the overlay on screen still needs a person. |
| 7 | **Not run** | Needs the window moved to a display with another refresh rate. Covered structurally by `budgetChangeRestarts`. |
| 8 | **Not run (visual)** | Covered structurally by the 40 ± 1 refresh test (check 4) |
| 9 | **Not run** | The iOS Simulator did not respond: `simctl install` and `simctl listapps` hung for over 5 minutes on the booted iPhone 17 Pro, and it was not force-rebooted because another session's simulator was booted beside it. The iOS app **builds** (check 1). |
| 10 | **Not run (visual)** | Structural: `DebugTextMode` precedence is tested (check 4), and with `--no-debug-overlay` no overlay is created, so `TextBuffer` stays empty and no text is drawn |
| 11 | **Not run** | Needs a window minimised by hand. Covered structurally by `visibilityRestarts`. |
| 12 | **Not run** | Needs Accessibility Inspector and VoiceOver. No accessibility API is touched by this feature. |
| 13 | **Not run** | `xctrace record --template Allocations --launch` started, then never finished (stopped after 4 minutes, with a 56 KB trace), as in 002. It needs Instruments by hand. Indirect evidence: every write path is a `StaticString`, integer or inline-struct operation, and the frame logs show `skipped=0`. Method since 011: `specs/011-draw-allocation-counter/quickstart.md`, "The method" — an optimised build with the counter compiled in, no Instruments (011 R12); a Profiling build carries no instrumentation (011 R1). |
| 14 | **Measured** (macOS, 120 Hz, budget 8.33 ms, 60 s each, 7,314 frames) | `--no-debug-overlay`: mean **0.20 ms**, worst **4.78 ms**. Overlay showing: mean **0.29 ms**, worst **5.64 ms**. Both runs: 0 dropped, 0 skipped. The overlay costs about 0.09 ms per frame. |
| 15 | **PASS (structural)** | Release contains no overlay code at all (check 16), so no argument can draw it. A visual confirmation is still outstanding. |
| 16 | **PASS** | macOS Release binary (arm64), unstripped **and** after `strip -rSTx`: 0 `DebugOverlay`, 0 `FrameTimeWindow`, 0 `OverlayRefreshSchedule`, 0 `overlayStatistics`, 0 `restartOverlayWindow` and 0 `DebugTextPattern` symbols. `strings`: 0 `no-debug-overlay`, 0 `dropped `, 0 `skipped `, 0 `mean    `, 0 `budget  `, 0 `ticks   ` and 0 `debug-text`. `writeHundredths` is kept (1 symbol), as expected: it is text capability, with no overlay text. |
| 17 | **Not run** | Needs a person to resize the window and use full screen |
| 18 | **PASS (partly)** | A temporary `throw .bitmapContextUnavailable` at the top of `GlyphAtlasBitmap.make`, launched with no argument, logged `E … [com.swiftsky.app:text] text disabled: bitmapContextUnavailable`. The app kept running with no notice and no crash. The hook was reverted, and `git status` confirms the file is clean. The `frame` lines' continuing could not be shown: by then the display had gone idle, and an unmodified build logged no `frame` lines either. |
