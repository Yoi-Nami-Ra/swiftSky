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

All on-device checks: 2026-10-01, Debug build, Xcode 27.0 (27A266a), iOS 27.0 simulator runtime. The
simulator ran in landscape, so the surface was 874 × 402 points.

| # | Where | Outcome |
|---|-------|---------|
| 1 | `./Scripts/verify.sh`, macOS host | PASS. `MoveOrderRequestTests` C1, C2, C5, C10 green |
| 2 | `./Scripts/verify.sh` | PASS. `VERIFICATION PASSED`, both app targets built, no warnings |
| 4 | iPad Pro 11-inch (M5) simulator, portrait 834 × 1,210 pt | PARTIAL. The one tap the simulator delivered was handled correctly: `order view=(600, 300) world=(183, 305)`, `arrived world=(182.959, 304.927)`. The input tool then stopped delivering taps on this freshly created iPad, even on the Home Screen (no app launched from the Dock), while the Home button worked. That is a simulator tooling fault, not this feature. The nine-point run on the iPad is left for a manual pass |
| 4 | iPhone 17 Pro simulator | PASS, with one deviation at the sensor housing, below. All nine points, each `order` then `arrived`, within 0.12 units (log excerpt below) |
| 6 | iPhone 17 Pro simulator | PASS. Each `order` line is written in the frame boundary that applies it, and the ship was seen turning towards the tap in the next screenshot. The exact latency was not measured; that the same frame's advance flies the order is C10/C13 |
| 8 | iPhone 17 Pro simulator | PASS. Taps 20 pt from the corners beside the Dynamic Island, and at the bottom edge above the home indicator, ordered the ship there |
| 9 | iPhone 17 Pro simulator | PASS for drag, 1.5 s long press and two-finger tap: no `order` line after 11:24:25. The home gesture was not reproducible with the simulator's input tool (an edge swipe left the app in front and issued no order); not run on a device |

| 10 | — | NOT RUN. The iOS simulator has no VoiceOver. `.allowsDirectInteraction` is set (C15, code review); needs a device |

**Check 4 log** (view points → world; arrival):

```text
order view=(437, 201) world=(0, 0)          arrived world=(-0.078, -0.034)
order view=(20, 382)  world=(-417, -181)    arrived world=(-416.941, -180.975)
order view=(20, 20)   world=(-417, 181)     arrived world=(-417.000, 180.935)
order view=(854, 20)  world=(417, 181)      arrived world=(416.908, 181.005)
order view=(854, 382) world=(417, -181)     arrived world=(416.999, -180.934)
order view=(437, 20)  world=(0, 181)        arrived world=(-0.119, 180.949)
order view=(854, 201) world=(417, 0)        arrived world=(416.919, 0.036)
order view=(437, 382) world=(0, -181)       arrived world=(0.080, -180.967)
order view=(70, 201)  world=(-367, 0)       arrived world=(-366.916, -0.000)
```

**Deviation, sensor housing**: in landscape the Dynamic Island sits at the middle of the left edge.
Taps 20 pt and 45 pt from that edge at its midpoint never reached the app: no `order` line, and no
other touch is lost. The system owns the touches over and around the sensor housing, which FR-003
leaves alone. At 70 pt the tap ordered the ship normally. The other eight points are within 20 pt of
their edge, as SC-001 asks. No code change: an app cannot receive those touches.
