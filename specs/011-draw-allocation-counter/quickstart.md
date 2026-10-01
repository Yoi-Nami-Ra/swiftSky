# Quickstart: Count Draw-Path Allocations and Verify Zero on iOS

Validation guide for [spec.md](./spec.md). The counter's API and the summary format are in
[contracts/allocation-counter.md](./contracts/allocation-counter.md).

## Prerequisites

- Xcode 27, the Metal toolchain, a clean checkout of this branch.
- The iPhone 17 Pro simulator (iOS 27.0), booted: `xcrun simctl boot "iPhone 17 Pro"`.
- Read logs with `/usr/bin/log` (in zsh a bare `log` is a shell builtin).

## The method — "the method of SKY-3"

This is the procedure SKY-4 and the later checks that cite this ticket follow.

1. **Build** the **Debug** configuration of the app for the destination. Debug is the only build that
   carries the frame instrumentation today; a Profiling build does not (research R1).
2. **Launch** it with the arguments the check names (none, for an idle run: the ship and the debug overlay
   are drawn). Leave it frontmost and untouched.
3. **Run** for the stated time (60 s for check 25), then quit.
4. **Read** the lines for the run:
   - Simulator: `xcrun simctl spawn booted log show --last 3m --style compact --predicate 'subsystem == "com.swiftsky.app" AND category == "frame"'`
   - Mac: `/usr/bin/log show --last 3m --style compact --predicate 'subsystem == "com.swiftsky.app" AND category == "frame"'`
5. **Decide** with the PASS rule in the contract:
   - `allocation counter ready` appears;
   - every summary but the first of the run (and the first after a `budget=` change) shows `allocs=0
     allocframes=0`.
   Record `eventallocs=` as reported, and `gfxallocs ÷ frames` (lowest and highest) as the framework's
   per-frame reference.
6. **If it fails**, `allocframes=` tells whether one frame or every frame allocates. Run the app under
   the debugger with a breakpoint on `sky_alloc_app_allocation` — the hook calls it for every app-side
   allocation it counts — and read the backtrace. Fix the source and repeat from step 1.

## Checks

| # | Check | Expected | Covers |
|---|-------|----------|--------|
| 1 | `./Scripts/verify.sh` | Every stage PASS, zero warnings, existing tests still pass | SC-006 |
| 2 | `swift test --filter AllocationCounter` 10 times in a row | Every run passes: N in {0, 1, 10, 1,000} counted exactly, other thread 0, framework stand-in only in `graphics`, outside a stretch 0, chaining | SC-001 |
| 3 | macOS Debug app, 10 s, method steps 1–4 | `allocation counter ready`; summaries with the four new fields after `ticks=`, existing fields unchanged | SC-002, US1 |
| 4 | iOS Debug app on the simulator, 10 s, method steps 1–4 | As check 3 | SC-002, US1 |
| 5 | Release builds of both apps, `nm` and `strings -a` on the executables | No `sky_alloc` symbols, no `allocs=` / `gfxallocs=` / `allocation counter` strings; 001 check 27's probes still 0 | SC-002, FR-009 |
| 6 | **Check 25 on iOS**: the method, simulator, Debug, no arguments, 60 s idle | PASS rule holds; `gfxallocs ÷ frames` recorded | SC-003, SC-004, US2 |
| 7 | Before/after: Debug builds of `main` and of this branch on the same simulator, 30 s idle each, overlay hidden in neither | After mean within 10% or 0.1 ms of before (whichever larger); `dropped=0` outside launch in both | SC-005 |
| 8 | 001's quickstart check 25 updated with the result and a pointer to "The method" above | Present; checks citing "the method of SKY-3" resolve to it | FR-012, FR-013, US3 |
| 9 | Read "The method" as a SKY-4 reader: can macOS be run from it alone? | Yes; no Instruments step | SC-007 |

## Results

| # | Date | Result | Evidence |
|---|------|--------|----------|
| 3 | 2026-10-01 | **PASS** | macOS Debug, Apple silicon Mac, 120 Hz: `allocation counter ready`, then e.g. `frames=235 skipped=0 dropped=0 mean=0.139693ms worst=0.766458ms budget=8.333333ms ticks=123 allocs=212 allocframes=120 eventallocs=0 gfxallocs=1320` — existing fields unchanged, four new ones after `ticks=` |
| 4 | 2026-10-01 | **PASS** | iPhone 17 Pro simulator (iOS 27.0), Debug: `allocation counter ready`, then e.g. `frames=233 skipped=0 dropped=0 mean=0.182022ms worst=2.123833ms budget=16.666667ms ticks=324 allocs=248 allocframes=89 eventallocs=0 gfxallocs=3360`. `log show` inside the simulator returns nothing here (it reports `getpwuid_r did not find a match for uid 502`); `log stream` works, so the method uses it |
| 5 | 2026-10-01 | **PASS** | Release builds of both apps (macOS executable and iOS-simulator executable): `nm` finds 0 `sky_alloc` symbols; `strings -a` finds 0 of `allocs=`, `gfxallocs=`, `allocation counter`, and 0 of 001 check 27's probes (`skipped=`, `dropped=`, `worst=`, `SWIFTSKY_INSTRUMENTATION`, and the `recordPresented`/`recordSkipped`/`updateBudget`/`summary` symbols) |
