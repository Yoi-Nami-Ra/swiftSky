# Quickstart & Validation Guide: Metal App Shell

**Feature**: `001-metal-app-shell` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

How to run the app and verify every success criterion. Entity shapes are in
[data-model.md](./data-model.md); interfaces in [contracts/](./contracts/).

---

## Prerequisites

- Xcode 27 with the iOS 26 and macOS 26 SDKs
- A Mac running macOS 26 (for the macOS target)
- An iOS 26 device or simulator (for the iOS target)
- For the performance gates: the baseline devices — **iPhone 11** and **MacBook Pro (16-inch, 2019,
  Intel)**. See [research.md](./research.md) R2; confirm the Mac model against Apple's compatibility
  list before recording baselines.

No setup, code generation, or dependency installation (FR-016, SC-008).

---

## Run it

```bash
open swiftSky.xcodeproj
```

Select the **swiftSky (macOS)** scheme and press Run. Then the **swiftSky (iOS)** scheme and press Run.

**Expected**: a 1280×720 window, content area uniformly black, nothing else. On iOS, a black
full-screen surface in landscape.

## One-command verification

```bash
./Scripts/verify.sh
```

Builds both destinations and runs the headless suite. Exits non-zero on any failure. This is the body a
CI job will use verbatim once a remote exists (FR-019a, SC-008a).

---

## Validation matrix

### Visible output

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 1 | Launch macOS app | 1280×720 window, uniformly black content area, no toolbar/labels/graphics | SC-001, FR-006a |
| 2 | Watch launch closely, several times | No white or grey flash before the first frame | SC-001, FR-004, FR-004a |
| 3 | Launch iOS app | Black edge to edge, including under safe-area insets | SC-001, FR-003 |
| 4 | Capture a frame in the GPU debugger | Each frame contains a shader-backed draw call covering the surface — **not** a clear-only pass | SC-019, FR-002a |
| 5 | Inspect the render pass | Pipeline state and vertex buffer created once at init, reused each frame | FR-002b |
| 6 | Inspect layer configuration | `bgra8Unorm_srgb`, opaque, sRGB colour space | FR-002c |
| 40 | Run a Debug build, watch the instrumentation log | Tick count the renderer receives increases monotonically across frames, and the surface stays uniformly black | SC-020, FR-012a, FR-012b |

**Checks 1, 40 — PASS on macOS (2026-07-27).** The app launches to a 1280×720 window with a uniformly
black content area. Runtime samples, taken every 120 frames from the frame loop:

```
presented=true tickCount=60  rendererSaw=60  frameMs=0.152
presented=true tickCount=120 rendererSaw=120 frameMs=0.145
presented=true tickCount=180 rendererSaw=180 frameMs=0.189
presented=true tickCount=240 rendererSaw=240 frameMs=0.064
presented=true tickCount=300 rendererSaw=300 frameMs=0.161
presented=true tickCount=360 rendererSaw=360 frameMs=0.133
```

Three requirements evidenced at once:

- **SC-020 / FR-012a**: `rendererSaw` equals `tickCount` at every sample, so the logic→render hand-off
  carries live state every frame rather than existing as an unused type.
- **FR-021a**: 120 frames elapse per 60 ticks. The display is 120 Hz and the simulation holds exactly
  60 Hz — the fixed timestep is genuinely decoupled from refresh rate, not merely declared to be.
- **SC-003 (indicative)**: frame times 0.064–0.189 ms against an 8.3 ms budget at 120 Hz. Not the
  formal gate, which must run on the baseline devices (T047, T048).

`presented=true` throughout confirms real draw calls, not skipped frames.

> **These samples came from temporary file-based diagnostics, since `os_log` output from this app was
> not reaching `log show`.** The diagnostics have been removed; the permanent instrumentation in
> `Instrumentation.swift` remains. Getting `FR-021d`'s log output visible is outstanding work — see
> tasks.md T058.

