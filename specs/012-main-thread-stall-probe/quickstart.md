# Quickstart: Measure Main-Thread Stalls and Verify Continuous Resize Under Thread Sanitizer

## Prerequisites

- A Mac with Xcode 27.0; the development Mac is an Apple M1 Pro, macOS 26.7, 120 Hz display.
- A person at the Mac for the drags (the session cannot drive the UI: Accessibility permission is not
  granted).
- Read the summaries with `/usr/bin/log` (in zsh a bare `log` is a builtin).

## The drag procedure

Formats and PASS rules are in [contracts/main-thread-stall-probe.md](./contracts/main-thread-stall-probe.md).

1. **Build** the two apps into separate derived-data folders:

   ```sh
   # Thread Sanitizer (Debug, which carries the instrumentation)
   xcodebuild build -project swiftSky.xcodeproj -scheme "swiftSky (macOS)" -configuration Debug \
     -destination 'platform=macOS' -derivedDataPath <tsan-dir> -enableThreadSanitizer YES
   # Optimised with the instrumentation (011 research R12)
   xcodebuild build -project swiftSky.xcodeproj -scheme "swiftSky (macOS)" -configuration Release \
     -destination 'platform=macOS' -derivedDataPath <opt-dir> \
     'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION' \
     'GCC_PREPROCESSOR_DEFINITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION=1'
   ```

2. **Launch** one app with its standard error saved (the sanitizer writes there), no arguments:
   `<dir>/Build/Products/<Debug|Release>/swiftSky.app/Contents/MacOS/swiftSky 2> stderr.txt &`
3. **Wait** for the second summary (about 2 s at 120 Hz), so start-up is over.
4. **Drag** a window corner continuously for at least 10 seconds: keep the button down and the corner
   moving, growing and shrinking the window between near its minimum size and most of the screen.
5. **Wait** for two more summaries, then quit the app (Command-Q).
6. **Read**: `/usr/bin/log show --last 3m --style compact --predicate 'subsystem == "com.swiftsky.app" AND category == "frame"'`,
   keeping only the app's own process id (another swiftSky may be running). Find `live resize began`
   and `live resize ended`; the covering summaries are those after the first, up to and including the
   first one after the second. For the sanitizer build, also count `WARNING: ThreadSanitizer` in
   `stderr.txt`.
7. **Decide** with contract C6. On a stall, repeat the drag with `sample <pid> 5 -file sample.txt` running
   and record what the main thread was doing.

## Checks

