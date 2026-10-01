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
