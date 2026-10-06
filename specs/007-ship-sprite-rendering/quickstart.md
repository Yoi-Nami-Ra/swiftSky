# Quickstart & Validation Guide: Ship Sprite Rendering

**Feature**: `007-ship-sprite-rendering` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

How to verify every success criterion. The API and its guarantees are in
[contracts/ship-sprite.md](./contracts/ship-sprite.md), shapes in [data-model.md](./data-model.md), and
the reasons in [research.md](./research.md).

**Earlier checks**: every 001–003 check that expects a uniformly black surface now launches with
`--no-ship --no-debug-overlay`. 002's text-comparison checks add `--no-ship` too. Release checks that
expected uniform black now expect black with the ship centred and facing right (spec FR-014, FR-015).

---

## Prerequisites

- The same as 006: Xcode 27, the iOS 26 and macOS 26 SDKs, and the Metal toolchain component.

## One-command verification

```bash
./Scripts/verify.sh
```

It now also checks that the bundled ship image is byte-identical to `design/sprites/ship.png`, and runs
the placement, image and error tests.

## Launch arguments (Debug and instrumented Release only)

| Argument | Effect |
|----------|--------|
| *(none)* | The ship at the centre facing right, and the debug overlay |
| `--debug-ship-spin` | The ship turns counter-clockwise in place, one turn every 2 s |
| `--no-ship` | The ship is not drawn; with `--no-debug-overlay`, the surface is uniformly black |

---

## Validation matrix

### Automated (headless)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `./Scripts/verify.sh` | Exits 0; all tests pass, including the new suites; no `warning:` lines; the Metal-device guard passes | SC-009 |
| 2 | Change one byte of `Sources/SwiftSkyRendering/Resources/ship.png`, run `verify.sh`, then restore the file | The image-identity stage fails | SC-008a |
| 3 | `swift test --build-system swiftbuild --filter ShipSpritePlacement` | C1–C10 pass | SC-002, SC-003 |
| 4 | `swift test --build-system swiftbuild --filter ShipImage` | C11–C13 pass | FR-002–FR-005 |
| 5 | `swift test --build-system swiftbuild --filter RendererError` | C14 passes | SC-006 |
| 6 | `swift test --build-system swiftbuild --filter DebugShipOptions` | C15 passes | FR-013, FR-014 |
| 7 | `swift test` 10 times in a row | 10 identical passes | SC-009 |

### Manual (visual): macOS and iOS

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 8 | Launch Debug on macOS, with no argument and with `--no-debug-overlay`; screenshot the 1280 × 720 window on a 2× display; narrow the window until the overlay reaches the ship | Ship centred within 1 px, nose to the right, bounding box 80 × 80 px; overlay top-left; where they overlap the overlay's text is on top | SC-001, US1-4 |
| 9 | The same on the iOS simulator (3×) and on a 1× display or scaled screenshot where possible | 120 × 120 px at 3×, 40 × 40 at 1×; centred; smooth edges | SC-001, FR-010 |
| 10 | Zoom the screenshot on the ship's edge | No rectangle, fringe or halo; transparent areas pure black (0, 0, 0) | FR-004, US1-3 |
| 11 | Launch with `--debug-ship-spin`; after the first second (spin-up takes 0.5 s), time 5 turns | Counter-clockwise; 10 s ± 0.5 s; nose passes top, then left, then bottom; no distortion | SC-004 |
| 12 | Resize the Mac window through 5 sizes, one taller than wide; drag continuously | Ship stays centred and 40 × 40 pt; never stretched | SC-005 |
| 13 | iPad simulator: Split View at ⅓, ½ and ⅔ | Ship centred and square at each size | SC-005 |
| 14 | Move the Mac window between a 2× and a 1× display (if available) | Same size in points; no shimmer when spinning | FR-010 |
| 15 | Debug with `--no-ship --no-debug-overlay` | Uniformly black; 001 checks 1–6 pass | SC-008 |
| 16 | Build Release, launch it with no argument and with `--debug-ship-spin --no-ship` | Both show the ship centred, still, facing right | FR-015 |
| 17 | `strings` and `nm` on the stripped Release binary | 0 `debug-ship-spin`, 0 `no-ship`, 0 `DebugShipOptions`, 0 `debugShipSpin`, 0 `drawsShip` | SC-008, C17 |
| 18 | Remove `ship.png` from the built app's `swiftSky_SwiftSkyRendering.bundle`, then launch | Failure notice naming the ship image; log line with `ship_image_unavailable`; no frame presented | SC-006 |
| 18a | With VoiceOver on (macOS) or the Accessibility Inspector, focus the game surface | Its description is still "swiftSky game surface", as in 001; nothing describes the ship | FR-016a |
| 19 | Frame time and allocation count over 60 s, overlay on, ship drawn (macOS) | Within budget; draw-path allocations 0; compare with 003's baseline (mean 0.29 ms) | SC-007 |

---

## Evidence

Recorded 2026-10-01 on macOS 26 (Apple silicon), Xcode 27, the iPhone 17 Pro simulator (iOS 27, 3×).

