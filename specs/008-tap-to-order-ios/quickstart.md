# Quickstart & Validation Guide: Tap to Order the Ship on iOS

**Feature**: `008-tap-to-order-ios` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

How to verify every success criterion. The API and its guarantees are in
[contracts/tap-to-order.md](./contracts/tap-to-order.md), shapes in [data-model.md](./data-model.md),
and the reasons in [research.md](./research.md).

---

## Prerequisites

- The same as 007: Xcode 27, the iOS 26 and macOS 26 SDKs, and the Metal toolchain component.
- An iPhone simulator and an iPad simulator (or devices) that support Split View.

## One-command verification

```bash
./Scripts/verify.sh
```

It now also runs `MoveOrderRequestTests` (contract C1–C10) on the Mac host.

## Reading the order log (Debug and Profiling)

```bash
xcrun simctl spawn booted log stream --level notice --predicate 'subsystem == "com.swiftsky.app"'
```

Each tap prints `order view=(x, y) world=(x, y)` (or `order dropped … reason=…`), and each arrival
prints `arrived world=(x, y) ticks=n` (FR-015). On a device, use Console.app filtered on the same
subsystem.

---

## Validation matrix

### Automated (headless)

| # | Check | How | Pass when | SC |
|---|-------|-----|-----------|----|
| 1 | Conversion and order tests | `./Scripts/verify.sh` | `MoveOrderRequestTests` pass: C1–C10 | SC-002, SC-003, SC-004, SC-005 |
| 2 | Whole suite and builds | `./Scripts/verify.sh` | `VERIFICATION PASSED`, both app targets built, no warnings | SC-008, SC-009 |
| 3 | Logic and rendering untouched | `git diff main --stat -- Sources/SwiftSkySimulation Sources/SwiftSkyRendering` | Empty | FR-009 |

### On iPhone (Debug build)

| # | Check | How | Pass when | SC |
|---|-------|-----|-----------|----|
| 4 | Tap sends the ship | On an iPhone and on an iPad (full screen): launch; tap the centre, the four corners and the four edge midpoints (each within 20 pt of the edge), waiting for each arrival | For each tap, the `arrived` line's world point is within 1 unit of the `order` line's world point; the ship is visibly under the tapped spot | SC-001 |
| 5 | New tap replaces the order | Tap far away; before arrival, tap a second point. Repeat five times | The ship comes to rest at the second point every time; the log shows one `arrived` for it | SC-003 |
| 6 | Immediate response | Tap beside the ship while it is at rest | The ship starts turning towards the tap with no perceptible delay | SC-005 |
| 7 | Rotation | Rotate to landscape; tap the corners | As check 4 | SC-001 |
| 8 | Taps outside the safe area | Tap under the status bar / Dynamic Island and just above the home indicator | Orders are issued there (log) and the ship flies there | US1-4 |
| 9 | Not-taps | Drag across the surface; long-press; two-finger tap; swipe up from the bottom edge | No `order` line for any of them; the home gesture works | FR-001, FR-003 |
| 10 | VoiceOver | Turn VoiceOver on; tap the surface | The ship flies to the tapped point; VoiceOver still reads "swiftSky game surface" on focus | SC-007a |

### On iPad (Debug build)

| # | Check | How | Pass when | SC |
|---|-------|-----|-----------|----|
| 11 | Split View and Slide Over | At each Split View width the system offers, and in Slide Over, tap near each corner; resize the pane while the ship flies, then tap | Check 4's tolerance at every width; after the resize, the ship goes to the point under the new tap | SC-007, US3-3 |

### Performance and builds

| # | Check | How | Pass when | SC |
|---|-------|-----|-----------|----|
| 12 | Frame budget and allocations, before and after | Profiling build of `main` (before) and of this branch (after), on the **same** iOS destination (device, or the same simulator if no device is available): 30 s each, the after run with a tap every ~2 s; read the `frames=… dropped=…` summaries and the Allocations instrument on the frame-loop thread | Both runs recorded side by side; after: `dropped=0` outside launch (within 001 SC-003's budget) and no allocations on frames without a tap | SC-006 |
| 13 | macOS builds and tests | `./Scripts/verify.sh` (macOS host) | macOS app builds, `MoveOrderRequestTests` run on macOS | SC-008 |
| 14 | Release logs nothing | Release build; tap a few times; stream the log | No `order` or `arrived` lines; `strings` on the binary finds neither | SC-007b |

## Evidence

Filled in by `/speckit-implement`: for each check, the device or simulator, the date and the outcome,
with log excerpts where they apply. A check that could not be run is listed as not run, with the reason.
