# Quickstart: Count Draw-Path Allocations and Verify Zero on iOS

Validation guide for [spec.md](./spec.md). The counter's API and the summary format are in
[contracts/allocation-counter.md](./contracts/allocation-counter.md).

## Prerequisites

- Xcode 27, the Metal toolchain, a clean checkout of this branch.
- The iPhone 17 Pro simulator (iOS 27.0), booted: `xcrun simctl boot "iPhone 17 Pro"`.
- Read logs with `/usr/bin/log` (in zsh a bare `log` is a shell builtin).

## The method — "the method of SKY-3"

This is the procedure SKY-4 and the later checks that cite this ticket follow. It needs no Instruments.

1. **Build** an **optimised build with the counter compiled in**: the Release configuration plus the
   instrumentation condition on the command line (research R12). The Debug configuration also carries
   the counter, but an unoptimised build allocates on every `for` loop over a range (the standard
   library's unspecialised iterator), so its counts say nothing about the shipped code; record them for
   information only. A Profiling build carries no instrumentation at all (research R1).

   ```sh
   # iOS simulator (for a Mac: -scheme "swiftSky (macOS)" -destination 'platform=macOS')
   xcodebuild build -project swiftSky.xcodeproj -scheme "swiftSky (iOS)" -configuration Release \
     -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath <dir> \
     'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION' \
     'GCC_PREPROCESSOR_DEFINITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION=1'
   ```

2. **Start reading the log before launching**, and launch with the arguments the check names (none, for
   an idle run: the ship and the debug overlay are drawn). Leave it frontmost and untouched.
   - Simulator — `log show` inside the simulator returns nothing on this machine, so stream instead:
     `xcrun simctl spawn <udid> log stream --style compact --predicate 'subsystem == "com.swiftsky.app" AND category == "frame"' > run.log &`,
     then `xcrun simctl install <udid> <dir>/Build/Products/Release-iphonesimulator/swiftSky.app` and
     `xcrun simctl launch <udid> com.swiftsky.app`.
   - Mac — launch `<dir>/Build/Products/Release/swiftSky.app/Contents/MacOS/swiftSky`, and afterwards
     read `/usr/bin/log show --last 3m --style compact --predicate 'subsystem == "com.swiftsky.app" AND category == "frame"'`
     (a bare `log` in zsh is a shell builtin).
3. **Run** for the stated time (60 s for check 25), then quit (`xcrun simctl terminate <udid>
   com.swiftsky.app`, or end the Mac process) and stop the stream.
4. **Read** the run's `allocation counter …` line and its summary lines.
5. **Decide** with the PASS rule in the contract:
   - `allocation counter ready` appears;
   - every summary but the first of the run (and the first after a `budget=` change) shows `allocs=0
     allocframes=0`.
   Record `eventallocs=` as reported, and `gfxallocs ÷ frames` (lowest and highest) as the framework's
   per-frame reference.
6. **If it fails**, `allocframes=` tells whether one frame or every frame allocates. Find the source with
   lldb on a running app, after start-up's one-off work (the glyph atlas alone makes thousands): start the
   app, wait a few seconds, then
   `lldb -p <pid> -b -o 'breakpoint set -n sky_alloc_app_allocation' -o continue -o 'bt 14' -o continue …`
   — the hook calls `sky_alloc_app_allocation` for every app-side allocation it counts. Fix the source
   and repeat from step 1.

## Checks

| # | Check | Expected | Covers |
|---|-------|----------|--------|
| 1 | `./Scripts/verify.sh` | Every stage PASS, zero warnings, existing tests still pass | SC-006 |
| 2 | `swift test --filter AllocationCounter` 10 times in a row | Every run passes: N in {0, 1, 10, 1,000} counted exactly, other thread 0, framework stand-in only in `graphics`, outside a stretch 0, chaining | SC-001 |
| 3 | macOS Debug app, 10 s, method steps 1–4 | `allocation counter ready`; summaries with the four new fields after `ticks=`, existing fields unchanged | SC-002, US1 |
| 4 | iOS Debug app on the simulator, 10 s, method steps 1–4 | As check 3 | SC-002, US1 |
| 5 | Release builds of both apps, `nm` and `strings -a` on the executables | No `sky_alloc` symbols, no `allocs=` / `gfxallocs=` / `allocation counter` strings; 001 check 27's probes still 0 | SC-002, FR-009 |
| 6 | **Check 25 on iOS**: the method, simulator, optimised instrumented build, no arguments, 60 s idle | PASS rule holds; `gfxallocs ÷ frames` recorded | SC-003, SC-004, US2 |
| 7 | Before/after: optimised instrumented builds of `main` and of this branch on the same simulator, 30 s idle each | After mean within 10% or 0.1 ms of before (whichever larger); `dropped=0` outside launch in both | SC-005 |
| 8 | 001's quickstart check 25 updated with the result and a pointer to "The method" above | Present; checks citing "the method of SKY-3" resolve to it | FR-012, FR-013, US3 |
| 9 | Read "The method" as a SKY-4 reader: can macOS be run from it alone? | Yes; no Instruments step | SC-007 |

## Results

| # | Date | Result | Evidence |
|---|------|--------|----------|
| 3 | 2026-10-01 | **PASS** | macOS Debug, Apple silicon Mac, 120 Hz: `allocation counter ready`, then e.g. `frames=235 skipped=0 dropped=0 mean=0.139693ms worst=0.766458ms budget=8.333333ms ticks=123 allocs=212 allocframes=120 eventallocs=0 gfxallocs=1320` — existing fields unchanged, four new ones after `ticks=` |
| 4 | 2026-10-01 | **PASS** | iPhone 17 Pro simulator (iOS 27.0), Debug: `allocation counter ready`, then e.g. `frames=233 skipped=0 dropped=0 mean=0.182022ms worst=2.123833ms budget=16.666667ms ticks=324 allocs=248 allocframes=89 eventallocs=0 gfxallocs=3360`. `log show` inside the simulator returns nothing here (it reports `getpwuid_r did not find a match for uid 502`); `log stream` works, so the method uses it |
| 5 | 2026-10-01 | **PASS** | Release builds of both apps (macOS executable and iOS-simulator executable): `nm` finds 0 `sky_alloc` symbols; `strings -a` finds 0 of `allocs=`, `gfxallocs=`, `allocation counter`, and 0 of 001 check 27's probes (`skipped=`, `dropped=`, `worst=`, `SWIFTSKY_INSTRUMENTATION`, and the `recordPresented`/`recordSkipped`/`updateBudget`/`summary` symbols) |
| 6 | 2026-10-01 | **PASS** | iPhone 17 Pro simulator (iOS 27.0), optimised instrumented build (R12), no arguments, 60 s idle, read with `log stream`: `allocation counter ready`, then 21 summaries, every one `allocs=0 allocframes=0 eventallocs=0` — first `frames=116 … allocs=0 allocframes=0 eventallocs=0 gfxallocs=3248`, last `frames=2516 skipped=0 dropped=0 mean=0.213621ms worst=2.614417ms budget=16.666667ms ticks=3556 allocs=0 allocframes=0 eventallocs=0 gfxallocs=3360`. Framework reference: `gfxallocs ÷ frames` = 28.0 in every summary (lowest 28.0, highest 28.0). The simulator presented about 42 frames a second under host load (120 frames per ~2.8 s) with `dropped=0`. For information, the Debug build on the same simulator: `allocs=202–266 allocframes=83–93` per summary, all from unspecialised `for`-loop iterators (R12). Before the fix (T011), the optimised build on macOS reported `allocs=120 allocframes=120` per 120 frames: the text renderer's completion handler (R13) |
| 7 | 2026-10-01 | **PASS** | Same simulator, optimised instrumented builds, 30 s idle each. Before (`main` 0edd3a0): `frames=1194 skipped=0 dropped=0 mean=0.196387ms worst=1.731750ms`. After (this branch): `frames=958 skipped=0 dropped=0 mean=0.130642ms worst=5.581958ms`. After mean is 0.066 ms lower, inside the 0.1 ms allowance; `dropped=0` in both. The worst frame differs by one start-up outlier; the lower mean is consistent with the text ring no longer creating a block per frame |
| 8 | 2026-10-01 | **PASS** | 001's quickstart check 25 records the iOS PASS with its figures and points to "The method"; its open-checks table row reads "iOS PASS (011); the macOS run is SKY-4". Each check that cited "the method of SKY-3" — 002 #15, 003 #13, 004 #8, 006 #11, 008 #12, 010 #10 — now has a pointer to "The method" in its result, its status unchanged |
| 9 | 2026-10-01 | **PASS** | Read as a SKY-4 reader: step 1 gives the macOS build (scheme and destination swapped), step 2 the Mac launch and `/usr/bin/log show` query, steps 5–6 the PASS rule and the lldb attach. Every step was run on macOS in this session (the optimised macOS runs of T011); none needs Instruments |

