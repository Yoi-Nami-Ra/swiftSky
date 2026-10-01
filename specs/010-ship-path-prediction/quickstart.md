# Quickstart & Validation Guide: Predict the Ship's Planned Path

**Feature**: `010-ship-path-prediction` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

How to verify every success criterion. Shapes are in [data-model.md](./data-model.md), the API, the
prediction and the log fields in [contracts/planned-path.md](./contracts/planned-path.md), the reasons
in [research.md](./research.md). The 001–009 checks still apply, unchanged.

## Prerequisites

The same as 009: Xcode 27, the iOS 26 and macOS 26 SDKs, the Metal toolchain component. Manual checks
10–13 need an interactive session on each platform.

## One-command verification

```bash
./Scripts/verify.sh
```

Usage unchanged; `swift test` now also runs `PlannedPathTests`.

## Try it

Nothing new is drawn. To run only the new suite:

```bash
swift test --build-system swiftbuild --filter PlannedPath
```

To watch predictions in the running app, launch a Debug build and stream the log (in zsh, `log` is a
builtin, so use the full path):

```bash
/usr/bin/log stream --predicate 'subsystem == "com.swiftsky.app" AND category == "frame"'
```

Each click or tap prints an `order … predicted=(x, y) ticks=N points=P arrives=yes` line, and the
ship's arrival prints `arrived world=(x, y) ticks=N` with the same point and tick.

---

## Validation matrix

### Automated (headless)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `./Scripts/verify.sh` | Exits 0; all existing and new tests pass; no `warning:` lines (the one exempt line only) | SC-008, FR-013 |
| 2 | `swift test --build-system swiftbuild` 10 times in a row | 10 identical passes | SC-008 |
| 3 | Predictions over 006's rest grid: 5 distances × 16 directions | Each path starts on the ship's position at the order's tick; every point equals, bit for bit, the real flight's position at its assigned tick; the last point and `endTick` are the first `arrived` state's; `reachesArrival` | SC-001, SC-002, US1-1, US1-3 |
| 4 | The same over 006's moving-start grid (3 speeds × 4 distances × 8 directions) and its named cases | As check 3, including passes, turn-backs and sideways corrections | SC-001, SC-002, US1-2 |
| 5 | Thinning: a path fed one synthetic position per tick for every flight length 0…3,700 | `count ≤ 256` always; `n ≤ 255` ticks → `n + 1` points at spacing 1; longer → 128–256 points, evenly spaced apart from the last; the last point is the last position fed; tick assignment as in the data model | SC-003, FR-004, FR-005, US2-1, US2-2 |
| 6 | Capped flights: zero thrust; zero angular acceleration facing away from the destination | Ends on the real position after exactly 3,600 ticks, `reachesArrival == false`, 226 points at spacing 16; every prediction in the suite has `endTick − startTick ≤ 3,600` | SC-004, FR-006, US2-3 |
| 7 | Per order: advance 1…1,000 ticks with and without explicit input; re-order mid-flight and to the same destination; refused order; no order; already there; ship, autopilot and tick count after `setOrder` as without this feature | Path unchanged by advances; replaced by the new prediction; whole state unchanged on refusal; empty without an order; one point when already there; FR-009 holds | SC-005, FR-007–FR-009, US1-4, US3-1–US3-3, Edge Cases |
| 8 | 006's ten-run determinism scenario, `StateBits` now including the path | Byte-identical, paths included | SC-006, FR-010, US3-4 |

### Headless before/after benchmark (always run)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 9 | As 006 check 14: a throwaway `-O -wmo` executable from `Sources/SwiftSkySimulation/*.swift`, timed with `ContinuousClock`, allocations counted with `malloc_zone_statistics`, 3 runs each: (a) a capped prediction (zero-thrust ship) and a 1,000-unit prediction from rest, 1,000 times each; (b) 10,000,000 single-tick `advance` calls on `main` and on this branch | (a) capped < 1 ms per prediction (expected ≈ 0.6 ms), 1,000-unit ≈ 60 µs; 0 allocations. (b) Per-call cost before/after recorded (the state grows to ~4.2 KB); 0 allocations | SC-007, FR-011, Principle III, R10 |

### Manual (running app)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 10 | Instruments → Allocations, 60 s Debug run on macOS and iOS, an order every second (method of SKY-3, SKY-4) | Zero allocations on our side, including the frames that apply an order | SC-007, FR-011 |
| 11 | Profiling build (optimised, with the overlay), an order every second for 60 s on each platform; watch the overlay's dropped-frame count | No drop when an order is given; frame time before (`main`) and after recorded | SC-007, Principle III |
| 12 | Launch Debug, Debug `--no-debug-overlay`, Release, both platforms; give a few orders | Exactly as 009: overlay; black with the ship; the ship flies, nothing new is drawn | SC-007, US3-5 |
| 13 | Debug build on each platform with the log streaming; 10 orders, each flown to arrival | Each `order` line's `predicted=` and `ticks=` equal the next `arrived` line's `world=` and `ticks=` (or the arrival line is a few ticks later, on a catch-up frame); `arrives=yes`; Release logs nothing | SC-009, FR-014, US1-5 |

## Evidence

Record results below as checks are run.

