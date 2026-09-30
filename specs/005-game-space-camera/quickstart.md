# Quickstart & Validation Guide: Game Space and Camera

**Feature**: `005-game-space-camera` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

How to verify every success criterion. The API and its guarantees are in
[contracts/camera.md](./contracts/camera.md), shapes in [data-model.md](./data-model.md), and the
reasons in [research.md](./research.md). The 001–004 checks still apply, unchanged.

---

## Prerequisites

- The same as 004: Xcode 27, the iOS 26 and macOS 26 SDKs, and the Metal toolchain component.

## One-command verification

```bash
./Scripts/verify.sh
```

Its usage is unchanged. `swift test` now also runs `CameraTests`.

## Try it from a test

The feature has no visible output. To run only the new suite:

```bash
swift test --build-system swiftbuild --filter Camera
```

---

## Validation matrix

### Automated (headless)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | `./Scripts/verify.sh` | Exits 0; every existing test and the camera tests pass; no `warning:` lines; the Metal-device guard passes | SC-006, FR-014 |
| 2 | Run `swift test --build-system swiftbuild` 10 times in a row | 10 identical passes | SC-006 |
| 3 | Mapping tests on 1920 × 1080, 1,001 × 667 and a portrait 768 × 1024 point surface | Origin → centre; four corners exact with +y up; clip origin (0, 0) and corners exactly (±1, ±1); one unit = one point | SC-001, US1, C6–C8 |
| 4 | Round-trip test: 1,000 grid positions across and beyond the surface | view → world → view within 1e-9 points; the centre and corners map to the expected world points | SC-002, US2, C9 |
| 5 | Scale and resize tests: the same point size at 1×, 2×, 3×; a resize to 1,001 × 667; insets on versus off | Identical mappings across scales; origin at (500.5, 333.5); insets change nothing | SC-003, SC-004, US3-1…3, C4, C5 |
| 6 | No-camera tests: zero width, zero height, zero area; backing scale 0, −0, −2, `.nan`, `±.infinity`; extreme finite scales that overflow or underflow each half-extent on its own | `nil` every time; every produced camera maps finite input to finite output | SC-005, US3-4, C1–C3, C2a, C10 |
| 7 | `GameSpace.shipLength` | 40 | FR-009 |

### Structural

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 8 | Read `Camera.swift` | A struct of two `let Double`s; no class, array, closure or other reference/growable storage; mappings are non-mutating arithmetic | SC-007, FR-007 |
| 9 | `git diff main -- Sources/SwiftSkyPlatform Sources/SwiftSkyRendering/Renderer.swift Sources/SwiftSkyRendering/Shaders.metal` | Empty: nothing on the draw or frame path changed | SC-006, FR-013, research R6 |
| 10 | `grep -n SKY-23 Sources/SwiftSkySimulation/Ship.swift` | No "retune" note; the limits' values unchanged | FR-012 |

### Manual (running app)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 11 | Launch Debug (no argument), Debug with `--no-debug-overlay`, and Release, on both platforms | Unchanged: the 003 overlay; a uniformly black surface; a uniformly black surface | SC-006, US4-1 |

## Evidence

Record results below as checks are run.

| # | Result | Notes |
|---|--------|-------|
| 1 | **PASS** 2026-09-30 | `./Scripts/verify.sh`: every stage PASS (Metal preflight, layer-boundary build, Metal-device guard, `swift test`, macOS and iOS `xcodebuild`), no `warning:` lines |
| 2 | **PASS** 2026-09-30 | 10/10 consecutive `swift test --build-system swiftbuild` runs pass (runs of 44, 61 and 16 tests) |
| 3–7 | **PASS** 2026-09-30 | `Camera` suite, 15 tests (31 cases): no-camera for zero width/height/area, scales 0, −0, −2, NaN, ±∞, and extreme scales that overflow or underflow either half-extent, one axis at a time; half-extents; fractional 1,001 × 667 px at 2× → 250.25 × 166.75; ship length 40; centre, corners and ±1 edges on three sizes incl. portrait; one unit = one point; off-surface finite; non-finite pass-through; known view → world; 1,000-position round trip; 1×/2×/3× identical; resize; portrait and landscape insets ignored; off-surface view → world |
| 8–10 | **PASS** 2026-09-30 | `Camera` is two `let Double`s and three non-mutating arithmetic functions, no reference or growable storage. `git diff main` on `SwiftSkyPlatform`, `Renderer.swift`, `Shaders.metal` is empty; no `Camera(` in `Sources/`. `Ship.swift`'s retune note replaced; limits unchanged |
| 11 | **Not run** (structural PASS) | No interactive launch in this session. Nothing on the draw or frame path changed (check 9), and nothing constructs a camera, so what the app draws cannot differ |
