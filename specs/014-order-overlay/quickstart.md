# Quickstart & Validation Guide: Draw the Order Overlay

## Prerequisites

- Xcode 27, the repo at the feature branch, the iPhone 17 Pro simulator (iOS 27) and a Mac.
- Debug builds for the visual checks: launch with `--no-debug-overlay` so the overlay's own pixels are
  easy to read. For allocation counting, the optimised instrumented build of 011 (CLAUDE.md, "The
  method" in `specs/011-draw-allocation-counter/quickstart.md`).

## One-command verification

```bash
./Scripts/verify.sh
```

Runs every headless suite, including the new `PlannedPath.tick(ofPoint:)` and `OrderOverlay` tests
(contracts C1, C2), and builds both apps.

## Validation matrix

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `verify.sh` | All suites pass, both apps build, no warnings | FR-017 |
| 2 | Launch on macOS and iOS, give no order | No overlay; with `--no-ship --no-debug-overlay` the surface is uniformly black | SC-004, FR-001 |
| 3 | Order the ship to a point (click on macOS, tap on iOS) | Marker ring centred under the pointer or finger; ring around the ship; line from the ship to the marker's centre | SC-001, FR-004–FR-006 |
| 4 | Screenshot right after an order; measure the marker | Marker centre within half a pixel of the ordered point (read from the Debug `order view=…` log line × scale) | SC-001, FR-011 |
| 5 | Watch a full flight | Ring stays on the ship; line shrinks behind the ship and never runs behind it | SC-002, FR-007 |
| 6 | Watch the arrival | Marker, line and ring vanish on arrival (the Debug `arrived` log line), 10 of 10 orders | SC-003, FR-002 |
| 7 | Give a new order mid-flight | Old marker and line replaced on the next frame | FR-002 |
| 8 | Order far off-screen, past the 60-second cap if possible | Line runs off the edge; no indicator; still ends at the destination when it comes into view | FR-006, edge cases |
| 9 | Resize the Mac window / rotate the iPhone mid-flight | Marker and line stay on the same world points | SC-001 |
| 10 | Release build | Overlay drawn the same as in Debug | FR-003 |
| 11 | `--no-interpolation` (Debug) | Overlay follows the tick pose with the sprite | FR-012 |
| 12 | 011 check 25 with orders flown for 60 s on each platform | `allocs=0` in every frame summary | SC-005, FR-013 |

## Notes for the visual checks

- **iOS**: tap with the simulator panel (or by hand), screenshot with `xcrun simctl io booted
  screenshot`, and read the order lines with `xcrun simctl spawn <udid> log stream`.
- **macOS**: click by hand. Screenshots need Screen Recording permission for the process that takes
  them (see 001 quickstart, check 2); ⌘⇧5 works without it.
- The overlay colour is the cyan-green of `OrderOverlayStyle`; the marker is the small ring, the ship's
  highlight the large one.

## Results

**Checks 2, 3, 5, 6, 7 — PASS on iOS (2026-10-05, T010).** iPhone 17 Pro simulator, iOS 27.0, Debug
build with `--no-debug-overlay`, the simulator in landscape (874 × 402 pt, 3×). Orders by tap through
the simulator panel; screenshots with `simctl io screenshot`; order and arrival lines from `log stream`.

- **2**: relaunched with `--no-ship --no-debug-overlay` and no order: 3,162,132 pixels, all exactly
  (0, 0, 0).
- **3 (and 4 for this order)**: tap at view (700, 302) pt. The marker ring's centre, fitted to its
  pixels with the line's wedge left out, is (2100.00, 906.00) px: exactly (700, 302) × 3. The highlight
  rings the ship and the line joins them.
- **5**: six frames 0.6 s apart through a 377-unit flight: the line shortens behind the ship, the ring
  stays on it, and the line always ends at the marker.
- **6**: the frames after the `arrived` line show only the ship; nothing of the overlay.
- **7**: a second order 2.3 s into a flight replaced the marker and line at once; from a moving ship
  the new line curves (turn-back) and ends at the new marker.

**Check 12 — PASS on iOS, with a note (2026-10-05, T015).** Optimised instrumented build (Release with
`SWIFTSKY_INSTRUMENTATION`, CLAUDE.md), iPhone 17 Pro simulator, 7 orders by tap over 75 s, summaries
from `log stream`. Every summary with the overlay drawn in flight reports `allocs=0 allocframes=0`; the
order frames report `eventallocs=28`, the event queue's, counted apart as 011 defines.

Six summaries report `allocs=23 allocframes=1`, and each is the summary covering an `arrived` line:
one frame per arrival. An lldb breakpoint on `sky_alloc_app_allocation`, armed once
`Instrumentation.recordArrival` had been hit, stopped in `UnsafeMutablePointer.allocate()` called from
`Instrumentation.recordArrival` at `Instrumentation.swift:267`: the arrival `os_log` line of 008, which
exists only in instrumented builds. It predates this feature and is not the overlay's (the overlay draws
nothing on that frame). Release builds compile it away. Recorded as a separate finding.
*Since fixed (011 check 10, 2026-10-05):* both the arrival and the order lines are now written after the
counted stretch, and every summary reads `allocs=0`. The order frames' `eventallocs=28` above was the
order log line, not the event queue; it is now `eventallocs=1`.

