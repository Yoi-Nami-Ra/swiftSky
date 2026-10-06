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

(to be filled during implementation)
