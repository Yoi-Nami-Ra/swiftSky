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
| 9 | As 006 check 14: a throwaway `-O -wmo` executable from `Sources/SwiftSkySimulation/*.swift`, timed with `ContinuousClock`, allocations counted with `malloc_zone_statistics`, 3 runs each: (a) a capped prediction (zero-thrust ship) and a 1,000-unit prediction from rest, 1,000 times each; (b) 10,000,000 single-tick `advance` calls on `main` and on this branch | (a) capped < 1 ms per prediction (expected ≈ 0.6 ms), 1,000-unit ≈ 60 µs; 0 allocations. (b) Per-call cost before/after recorded (the state grows to ~4.3 KB); 0 allocations | SC-007, FR-011, Principle III, R10 |

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
| 1 | | |
| 2 | | |
| 3–4 | | |
| 5 | | |
| 6 | | |
| 7 | | |
| 8 | | |
| 9 | | |
| 10 | | |
| 11 | | |
| 12 | | |
| 13 | | |
