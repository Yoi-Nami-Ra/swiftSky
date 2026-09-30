# Quickstart & Validation Guide: Ship State and Newtonian Motion

**Feature**: `004-ship-newtonian-motion` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

This guide covers how to verify every success criterion. Entity shapes are in
[data-model.md](./data-model.md), the API and per-tick rule in
[contracts/ship-motion.md](./contracts/ship-motion.md), and the reasons behind each decision in
[research.md](./research.md). The 001, 002 and 003 checks still apply, unchanged.

---

## Prerequisites

- The same as 003: Xcode 27, the iOS 26 and macOS 26 SDKs, and the Metal toolchain component.
- **Performance checks (8 and 9)**: before/after deltas on one device are valid on any hardware.
  Absolute baseline numbers wait for SKY-31 and SKY-32.

## One-command verification

```bash
./Scripts/verify.sh
```

Its usage is unchanged. `swift test` now also runs `ShipMotionTests`.

## Try it from a test

The feature has no visible output. To see the ship move, run only the new suite:

```bash
swift test --build-system swiftbuild --filter ShipMotion
```

---

## Validation matrix

### Automated (headless)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `./Scripts/verify.sh` | Exits 0; every existing test and the new ship-motion tests pass; no `warning:` lines | SC-006, FR-015 |
| 2 | Run `swift test --build-system swiftbuild` 10 times in a row | 10 identical passes | SC-006 |
| 3 | At-rest test: 10,000 neutral ticks | Ship's bit patterns unchanged | SC-001, US1-1 |
| 4 | Thrust test: 60 full-thrust ticks from rest, then 60 coasting ticks | Speed within 0.0001 of 200; distance within 3.34 of 100; coast distance within 0.0001 of 200; velocity constant while coasting; acceleration along the heading at 0°, 90°, −135°, 180° | SC-002, US1-2…5 |
| 5 | Turn tests: full turn from rest for 600 ticks, then release; turn −1; turn 0.5 held | +6 °/s per tick (±1e-6) until exactly 180 °/s after 30 (≤ 31) ticks; never above; release reaches exactly 0 with no sign change; −1 mirrors; 0.5 settles at 90 °/s; heading stays in (−180°, 180°] | SC-003, US2-1…5 |
| 6 | Determinism test: a ≥ 600-tick varied sequence, run 10 times; and n-at-once versus one-at-a-time | Byte-identical in both | SC-004, FR-011, US3 |
| 7 | Sanitisation and edge tests: the contract's table, zero and negative ticks, zero limits | As in the contract | FR-003, FR-007, Edge Cases |

### Manual (running app)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 8 | Instruments → Allocations, a 60 s Debug run on macOS and on iOS, on the frame-loop thread's draw path, using the method of SKY-3, SKY-4 and 002 check 15 | Zero allocations on our side | SC-005, FR-013 |
| 9 | Frame time, same device, before (on `main`) and after (this branch): the 003 overlay's mean and worst over 10 s | Both within budget; the delta recorded here | Principle III |
| 10 | Launch Debug (no argument), Debug with `--no-debug-overlay`, and Release, on both platforms | Unchanged: the 003 overlay; a uniformly black surface; a uniformly black surface | SC-005, US4-1 |

### Headless before/after benchmark (always run)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 11 | Build a throwaway `-O` executable in the session scratchpad with `swiftc`, from `Sources/SwiftSkySimulation/*.swift` plus a `main.swift` that runs 10,000,000 single-tick `Simulation.advance` calls (a full-thrust, full-turn input on this branch; no input on `main`), timing them with `ContinuousClock` and counting allocations with `malloc_zone_statistics` around the loop. Run it on `main` and on this branch, 3 runs each | Branch: 0 allocations; ns per tick before and after recorded here (expected well under 1 µs, i.e. < 0.03% of a 16.67 ms frame at 4 ticks) | Principle III, FR-013, research R7 |

## Evidence

Record results below as checks are run.

| # | Result | Notes |
|---|--------|-------|
| 1 | **PASS** 2026-09-30 | `./Scripts/verify.sh`: all 7 stages PASS, no `warning:` lines (the one exempt swiftbuild line only), both app targets build. `FrameLoop.swift` and all of `SwiftSkyRendering`/`SwiftSkyPlatform` unchanged against `main` |
| 2 | **PASS** 2026-09-30 | 10/10 consecutive `swift test --build-system swiftbuild` runs pass: 47 simulation, 44 rendering, 16 platform tests |
| 3–7 | **PASS** 2026-09-30 | `ShipMotion` suite, 21 tests (32 cases): rest, thrust, coast, heading, partial thrust, non-positive ticks; spin-up, spin-down, mirror, partial and lowered turn, wrap, thrust-after-rotation; ten-run and batching determinism; sanitisation and zero limits |
| 8 | **Not run** | Needs an Instruments session on each device. The method is itself still open (SKY-3 iOS, SKY-4 macOS) for 001. Structural evidence: the step touches stored `Double`s only, and check 11 measured 0 allocations over 10 M ticks |
| 9 | **Not run** | Needs an interactive device session with the 003 overlay. Check 11 bounds the added cost: ≤ 4 ticks × ~10 ns ≈ 40 ns per frame, 0.0002 % of a 16.67 ms budget |
| 10 | **Not run** (structural PASS) | No interactive launch in this session. `git diff main` shows no change to `SwiftSkyRendering` or `SwiftSkyPlatform`, the renderer ignores the ship, and the frame loop's call still passes the neutral input, so nothing visible can differ |
| 11 | **PASS** 2026-09-30 | Apple Silicon Mac, `swiftc -O -wmo`, 10 M single-tick advances, 3 runs each. **Before** (`main`, tick count only): 0.21 / 0.10 / 0.10 ns per tick. **After** (full thrust + full turn): 10.2 / 8.1 / 8.0 ns per tick; coasting (neutral): 3.9 ns per tick. **Allocations: 0** in every run; a control run that allocates 1,000 arrays in the same window reports 1,126 blocks, so the counter works |
