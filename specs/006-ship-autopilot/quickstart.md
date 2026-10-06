# Quickstart & Validation Guide: Ship Autopilot

**Feature**: `006-ship-autopilot` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

How to verify every success criterion. Shapes are in [data-model.md](./data-model.md), the API and
law in [contracts/autopilot.md](./contracts/autopilot.md), the reasons in
[research.md](./research.md). The 001–005 checks still apply, unchanged.

## Prerequisites

The same as 004: Xcode 27, the iOS 26 and macOS 26 SDKs, the Metal toolchain component. Manual
checks 9–11 need an interactive device session.

## One-command verification

```bash
./Scripts/verify.sh
```

Usage unchanged; `swift test` now also runs `AutopilotTests`.

## Try it from a test

Nothing is visible. To watch a flight, run only the new suite:

```bash
swift test --build-system swiftbuild --filter Autopilot
```

---

## Validation matrix

### Automated (headless)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `./Scripts/verify.sh` | Exits 0; all existing and new tests pass; no `warning:` lines (the one exempt line only) | SC-009, FR-017 |
| 2 | `swift test --build-system swiftbuild` 10 times in a row | 10 identical passes | SC-009 |
| 3 | Arrival grid from rest: 5 distances × 16 directions | 100 % arrived, within 1 unit and < 1 unit/s | SC-001, US1-1, US1-2 |
| 4 | Same grid, time taken | ≤ 1.1 × reference + 0.5 s (reference from the ship's limits: turn in place, full burn, 180° coast flip, full brake). Worked example: 1,000 units facing the target, reference 4.72 s, bound 5.69 s, expected ≈ 5.1 s | SC-002, US1-4 |
| 5 | Same grid, overshoot along start → destination | ≤ 1 unit at every tick; the flip starts before halfway | SC-003, US1-3, US1-4 |
| 6 | Moving-start grid: ≥ 64 cases, speeds ≤ 1,000 u/s, 8 directions, distances 0–5,000 | 100 % arrived within 60 s; bearing sweep < 360°; ≤ 2 passes | SC-004, US2 |
| 7 | Re-order in each of aligning, burning, flipping, braking, arrived; same-destination re-order | Arrives at the new destination; no dependence on the old one after the switch | SC-006, US3 |
| 8 | Read-out and edges: no order; phase sequence from rest; distance remaining; non-finite order refused; already there; zero limits stay finite; explicit input keeps the order; n-at-once == one-at-a-time; tolerance sanitising and non-default tolerances | As in the contract | FR-002, FR-003, FR-005, FR-010, FR-011, FR-013, US4, Edge Cases |
| 9 | Station-keeping: 10,000 ticks after arrival | Within 1 unit and arrived throughout; final speed < 0.01 u/s, rate of turn 0; after a nudge out of tolerance it leaves arrived and arrives again | SC-008, US1-5, FR-009 |
| 10 | Determinism: moving start, re-ordered in burning, flipping and braking, ≥ 1,200 ticks with multi-tick advances, 10 runs | Byte-identical (`StateBits`) | SC-005, US5-1, US5-2 |

### Manual (running app)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 11 | Instruments → Allocations, 60 s Debug run on macOS and iOS (method of SKY-3, SKY-4) | Zero allocations on our side | SC-007, FR-015 |
| 12 | Frame time before (`main`) and after (this branch), 003 overlay mean/worst over 10 s | Both within budget; delta recorded | Principle III |
| 13 | Launch Debug, Debug `--no-debug-overlay`, Release, both platforms | Unchanged: overlay; black; black | SC-007, US5-3 |

### Headless before/after benchmark (always run)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 14 | As 004 check 11: a throwaway `-O` executable from `Sources/SwiftSkySimulation/*.swift` timing 10,000,000 single-tick `advance` calls with `ContinuousClock` and counting allocations with `malloc_zone_statistics`. `main`: no order. Branch: re-issuing a far order whenever it arrives, so every tick runs the law. 3 runs each | Branch: 0 allocations; ns per tick before/after recorded (expected well under 1 µs) | Principle III, FR-015, R10 |

## Evidence

Record results below as checks are run.

| # | Result | Notes |
|---|--------|-------|
| 1 | **PASS** 2026-10-01 | `./Scripts/verify.sh`: all stages PASS (metal compiler, swift build, no Metal device in tests, swift test, xcodebuild macOS, xcodebuild iOS), no `warning:` lines beyond the exempt swiftbuild line. `SwiftSkyRendering` and `SwiftSkyPlatform` unchanged against `main` |
| 2 | **PASS** 2026-10-01 | 10/10 consecutive `swift test --build-system swiftbuild` runs pass: 60 simulation (16 of them `Autopilot`), 62 rendering, 16 platform tests |
| 3–5 | **PASS** 2026-10-01 | `arrivesFromRest`: 80 cases (5 distances × 16 directions) arrive within 1 unit and < 1 u/s, inside SC-002's bound, overshoot ≤ 1, flip before halfway, phases in order. Examples: 1,000 units ahead 5.40 s (bound 5.69 s); 1,000 units behind 6.90 s (bound 7.34 s). `phaseSequenceFromRest` passes |
| 6 | **PASS** 2026-10-01 | `arrivesFromMovingStarts`: 96 cases (3 speeds × 4 distances × 8 directions) arrive within 60 s, bearing sweep < 360°, ≤ 2 passes; `namedMovingStarts` passes |
| 7 | **PASS** 2026-10-01 | `reorderInAnyPhase` (5 phases) and `sameDestinationAndRefusal` |
| 8 | **PASS** 2026-10-01 | `noOrder`, `readOut`, `alreadyThere`, `zeroLimits` (3 cases), `farDestination`, `exactlyBehindTurnsCounterClockwise`, `tolerances`, and batching / explicit input in `batchingExplicitInputAndCopies` |
| 9 | **PASS** 2026-10-01 | `keepsStation` (2 cases): arrived and within 1 unit for 10,000 ticks, final speed < 0.01 u/s, rate of turn 0; a 30-tick full-thrust nudge leaves arrived and it arrives again |
| 10 | **PASS** 2026-10-01 | `tenRunsAreIdentical`: 1,200-tick scenario with re-orders in burning, flipping and braking and 1/2/3/4-tick advances, byte-identical 10 times |
| 11 | **Not run** | Needs an Instruments session on each device (the method is still open as SKY-3 / SKY-4). Structural evidence: the law touches stored `Double`s only, and check 14 measured 0 allocations over 10 M ticks. The running app gives no order, so the law never runs there yet Method since 011: `specs/011-draw-allocation-counter/quickstart.md`, "The method" — an optimised build with the counter compiled in, no Instruments (011 R12); build it with `Scripts/build-instrumented.sh` (019); the former Profiling build carried no instrumentation (011 R1) and was removed (019). |
| 12 | **Not run** | Needs an interactive device session. Check 14 bounds the cost: ≤ 4 ticks × ~150 ns ≈ 0.6 µs per frame once orders exist (0.004 % of 16.67 ms); with no order, as in the app today, the extra cost is one `nil` check per tick |
| 13 | **Not run** (structural PASS) | No interactive launch in this session. No change to `SwiftSkyRendering` or `SwiftSkyPlatform`; the frame loop's `Simulation.advance(state, ticks:)` with no order is bit-identical to the neutral input (`noOrder` test), so nothing visible can differ |
| 14 | **PASS** 2026-10-01 | Apple Silicon Mac, `swiftc -O -wmo`, 10 M single-tick advances, 3 runs each. **Before** (`main`, no input): 5.12 / 4.02 / 4.18 ns per tick. **After** (every tick flown by the autopilot, re-ordered on arrival): 147.9 / 189.0 / 148.2 ns per tick — above the plan's < 100 ns estimate but well under the 1 µs expectation. **Allocations: 0** in every run; a control that allocates 1,000 arrays in the same window reports 1,003 blocks |

