# Quickstart & Validation Guide: Click to Order the Ship on macOS

**Feature**: `009-click-to-order-macos` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

How to verify every success criterion. Guarantees are in
[contracts/click-to-order.md](./contracts/click-to-order.md); reasons in [research.md](./research.md).

## Prerequisites

The same as 008. A Mac with a mouse (ideally one with a middle button) or a trackpad with tap to click.

## One-command verification

```bash
./Scripts/verify.sh
```

It now also runs `ClickPositionTests` (C1–C5).

## Reading the order log (Debug and Profiling)

```bash
log stream --level notice --predicate 'subsystem == "com.swiftsky.app"'
```

The same `order …` and `arrived …` lines as 008.

---

## Validation matrix

| # | Check | How | Pass when | SC |
|---|-------|-----|-----------|----|
| 1 | Flip and conversion tests | `./Scripts/verify.sh` | `ClickPositionTests` C1–C5 pass; 008's suites still pass | SC-002, SC-007 |
| 2 | Shared code untouched | `git diff main --stat -- Sources/SwiftSkySimulation Sources/SwiftSkyRendering Sources/SwiftSkyPlatform/MoveOrderRequest.swift Sources/SwiftSkyPlatform/SurfaceEvent.swift Sources/SwiftSkyPlatform/FrameLoop.swift Sources/SwiftSkyPlatform/Instrumentation.swift` | Empty | FR-007 |
| 3 | Click sends the ship | Debug build; click the centre, the four corners and the four edge midpoints (each within 20 pt of the edge), waiting for each arrival | Each `arrived` within 1 unit of its `order`; the ship under the pointer | SC-001 |
| 4 | Not mirrored | Click near the top, then near the bottom | The ship goes up, then down; `order` world y positive, then negative | US1-3 |
| 5 | New click replaces the order | Click far; before arrival click elsewhere; five times | The ship comes to rest at the second point each time; one `arrived` per run | SC-003 |
| 6 | Clicks that do not order | Three each: right click, Control-click, middle click, drag, a press on the surface released outside the window, first click on the inactive window (after focusing another app); once each: drag the window by its title bar, resize it from an edge, open a menu from the menu bar | No `order` line for any; the window moves, resizes and the menu opens as usual | SC-004, FR-005 |
| 7 | Clicks that do order | Three each: Command-, Option-, Shift-click, trackpad tap to click, double-click | An `order` line per click (two for a double-click, same point) | SC-004, US1-4, US2-2 |
| 8 | Window sizes and full screen | Resize through five sizes, one taller than wide; full screen; move between a Retina and a non-Retina display if available; click near each corner each time | Check 3's tolerance every time | SC-005 |
| 9 | Frame budget and allocations, before and after | Profiling builds of `main` (before) and this branch (after) on the same Mac, window frontmost, 30 s each, the after run with a click every ~2 s; summaries and Instruments Allocations on the frame-loop thread | Both recorded side by side; after: `dropped=0` outside launch, no allocations on frames without a click | SC-006 |
| 10 | VoiceOver unchanged | VoiceOver on; focus the surface | It still reads "swiftSky game surface" | FR-009 |

## Evidence

Filled in by `/speckit-implement`: for each check, the Mac, the date and the outcome, with log excerpts
where they apply. A check that could not be run is listed as not run, with the reason.

All checks: 2026-10-01, Debug build, Xcode 27.0 (27A266a), macOS host.

| # | Where | Outcome |
|---|-------|---------|
| 1 | `./Scripts/verify.sh` | PASS. `ClickPositionTests` C1, C4, C5 green; 008's suites still pass |
| 3, 4, 6, 7 | Mac | NOT RUN. Clicks could not be produced: synthetic mouse events posted through CGEvent were dropped, because the session has neither Accessibility nor event-posting access (`AXIsProcessTrusted` and `CGPreflightPostEventAccess` both false), and granting them is the user's decision. The app itself ran normally: a 1,280 × 720 window at 120 Hz, `frames=7074 skipped=0 dropped=1 mean=0.301ms`. Needs a manual pass |
| 5 | Mac | NOT RUN, for the same reason as check 3. Replacement itself is 008's `MoveOrderRequest.apply`, tested by 008 `replacesMidFlight` and `lastOfTwoWins`, which pass |
| 8 | Mac | NOT RUN, for the same reason as check 3. Every size class is covered by C2 (1,280 × 800, 800 × 1,280, 1,001 × 667, full-screen 1,512 × 982, each at 1× and 2×) and C3, which pass |
| 2 | `git diff main --stat` on the shared files | PASS. Empty for the logic and rendering layers, `MoveOrderRequest.swift`, `SurfaceEvent.swift`, `FrameLoop.swift` and `Instrumentation.swift`; no accessibility line in `MetalSurfaceView.swift` changed |
| 9 | Mac, 120 Hz, Profiling builds under `xctrace` Allocations, 30 s each | PARTIAL. Frame times: before (`main`) `frames=3953 skipped=0 dropped=0 mean=0.176ms worst=3.10ms`; after (this branch) `frames=3953 skipped=0 dropped=0 mean=0.178ms worst=3.98ms`, budget 8.33 ms; no difference beyond noise. The after run had no clicks (none could be posted, check 3). The allocation count per thread is not exportable from the trace without the Instruments UI; the recogniser runs only on the main thread when the mouse is used, and nothing is added to the frame loop (R6) |
| 10 | Mac | NOT RUN (VoiceOver needs the UI). By review: `configureAccessibility()` is unchanged on macOS (check 2) |

**Still open, for a manual pass on the Mac**: checks 3–8 (clicks: send, not mirrored, replace,
non-ordering and ordering clicks, window sizes and full screen), check 9's allocation count and its
with-clicks run, and check 10. They need clicks this session cannot post, or the Instruments and
VoiceOver UI. The headless checks and the final `./Scripts/verify.sh` run are complete.