**Check 10 — PASS on iOS.** A plain Release build draws the same overlay after a tap.

**Check 11 — PASS on iOS.** Debug with `--no-interpolation`: mid-flight, the highlight rings the
sprite, which is drawn at the tick pose, and the line starts at it.

**Checks 2, 3, 5, 6, 7, 8 and 9 (resize) — PASS on macOS, by eye (2026-10-05, T011, T017).** Debug build
with `--no-debug-overlay`, window opened at its first-launch size; orders by hand, results reported by
the tester: no overlay before an order; marker centred under the pointer, ring on the ship, line
between; the line shortens behind the ship; everything clears on arrival; a new order replaces the old
marker at once; the overlay stays on its world points through a live resize; an order at the window
edge, then shrinking the window, runs the line cleanly off the edge. No screenshots (this session has no
Screen Recording permission), so no pixel measurement on macOS; check 4's half-pixel measurement is the
iOS one above, through the same shared renderer and camera.

**Check 9 (rotation) — not run.** The simulator tools available here cannot rotate the device. The
overlay is placed through the camera every frame, the same path the macOS resize exercises, and the
geometry tests cover placement on any surface size; accepted without a rotation run.

**Check 12 on macOS — not run (2026-10-05, T016 skipped by decision).** SC-005 asks for both platforms;
only iOS was measured. The overlay's per-frame code is the shared rendering layer, identical on both,
and iOS shows `allocs=0` on every frame that draws it. Open as a gap, not a pass.

**Check 12 on macOS — PASS (2026-10-06).** 011's method: optimised instrumented build (Release plus
`SWIFTSKY_INSTRUMENTATION`) of `main` at `e0c9fdd`, launched with `open -n`, no arguments, on the 1×
external display (60 Hz), the frame log streamed. `allocation counter ready`, then 88 summaries from
23:32:39 to 23:35:31. Ten orders were clicked over 60 s (23:34:31 to 23:35:25); nine flew to an `arrived`
line, and one (23:35:09) was replaced by the next click before it arrived. Every summary, including each
covering an order or an arrival, reads `allocs=0 allocframes=0`. `eventallocs=1` in the 10 summaries that
carry an order click and 0 in the other 78. `gfxallocs ÷ frames` is 10.0 in every full summary (the same
as SKY-4's macOS reference). Last summary: `frames=10463 skipped=0 dropped=0 mean=0.228788ms
worst=6.055833ms budget=16.666625ms`. The gap above is closed.
