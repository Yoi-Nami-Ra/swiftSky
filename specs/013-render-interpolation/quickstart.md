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
| 3 | Blend: fraction 0, equal pairs, 1,000+ seeded pairs and fractions | Bit for bit at 0 and for equal pairs; on the segment, at the fraction of the distance within 1e-9 | SC-001, FR-002, FR-003 |
| 4 | Heading seam pairs both ways, opposite headings, range | Short arc; never more than half a turn; opposite blends counter-clockwise; result in (−π, π] | SC-002, FR-002 |
| 5 | Accumulator over 10,000+ elapsed values incl. 0, negative, non-finite, sub-tick, exact multiples, 10 s stalls | `tickFraction` in [0, 1) and `unconsumed ≥ 0` after each | SC-003, FR-001 |
| 6 | `advance` with `previousPose` for 0, 1, 2, 4 ticks, autopilot and explicit input | Previous pose per C3; state byte-identical to the plain overload | SC-003, FR-005 |
| 7 | `DebugShipOptions` with and without `--no-interpolation` | `interpolates` false only with the argument | FR-008 |

### Manual (running app)

| # | Check | Expected | Covers |
|---|-------|----------|--------|
| 8 | macOS Debug at 120 Hz: fly orders and `--debug-ship-spin`, then the same with `--no-interpolation` | Smooth without the argument; stepping with it; no long-way spin across ±π | SC-004, SC-002, US1 |
| 9 | macOS at 60 Hz (set the display to 60 Hz in System Settings) | As smooth as before, no new stepping | SC-004, US1-3 |
| 10 | 011's check 25 by "the method", 60 s with orders, macOS and iOS simulator | `allocs=0` in every frame summary; frame times within budget | SC-005, FR-009 |
| 11 | Release build, both platforms | `--no-interpolation` has no effect; the ship is drawn interpolated | FR-008 |

## Evidence

| # | Result | Notes |
|---|--------|-------|