| # | Result | Notes |
|---|--------|-------|
| 1 | **PASS** 2026-10-01 | `./Scripts/verify.sh`: all stages PASS (metal compiler, ship.png identity, swift build with the layer boundary, no Metal device in tests, swift test, xcodebuild macOS, xcodebuild iOS), no `warning:` lines beyond the exempt swiftbuild line. `SwiftSkyRendering`, `Package.swift` and `verify.sh` unchanged against `main` |
| 2 | **PASS** 2026-10-01 | 10/10 consecutive `swift test --build-system swiftbuild` runs pass: 72 simulation (12 of them `Planned path`), 84 rendering, 34 platform tests |
| 3–4 | **PASS** 2026-10-01 | `matchesTheRealFlightFromRest`: 80 cases (5 distances × 16 directions); `matchesTheRealFlightFromMovingStarts`: 96 cases (12 × 8 directions); `namedMovingStarts` (4) and `alreadyThere`. Every point equals the real flight's position at its assigned tick, bit for bit; every path ends on the first arrived state's position and tick |
| 5 | **PASS** 2026-10-01 | `thinningAtEveryLength`: all 3,701 lengths (0…3,700 ticks): ≤ 256 points; every tick for ≤ 255 ticks; ≥ 128 points beyond; power-of-two spacing; every point at its assigned tick; last point is the final position, within one spacing of the one before |
| 6 | **PASS** 2026-10-01 | `cappedFlight` (zero thrust; zero angular acceleration facing away): `reachesArrival == false`, 3,600 ticks, 226 points at spacing 16, last point bit-identical to the real state after 3,600 ticks. The work bound (`endTick − startTick ≤ 3,600`) is asserted on all 182 grid predictions |
| 7 | **PASS** 2026-10-01 | `advancingLeavesThePath` (1, 7, 60, 333, 1,000 ticks, with and without explicit input), `reorderReplacesThePath` (mid-flight and same destination, start ticks 120 and 180), `refusedOrderLeavesTheState` (three non-finite destinations), `noOrderNoPath`, `predictingChangesNothingElse`, `alreadyThere` |
| 8 | **PASS** 2026-10-01 | 006's `tenRunsAreIdentical` now compares paths through `bits(_ state:)`; `determinismScenarioHasAPath` confirms its final state carries one. 006's `reorderInAnyPhase` also compares whole states, so it now checks that a re-order's path does not depend on the old order |
| 9 | **PASS** 2026-10-01 | Apple Silicon Mac, `swiftc -O -wmo`, 3 runs each, allocations counted through libmalloc's `malloc_logger` hook, which also counts transient allocations (control: 1,000 transient arrays counted as 1,115). **Prediction**: capped (3,600 ticks) 104.1 / 87.8 / 87.5 µs; 1,000 units from rest 37.2 / 36.8 / 36.9 µs; `setOrder(to:)` with its prediction 37.6 / 36.9 / 37.3 µs; **0 allocations** in all. **advance, 10 M single-tick calls**: no order, `main` 5.32 / 3.79 / 3.81 ns, branch 3.89 / 3.80 / 3.79 ns; order flown, `main` 30.2 / 29.8 / 29.9 ns, branch 30.1 / 29.7 / 29.8 ns; 0 allocations. `SimulationState` 114 → 4,249 bytes (`PlannedPath` 4,129). With whole-module optimisation the larger copy costs nothing measurable; across the module boundary in the app it is at most one ~4 KB copy per frame |
| 10 | **Not run** | Needs an Instruments session on each device (the method is still open as SKY-3 / SKY-4). Evidence instead: inline storage only (R2); check 9 counts 0 allocations, transient ones included, for predictions, `setOrder` and `advance`; the log line captures scalars, never the path |
| 11 | **Partial** 2026-10-01 | Not run in a Profiling build on a device. On the iOS Simulator, a **Debug** (`-Onone`) build over the check 13 session — 11 orders, 19,435 frames — reported `dropped=0 skipped=0` in all 162 summaries, worst frame 4.24 ms against a 16.67 ms budget. A capped prediction in an optimised build is 0.1 ms (check 9) |
| 12 | **PASS** (iOS Simulator) 2026-10-01 | Debug: overlay and ship, the ship flies to each tap, nothing else drawn. Debug `--no-debug-overlay`: black with the ship, order still logged. Release: black with the ship, the ship flies to a tap, and no order or arrival line is logged. macOS not run (no event posting) |
| 13 | **PASS** (iOS Simulator) 2026-10-01 | Debug build on the iPhone 17 Pro simulator (iOS 27), 10 taps flown to arrival. All 10 order lines say `arrives=yes` (129–256 points). 3 arrival lines match `predicted=`/`ticks=` exactly (ticks 4436, 9241, 9843); 7 come one tick later, at the next tick's station-keeping position. The simulator delivers ~44 frames/s (120 frames ≈ 165 ticks in the summaries), so many frames advance two ticks and the once-per-frame arrival line lands late: SC-009's allowed difference. Confirmed by replaying the session offline from the log with the logic layer: each order's tick is found uniquely, the real flight first reports arrival on exactly the predicted tick in all 10, and each late arrival line's position is the replayed position at its tick. macOS not run: no event-posting access in this session (as 009) |
