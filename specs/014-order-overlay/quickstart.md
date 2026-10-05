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
