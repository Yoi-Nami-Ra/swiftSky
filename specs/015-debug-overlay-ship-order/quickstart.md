# Quickstart & Validation Guide: Ship and Order Lines on the Debug Overlay

## Prerequisites

- Xcode 27, the repo at the feature branch, the iPhone 17 Pro simulator and a Mac.
- Debug builds for the visual checks (the overlay is on by default). For allocation counting, the
  optimised instrumented build of 011 ("The method" in `specs/011-draw-allocation-counter/quickstart.md`).

## One-command verification

```bash
./Scripts/verify.sh
```

Runs every headless suite, including the signed writer (contract C1) and the overlay's new lines (C2,
C3), and builds both apps.

## Validation matrix

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `verify.sh` | All suites pass, both apps build, no warnings | FR-013, SC-006 |
| 2 | iOS Debug, no arguments; screenshot | Six 003 lines, then `pos`/`vel` at `0.00`, `speed 0.00 u/s`, `heading 0.00 deg`, `turn 0.00 deg/s`, `order   none`; all inside the safe area | SC-001, FR-001–FR-004 |
| 3 | iOS Debug, `--debug-ship-spin`; two screenshots a second apart | `turn` reads `180.00 deg/s`; heading differs between the shots and stays in −179.99…180.00; position `0.00` | SC-003, FR-002 |
| 4 | iOS Debug, tap a point; screenshots during the flight and after arrival | `order` line with a phase, `dest` equal to the log's `order … world=` to two decimals, `dist` falling; after arrival `order   arrived`, `dist` ≤ 1.00 | SC-002, FR-003 |
| 5 | iOS Debug, tap a second point mid-flight | `dest` changes to the new point at the next refresh | FR-003 |
| 6 | macOS Debug, no arguments, then click a point | As checks 2 and 4, in the window's top-left | SC-001, SC-002 |
| 7 | `--no-ship`, `--no-interpolation` (Debug) | Ship and order lines still shown; values unchanged in meaning | Edge cases |
| 8 | `--no-debug-overlay`, `--debug-text` (Debug) | No overlay lines at all / the test string only | 003 FR-011, FR-012 |
| 9 | 011 check 25, optimised instrumented build, iOS simulator, 60 s with orders flown; the same on `main` (d6f004e) for the before figures | `allocation counter ready`; `allocs=0 allocframes=0` in every summary but the first; mean/worst frame time recorded before and after (Principle III) | SC-004, FR-010 |
| 10 | Same as 9 on macOS: idle with `--debug-ship-spin` (no order); with clicked orders by hand | Same | SC-004 |
| 11 | Plain Release build for macOS, as 003 check 16: `nm` on the binary, unstripped and after `strip -rSTx`; `strings` | 0 `DebugOverlayShip` symbols; 0 of `pos     x`, `heading `, ` deg/s`, ` u/s`, `order   `, `dest    x` | SC-005, FR-009 |

## Notes

- **Simulator**: install and launch with `xcrun simctl install <udid> <app>` and
  `xcrun simctl launch <udid> com.swiftsky.app [arguments]`; screenshot with
  `xcrun simctl io <udid> screenshot <file>.png`; read the order lines with
  `xcrun simctl spawn <udid> log stream --style compact --predicate 'subsystem == "com.swiftsky.app"'`.
- **Phase names** are not part of check 11: they are `AutopilotPhase`'s case names, which Swift keeps in
  reflection metadata in every build (research R6).
- **macOS** checks need a person at the Mac (click, Screen Recording for screenshots).

## Results

Run on 2026-10-05, branch `015-debug-overlay-ship-order`, iPhone 17 Pro simulator (iOS 27, landscape)
unless noted.