### Window and scene behaviour

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 7 | Resize the macOS window through its full range, including full screen | Black fills exactly; no letterboxing, stretching, or non-black frames | SC-006 |
| 8 | Drag a resize handle inward past 640×360 | Window stops shrinking at the minimum | FR-006a |
| 9 | Open the File and Window menus | **No** New Window command, no Window menu entry | SC-014, FR-006c |
| 10 | Close the window | App quits; no windowless process remains (`pgrep swiftSky` returns nothing) | FR-006d |
| 11 | Rotate iOS device to portrait | App stays landscape, does not rotate | FR-006b |
| 12 | Put the iOS app in Split View on iPad | Surface fills whatever size it is given, including portrait-shaped | FR-006b |
| 13 | Minimise or fully occlude the macOS window | Frame production stops; resumes when visible | FR-008 |
| 14 | Check Xcode's run destination list | Exactly two destinations; no Mac Catalyst, no "Designed for iPad" | SC-018, FR-016a |

### Architecture

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 15 | Add `import SwiftSkyRendering` to a file in `SwiftSkySimulation`, build | **Build fails.** Revert. Record the error here. | SC-009 |
| 16 | Add `import SwiftSkyPlatform` to a file in `SwiftSkySimulation`, build | **Build fails.** Revert. Record the error here. | SC-009 |
| 17 | Add `import SwiftSkyPlatform` to a file in `SwiftSkyRendering`, build | **Build fails.** Revert. Record the error here. | SC-009 |
| 18 | Grep `Sources/SwiftSkySimulation` for `import`, `actor`, `NSLock` | No matches | FR-012c |
| 19 | Grep `Sources/SwiftSkyRendering` for `NSView`, `UIView`, `SwiftUI`, `NSWindow` | No matches | FR-010 |
| 41 | Audit the platform layer for drawing | No background colours, no `draw(_:)`/`drawRect` overrides, and no SwiftUI drawing primitives anywhere in `Sources/SwiftSkyPlatform/` except `RendererFailureNotice.swift` | SC-002, FR-001, FR-007 |
| 42 | Grep all three layers for mutable global state | No `static var`, `nonisolated(unsafe)`, or top-level `var` in any layer; no render-side interpolation in `Sources/SwiftSkyRendering/` | FR-015, FR-021c |

**Check 18 — PASS (2026-07-27).** Zero code matches for `^import`, `actor`, `@MainActor`, `NSLock`,
`DispatchQueue`, `os_unfair_lock` across all four simulation files; each file has exactly 0 import
statements. The only textual hit is the word "actor" inside a doc comment in `Simulation.swift`
explaining that the layer deliberately has none.

**Check 42 — PASS (2026-07-27).** Zero matches for `static var`, `nonisolated(unsafe)`, or top-level
`var` across all three layers. Zero matches for `interpolat`, `lerp`, `mix(` in
`Sources/SwiftSkyRendering/`.

**Check 19 — PASS (2026-07-27).** Zero matches for `NSView`, `UIView`, `SwiftUI`, `NSWindow`,
`UIWindow` in `Sources/SwiftSkyRendering/`.


> **SC-009 evidence — PASS (2026-07-27).** All three forbidden directions fail the build.
>
> **Enforcement requires `--explicit-target-dependency-import-check=error`**, which `Scripts/verify.sh`
> always passes. This was discovered the hard way: a bare `swift build` reports directions 15 and 16 as
> a *warning* from SwiftPM's dependency scanner and **exits 0**. Compiler-level warnings-as-errors does
> not reach it, because the diagnostic is not from the compiler. Only direction 17 fails without the
> flag, and then only incidentally, as a module cycle.
>
> - **Check 15** (logic → rendering): `error: 'SwiftSkySimulation' is missing a dependency on
>   'SwiftSkyRendering' because dependency scan of Swift module 'SwiftSkySimulation' discovered a
>   dependency on 'SwiftSkyRendering'`
> - **Check 16** (logic → platform): `error: 'SwiftSkySimulation' is missing a dependency on
>   'SwiftSkyPlatform' because dependency scan of Swift module 'SwiftSkySimulation' discovered a
>   dependency on 'SwiftSkyPlatform'`
> - **Check 17** (rendering → platform): `error: module dependency cycle: 'SwiftSkyRendering (Source
>   Target) -> SwiftSkyPlatform.swiftmodule -> SwiftSkyRendering.swiftmodule'`
>
> The clean build passes with the flag enabled, so enforcement costs nothing. Probe files were removed
> and the tree verified clean after each direction.

### Tests