| # | Result | Notes |
|---|--------|-------|
| 1 | **PASS** | `./Scripts/verify.sh`: all 7 stages green, including the new ship-image identity stage; no `warning:` lines beyond the documented swiftbuild exemption; the Metal-device guard passes. |
| 2 | **PASS** | Wrote one byte into the bundled `ship.png`: the identity stage FAILed and verification failed. Restored the file, and `cmp` confirms it matches the design file again. |
| 3 | **PASS** | `ShipSpritePlacement`: 15 tests (with parameterised cases) covering C1–C10. |
| 4 | **PASS** | `ShipImageBitmap`: 5 tests covering C11–C13. |
| 5 | **PASS** | `RendererError`: 2 tests covering C14, plus distinct codes for every case. |
| 6 | **PASS** | `DebugShipOptions`: 1 parameterised test (8 cases), C15. |
| 7 | **PASS** | 10 consecutive `swift test` runs: every run passed, the same in each (the three test binaries report 84 tests in 12 suites, 60 in 4, and 17 in 3). |
| 8 | **Not captured (macOS)** | `screencapture -l` failed with "could not create image from window": this session has no Screen Recording permission. The app launches, presents frames and draws the overlay. Re-run by eye, or grant the permission and capture. |
| 9 | **PASS (iOS, 3×)** | Debug, overlay on. Screenshot 1206 × 2622 px (portrait capture of the landscape app). The ship's opaque pixels span 120 px across its width (543…662), which is 40 pt at 3×. Its centre across the width is 603.0, the surface centre is 603. Rotated to landscape, the nose points right and the overlay is at the top-left. Log: `frames=354 skipped=0 dropped=0 mean=0.18 ms`. |
| 10 | **PASS (iOS, 3×)** | Background corner pixel (0, 0, 0). Edges look smooth at 100 %, with no rectangle or halo around the sprite. |
| 11 | **PASS (iOS, measured from screenshots)** | `--debug-ship-spin`, four `simctl io screenshot` captures after spin-up, at 0.617 s, 0.657 s and 0.637 s apart. The orientation of the ship's brightness centroid advanced **+119.9°, +111.1°, +116.9°**: counter-clockwise, 347.9° in 1.911 s ≈ **182°/s**, one turn in ≈ **1.98 s** (expected 2 s ± 5 %). Capture timing jitters by tens of ms, so treat this as a rate check, not a precise measurement. The rate itself is the ship's maximum turn rate of π rad/s, covered by 004's tests. Undistorted in every frame. |
| 12 | **Not run (visual, macOS)** | Needs someone watching a live resize; this session cannot capture macOS windows (see check 8). Structurally covered: the placement tests show a 40 pt square, centred on the surface, for wide, tall and odd-sized surfaces (C8), and identical results at 1×, 2× and 3× (C7). The placement is rebuilt from the current surface every frame, so a resize applied at a frame boundary (001 FR-031) is reflected in the next frame. |
| 13 | **Not run** | No iPad simulator is installed on this machine (`simctl list devices available` lists iPhones only). The same structural cover as check 12 applies, including the portrait-shaped 390 × 844-point case. |
| 14 | **Not run** | No 1× display is attached. At 1× the sprite samples mip level 1 (40 × 40), built once at init (research R4). |
| 15 | **PASS (iOS)** | Debug with `--no-ship --no-debug-overlay`: every pixel of the app surface is (0, 0, 0). The only non-black pixels are the OS home indicator (rows 1167–1181 of the 2622 × 1206 landscape capture), which the system draws, not the app. |
| 16 | **Not run (visual)** | Release was not launched to the screen: macOS capture is unavailable (check 8), and `simctl install` hung on this simulator. Structural: in Release the ship is drawn unconditionally (only the `drawsShip` guard is instrumentation-only), the loop always calls `advance(_:ticks:)`, and check 17 shows no argument parsing exists. |
| 17 | **PASS** | macOS Release binary, unstripped and after `strip -rSTx`: `strings` finds 0 `debug-ship-spin` and 0 `--no-ship`; `nm` finds 0 `DebugShipOptions`, 0 `debugShipSpin` and 0 `drawsShip`. |
| 18 | **PASS (macOS)** | `ship.png` deleted from a copy of the built app's `swiftSky_SwiftSkyRendering.bundle`. **Release**: the process stays up with one 1280 × 720 window, the text-only notice (the renderer never exists, so no loop starts and no frame is presented), and `/usr/bin/log show` has `[com.swiftsky.app:renderer] renderer initialisation failed code=ship_image_unavailable detail=swiftSky could not load the ship image (ship.png is missing from the app). The installation may be incomplete.` **Debug**: the same log line, then 001's deliberate `assertionFailure` in `RendererFailureReporter` with the same code and text. (In zsh, `log` is a builtin: call `/usr/bin/log`.) |
| 18a | **Not run (assistive tech)** | Structural: `MetalSurfaceView`'s `accessibilityLabel = "swiftSky game surface"` is untouched by this feature (no platform-layer change beyond the switches), and nothing sets an accessibility value for the ship. |
| 19 | **Measured, with a caveat (macOS)** | 60 s Debug run, overlay on, ship drawn: frames=1315, **0 dropped, 0 skipped, mean 0.47 ms, worst 6.59 ms**, budget 16.16 ms. The window was not frontmost (the display link ran at about 22 Hz), so this is **not** a like-for-like comparison with 003's 120 Hz baseline (mean 0.29 ms). An earlier 120 Hz run of the same build: mean 0.19–0.21 ms, worst 1.76 ms, budget 8.33 ms. iOS simulator: mean 0.18–0.22 ms. Instruments Allocations was not run; the draw path allocates nothing by construction (`setVertexBytes` of a stack tuple; research R10). Re-run in the foreground with Instruments for the formal before/after. |
