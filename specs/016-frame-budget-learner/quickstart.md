# Quickstart & Validation Guide: Frame Budget That Does Not Lock Onto Stray Gaps

## Prerequisites

- Xcode 27, the repo at the feature branch, the iPhone 17 Pro simulator and a Mac (120 Hz built-in
  display; a 60 Hz external display for check 5).
- Debug builds (the summary's `budget=` field is instrumentation).

## One-command verification

```bash
./Scripts/verify.sh
```

Runs the learner's headless suite (contract C3) with every other suite, and builds both apps.

## Validation matrix

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `verify.sh` | All suites pass, both apps build, no warnings | SC-001, FR-008 |
| 2 | iOS simulator, Debug, Mac under load (e.g. `yes > /dev/null` on every core), 10 minutes; read the summaries with `xcrun simctl spawn <udid> log stream --predicate 'subsystem == "com.swiftsky.app"'` | `budget=16.666667ms` in every summary | SC-002 |
| 3 | macOS Debug on the 120 Hz display; live-resize the window for ~10 s | Every summary after the resize still `budget=8.333333ms` | SC-003 |
| 4 | macOS Debug, 120 Hz idle for 30 s | `budget=8.333333ms` | FR-008 #1 |
| 5 | macOS Debug, drag the window to a 60 Hz external display and wait 10 s | Every later summary `budget=16.666667ms` | SC-003 |
| 6 | 011 check 25 on the optimised instrumented build, 60 s | `allocs=0 allocframes=0` in every summary but the first | SC-004 |

## Notes

- Checks 2–6 need a person (simulator under load, window drags). The agent leaves them open.
- Launch macOS builds with `open -n <app>` so the window comes to the front.

## Results

Run on 2026-10-07, branch `016-frame-budget-learner`, by the agent (no simulator, no window drags).

| # | Result | Evidence |
|---|--------|----------|
| 1 | **PASS** | `./Scripts/verify.sh`: all stages green, both apps build in Debug, no warnings. The `Display interval learner` suite (16 tests: C3 series 1–7 and the floor, forget, rounding and residual-risk cases) runs in `swift test` with no Metal device. FR-010: the macOS app also builds in the Release configuration (`xcodebuild … -configuration Release CODE_SIGNING_ALLOWED=NO build`, exit 0); its only `warning:` line is Xcode's pre-existing "No App Category is set" target notice. |
| 2 | **LEFT FOR THE USER** | 10-minute Debug run on the loaded iOS simulator. |
| 3 | **LEFT FOR THE USER** | macOS live resize on the 120 Hz display. |
| 4 | **PASS** (2026-10-07) | macOS, Apple silicon Mac on its 120 Hz display, run from `main` after the merge. Built with `Scripts/build-instrumented.sh macos` (instrumented Release, 019), not Debug: the learner is the same code in both, and the summary line is compiled into both. 144 summaries from 09:07:47 to 09:13:38, every one `budget=8.333333ms`, including the first after launch. |
| 5 | **LEFT FOR THE USER** | macOS move to a 60 Hz display. |
| 6 | **PASS** (2026-10-07) | macOS, the same run as check 4 (`Scripts/build-instrumented.sh macos`, optimised instrumented build), about 6 minutes with clicks: `allocation counter ready`, then 144 summaries, every one `allocs=0 allocframes=0`. `eventallocs=` was 0 in 133 summaries and 1–2 in the 11 that applied a click (the event queue drain, which FR-004 of 011 reports apart and does not gate); `gfxallocs=1200` per 120 frames. The iOS half of 011 check 25 was not re-run. |