| # | Check | Command | Expected | Criterion |
|---|-------|---------|----------|-----------|
| 20 | Headless suite | `swift test` | Passes, under 10 s, no GPU or simulator UI | SC-007, FR-017 |
| 21 | Determinism | Run the suite 10 times | Identical results every run | SC-007, SC-013 |
| 22 | Clamp behaviour | Included in suite | 10 s elapsed span advances exactly 4 ticks, not 600 | SC-013, FR-021b |
| 23 | Break a test deliberately, run `verify.sh` | Exits non-zero. Revert. | SC-008a |

**Checks 20–23 — PASS (2026-07-27).**

- **20**: `swift test` runs 23 tests in 2 suites, ~2.3 s, no GPU and no simulator UI. (Command is
  `swift test`, not `xcodebuild test` — topology B, research.md R1.)
- **21**: 10 consecutive runs, all reporting "23 tests in 2 suites passed", 23 s total wall clock.
- **22**: `tenSecondStall` asserts a 10-second span advances exactly 4 ticks. Also covered:
  clamp boundary, one-over-clamp, repeated stalls not compounding, and that a clamped frame leaves
  under one tick unconsumed so the next frame does not immediately clamp again.
- **23**: with `SimulationState().tickCount == 999` substituted, `verify.sh` exited **1**; after
  revert, exited **0**; `git diff` on `Tests/` was empty, confirming a clean revert.

### Performance (baseline devices only)

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 24 | 60 s idle session, read instrumentation log | Zero dropped frames **and** zero skipped frames; frame time within budget | SC-003, FR-027c |
| 25 | Sustained run, allocation counter | Zero heap allocations in the draw path | SC-004 |
| 26 | Idle memory footprint | Under 150 MB (iOS) / 250 MB (macOS). **Record the measured value — it becomes the baseline.** | SC-005 |
| 27 | Build Release, inspect symbols (`nm`/`strings`) | No instrumentation symbols present | SC-004a, FR-021e |

> **SC-005 baseline — fill in during implementation.** Later features are measured against these, with
> a 10% regression margin.
>
> - iOS idle footprint: `___ MB` on iPhone 11
> - macOS idle footprint: `___ MB` on MacBook Pro (16-inch, 2019)
> - iOS median frame time: `___ ms` · macOS median frame time: `___ ms`

### Concurrency

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 28 | Build with strict concurrency checking | Zero warnings | SC-015 |
| 29 | Resize continuously 10 s under Thread Sanitizer | Zero data races; no main-thread stall over one frame interval | SC-015, SC-016 |
| 30 | Sustained run under Address Sanitizer | Zero memory errors | SC-015 |
| 31 | Launch and quit 20 times, some quits mid-draw | Zero crashes, zero hangs on exit | SC-017, FR-032 |

### Failure paths

| # | Check | How | Expected | Criterion |
|---|-------|-----|----------|-----------|
| 32 | Renderer init failure | Temporarily rename a shader function so lookup fails | Text-only notice naming the cause; exits on dismissal; matching diagnostic in log; debug build traps | SC-012, FR-024, FR-026 |
| 33 | Same, with VoiceOver on | Notice is readable by the screen reader and honours Dynamic Type | SC-012, FR-025 |
| 34 | No fallback surface | Confirm the failure path never shows a black screen instead of the notice | FR-027 |
| 35 | Drawable unavailable | Force drawable acquisition to return nothing intermittently | App keeps running; skips counted separately from drops; nothing shown to user; tick count tracks elapsed time within the clamp | SC-021, FR-027a–c |

### Accessibility

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 36 | Enable VoiceOver, focus the surface | Reported with a meaningful description, not skipped or "unlabelled" | SC-011, FR-009 |
| 37 | Enable Reduce Motion | No change (nothing moves); no assertion or warning | Reduced-motion edge case |

### Dependencies

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 38 | Inspect project package dependencies | Empty | SC-010, FR-018 |
| 39 | `git status` after a build | Clean — no build artefacts or user state tracked | FR-019 |

---

## Definition of done

All 42 checks pass, and the three fill-in blocks above are completed: SC-009's compiler errors, and
SC-005's measured memory and frame-time baselines. Checks 40–42 are numbered out of sequence because
they were added by `/speckit-analyze` after the original 39; they sit in the tables where they belong
topically rather than at the end. The spec's remaining unchecked quality-checklist
items are accepted and do not block completion — see
[checklists/requirements.md](./checklists/requirements.md) Notes 1 and 2.
