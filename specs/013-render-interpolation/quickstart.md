# Quickstart & Validation Guide: Interpolate Rendering Between Simulation Ticks

How to verify 013. Data shapes are in [data-model.md](./data-model.md), the API in
[contracts/ship-pose.md](./contracts/ship-pose.md), and design reasons in [research.md](./research.md).

## Prerequisites

- Xcode with the iOS 26 / macOS 26 SDKs; a Mac with a 120 Hz (ProMotion) display for the by-eye checks.
- For the allocation check: the method in `specs/011-draw-allocation-counter/quickstart.md`.

## One-command verification

```sh
./Scripts/verify.sh
```

## Try it

1. Build and launch the macOS Debug app with `open -n <app>` on a 120 Hz display.
2. Click across the window and watch the ship turn, burn, flip and brake.
3. Relaunch with `--no-interpolation` and repeat: the stepping is visible again.
4. Relaunch with `--debug-ship-spin` (with and without `--no-interpolation`) to watch rotation alone.

## Validation matrix

### Automated (headless)

| # | Check | Expected | Covers |
|---|-------|----------|--------|
| 1 | `./Scripts/verify.sh` | Exits 0; all existing and new tests pass; no new `warning:` lines | SC-006, FR-011 |
| 2 | `swift test --build-system swiftbuild` 10 times in a row | 10 identical passes | SC-006 |
| 3 | Blend: fraction 0, equal pairs, 1,000+ seeded pairs (within ±10,000 units) and fractions | Bit for bit at 0 and for equal pairs; within 1e-9 units of the exact point at the fraction along the segment | SC-001, FR-002, FR-003 |
| 4 | Heading seam pairs both ways, opposite headings, range | Short arc; never more than half a turn; opposite blends counter-clockwise; result in (−π, π] | SC-002, FR-002 |
| 5 | Accumulator over 10,000+ elapsed values incl. 0, negative, non-finite, sub-tick, exact multiples, 10 s stalls | `tickFraction` in [0, 1) and `unconsumed ≥ 0` after each | SC-003, FR-001 |
| 6 | `advance` with `previousPose` for 0, 1, 2, 4 ticks, autopilot and explicit input | Previous pose per C3; state byte-identical to the plain overload | SC-003, FR-005 |
| 7 | `DebugShipOptions` with and without `--no-interpolation` | `interpolates` false only with the argument | FR-008 |

### Manual (running app)

| # | Check | Expected | Covers |
|---|-------|----------|--------|
| 8 | macOS Debug at 120 Hz: fly orders and `--debug-ship-spin`, then the same with `--no-interpolation` | Smooth without the argument; stepping with it; no long-way spin across ±π | SC-004, SC-002, US1 |
| 9 | macOS at 60 Hz (set the display to 60 Hz in System Settings) | As smooth as before, no new stepping | SC-004, US1-3 |
| 10 | 011's check 25 by "the method", 60 s with orders, macOS and iOS simulator | `allocs=0` in every frame summary; frame times within budget, before (`main`) and after recorded | SC-005, FR-009 |
| 11 | Release build, both platforms | `--no-interpolation` has no effect; the ship is drawn interpolated | FR-008 |

## Evidence

| # | Result | Notes |
|---|--------|-------|
| 1 | **PASS** 2026-10-04 | `./Scripts/verify.sh`: every stage PASS (metal compiler, ship.png identity, swift build with the layer boundary, no Metal device in tests, swift test, xcodebuild macOS and iOS) |
| 2 | **PASS** 2026-10-04 | 10/10 consecutive `swift test --build-system swiftbuild` runs: 87 simulation, 84 rendering, 58 platform tests |
| 3–4 | **PASS** 2026-10-04 | `Ship pose` suite: fraction 0 and equal pairs bit for bit (signed zeros included); 2,000 seeded pairs within ±10,000 units on the segment within 1e-9 and on the short arc; seam pairs both ways; opposite headings counter-clockwise from four starts; every heading in (−π, π] |
| 5 | **PASS** 2026-10-04 | `TimeAccumulator`: 10,000 elapsed values (specials incl. 0, −0, negative, ±∞, NaN, 10 s and 30 s stalls, exact and one-ulp-off tick multiples; random sub-tick, whole-tick and up-to-0.2 s values): `tickFraction` in [0, 1), `unconsumed ≥ 0` after each |
| 6 | **PASS** 2026-10-04 | `Simulation`: 0, 1, 2, 4 ticks with the autopilot and with an explicit input; previous pose per C3; state byte-identical to the plain overload; a 9-frame mixed sequence trails by exactly one tick |
| 7 | **PASS** 2026-10-04 | `DebugShipOptions`: `interpolates` false only with `--no-interpolation`, independent of `--debug-ship-spin` and `--no-ship` |
| 8 | **PENDING** | Needs a 120 Hz display: the development Mac's display ran at 60 Hz (budget 16.67 ms in every summary) |
| 9 | **PENDING** | By eye, at 60 Hz |
| 10 | **PASS** 2026-10-04 | Optimised build with the counter (Release + `SWIFTSKY_INSTRUMENTATION`), `--debug-ship-spin` (the heading is blended every frame; orders could not be clicked without Accessibility), 60 s. **macOS**: `allocation counter ready`, 30/30 summaries `allocs=0 allocframes=0`, 0 dropped; mean 0.167 ms, worst 0.91 ms (`main`: 0.184 ms, 1.24 ms). **iOS simulator** (iPhone 17 Pro): 22/22 summaries `allocs=0 allocframes=0`; warm run mean 0.145 ms, worst 13.8 ms, 0 dropped (`main`: 0.157 ms, 29.3 ms, 2 dropped at launch). A first run on a freshly booted simulator had a 297 ms launch frame and mean 0.264 ms; the warm repeat is the comparable figure |
| 11 | **PASS** 2026-10-04 | By reading: `DebugShipOptions` and its parsing, `FrameLoop.debugNoInterpolation` and the switch's branch are all under `SWIFTSKY_INSTRUMENTATION`; the `#else` branch always blends |