| # | Result | Evidence |
|---|--------|----------|
| 2 | **PASS** | Debug, no arguments: `pos`/`vel` `x 0.00 y 0.00`, `speed 0.00 u/s`, `heading 0.00 deg`, `turn 0.00 deg/s` under `ticks`, then `order   none` and no `dest`/`dist`, all inside the safe area. |
| 3 | **PASS** | `--debug-ship-spin`: shots at ticks 167 and 258 read `heading 97.50 deg` and `10.50 deg`, `turn 180.00 deg/s`, position `0.00`. 91 ticks × 3°/tick = 273°, and 97.50 + 273 − 360 = 10.50: the screen agrees with the simulation exactly. |
| 4 | **PASS** | Taps with the simulator control tool. Order `world=(213, -81)`: after arrival the overlay read `order   arrived`, `dest x 213.00 y -81.00`, `dist 0.04 u`, `vel 0.00`. Order `world=(-317, 129)`: one shot read `burning`, `dist 540.81`, `speed 106.67` (= ‖(−99.16, 39.29)‖), the next `flipping`, `dist 244.86`, `turn 180.00 deg/s`. `dest` equalled the log's `world=` to two decimals each time. |
| 5 | **PASS** | Two taps 20 ms apart: the log shows order `(343, 129)` then `(-317, -121)`; the next refresh showed `dest x -317.00 y -121.00`, and the first order never reached the screen. A re-order from rest read `flipping` straight away, with `vel 0.00`: the autopilot's own phase, probably from a station-keeping velocity under 0.005 u/s pointing away from the new target. That is logic-layer behaviour (006), not the overlay's, and is reported as is. |
| 6 | **LEFT FOR THE USER** | macOS: needs clicks by hand. |
| 7 | **PASS** | `--no-ship --no-interpolation`: no sprite drawn; after a tap the overlay read `order   aligning`, `turn 156.00 deg/s`, `dest x -317.00 y 129.00`, `dist 342.24 u`. |
| 8 | **PASS** (2026-10-05, rerun) | iPhone 17 Pro simulator, Debug. No argument: 12 lines — the six frame lines, then `pos`, `vel`, `speed`, `heading`, `turn` at zero and `order   none`. `--no-debug-overlay`: no text at all; the only non-black pixels (7,469) lie in a 115 × 120 px box at the centre, the ship. `--debug-text`: the test string and its `fps` line only, no overlay line. |
| 9 | **PASS** (before and after) | Before (`main` d6f004e, optimised instrumented build, iOS simulator, 60 s, 3 orders flown by taps): `allocation counter ready`; 21 summaries, all `allocs=0 allocframes=0`, `eventallocs` 0–1; mean 0.10–0.52 ms, worst 85.4 ms (a simulator hitch during a tap; 8 dropped). After (this branch, same build settings, iPhone 17 Pro, debug overlay shown, 2026-10-05 rerun after the earlier simulator freeze): `allocation counter ready`; 5 orders by tap, 5 arrivals, 20 summaries — the first `allocs=1 allocframes=1` (start-up, excluded by 011), every later one `allocs=0 allocframes=0`, `eventallocs` 0–1; mean 0.09–0.18 ms, worst 84.5 ms (a simulator hitch; 3 dropped). The new lines cost no allocation and no measurable frame time. The Debug build's counts (128–177 allocs per summary) are for information only, since Debug allocates in unspecialised iterators (011 R1). |
| 10 | **PASS (idle); orders left for the user** | macOS optimised instrumented build, `open -n … --args --debug-ship-spin`, 65 s, no order, so the heading line changed at every refresh: `allocation counter ready`; 31 summaries, all `allocs=0 allocframes=0 eventallocs=0`; mean 0.20–0.21 ms, worst 1.03 ms, budget 16.67 ms, 0 dropped. The run with clicked orders needs a person at the Mac. |
| 11 | **PASS** | Plain Release build for macOS (arm64), unstripped and after `strip -rSTx`: 0 `DebugOverlayShip`, 0 `DebugOverlay`, 0 `headingDegrees` symbols (with 172 `Renderer` and 6 hundredths-writer symbols present, so symbols are readable). `strings`: 0 `pos     x`, 0 `heading `, 0 ` deg/s`, 0 ` u/s`, 0 `order   `, 0 `dest    x`, 0 `dist    `, 0 `no-debug-overlay`. `aligning`: 1, the `AutopilotPhase` case name in reflection metadata, as expected (research R6). |
| 1 | **PASS** | `./Scripts/verify.sh` green. Tests 246 → 266 (rendering suite 97 → 117), with no Metal device. |