| # | Check | Expected | Covers |
|---|-------|----------|--------|
| 1 | `Scripts/verify.sh` | Passes; the new tracker and figures tests run headlessly; 10 consecutive runs of the new suites pass | SC-001, SC-007 |
| 2 | Debug build, idle 10 s, then a 5 s drag | Summaries end with `mainworst=…ms mainover=…`; idle summaries after the first have `mainover=0`; the drag is bracketed by the two markers and reads as short stretches (no `mainworst` near the drag's length — research R2) | SC-002, FR-013 |
| 3 | Debug build with `--debug-main-stall` | The summary after the 5 s mark has `mainworst` ≥ 50 ms and `mainover` ≥ 1; the others after the first have `mainover=0` | SC-002 |
| 4 | Release build, `nm` and `strings -a` | 0 of `mainworst=`, `mainover=`, `live resize`, `--debug-main-stall`, `MainThreadStallProbe` | SC-002, FR-008 |
| 5 | Thread Sanitizer build, the drag procedure | 0 data races; summaries throughout the drag; stall figures recorded for information | SC-003 |
| 6 | Optimised instrumented build, the drag procedure | Every covering summary `mainover=0`, `mainworst` ≤ `budget=` | SC-004 |
| 7 | Optimised instrumented builds of `main` and this branch, idle 30 s each | Mean frame time within 10% or 0.1 ms; `dropped=0` outside launch | SC-005 |
| 8 | Optimised instrumented build, idle 60 s, 011's method | `allocs=0 allocframes=0` in every summary after the first | SC-006 |
| 9 | 001's quickstart | Check 29's result and its open-checks row updated (FR-011) | FR-011 |

## Results

| # | Date | Result | Evidence |
|---|------|--------|----------|
| 1 | 2026-10-01 | **PASS** | `Scripts/verify.sh`: VERIFICATION PASSED (layer boundary, headless tests with no Metal device, both app builds, no warnings). The new suites — busy stretch tracker (4), stall figures (6), stall probe (3), `DebugMainStall` (1) — 14 tests, passed on 10 of 10 consecutive runs |
| 4 | 2026-10-01 | **PASS** | Release build of `swiftSky (macOS)`: `strings -a` and `nm` find 0 of `mainworst=`, `mainover=`, `live resize`, `--debug-main-stall`, `MainThreadStallProbe`, `DebugMainStall` (and 0 of `frames=`) |
| 2 | 2026-10-01 | **PASS** (mechanics); idle stalls in Debug recorded | Debug build, Apple M1 Pro, macOS 26.7, 120 Hz. Summaries end with `mainworst=…ms mainover=…`. A 9.3 s drag (`live resize began` 22:40:35.006 → `live resize ended` 22:40:44.299) read as short stretches — mid-drag `mainworst` 5.3–8.1 ms, never near the drag's length, so the tracking mode is measured (research R2). Idle in the Debug build: occasional system-side stretches of 14–45 ms; a sample put them in window-server Space-change handling (`MBDisplays::ActiveSpaceChanged`) and Core Animation commits, with none of the app's code on the stack. Idle in the optimised build (check 8): `mainover=0` in all 62 summaries |
| 3 | 2026-10-01 | **PASS** | Debug build with `--debug-main-stall`: the summary covering the 5 s mark reported `mainworst=50.049000ms mainover=1` |
| 5 | 2026-10-01 | **PASS** | Thread Sanitizer build, an 18.2 s continuous drag (22:52:14.918 → 22:52:33.122) by hand: **0 data races** (standard error empty), a summary every second throughout, `dropped=2` unchanged by the drag. Stall figures for information: mid-drag `mainworst` 7.2–13.3 ms, 33.9 ms at release. The first attempt found two defects, both fixed before this run (research R12, R13) |
| 6 | 2026-10-01 | **FAIL at release only** (system code); mid-drag PASS | Optimised instrumented build. First run (drag 3, 17.8 s): 6 of 17 mid-drag summaries over the interval (8.8–24.3 ms) and 29.2 ms at release; a sample put ~205 ms of the main thread's drag work in the app's `setFrameSize` → `CAMetalLayer.setDrawableSize` (synchronous drawable teardown). Fixed (research R14). Re-run (drag 5, 14.9 s, 23:14:24.428 → 23:14:39.321): all **15 mid-drag summaries `mainover=0`, `mainworst` 2.7–6.7 ms** against `budget=8.333333ms`; the first summary after `live resize ended`: `mainworst=15.354000ms mainover=1`. A sampled repeat (drag 6) put ~30 ms of 2.0 s of main-thread work in the app's code (mostly the instrumentation itself), none of it able to make that stretch; `_endLiveResize` 2 ms; the rest is AppKit, SwiftUI hosting layout and Core Animation commits. Recorded as a FAIL caused wholly by system code (spec Clarifications), follow-up SKY-37. Nothing looked wrong on screen during the drags (reported by the person dragging) |
| 7 | 2026-10-01 | **PASS** | Idle 30 s on the same Mac. Before: `main` (`2f88a12`) plus only the paused-loop fix (R13) — unpatched `main` stays paused at launch and writes no summary. At 3,717 frames: before `mean=0.185138ms dropped=0`, after (this branch) `mean=0.184395ms dropped=0` |
| 8 | 2026-10-01 | **PASS** | Optimised instrumented build, idle 62 s, 011's method: `allocation counter ready`, then all 62 summaries after the first `allocs=0 allocframes=0 eventallocs=0`; `gfxallocs÷frames` 10.0 (1,172–1,209 per 120 frames); `mainover=0` in every summary |
| 9 | 2026-10-01 | **PASS** | 001's quickstart check 29 and its open-checks row updated |
