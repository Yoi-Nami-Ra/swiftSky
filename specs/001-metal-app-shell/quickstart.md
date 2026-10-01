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

Builds both destinations and runs the headless suite. Exits non-zero on any failure, **including on any
stage that exits 0 but emits a `warning:` line** — that gate is what enforces SC-015 (see check 28).
This is the body a CI job will use verbatim once a remote exists (FR-019a, SC-008a).

**One prerequisite the script cannot satisfy for itself**: Xcode 26 ships the Metal compiler as a
separately downloadable component, so a complete Xcode plus a clean clone is still not enough to compile
`Shaders.metal`. The script checks for it first and names the remedy:

```bash
xcodebuild -downloadComponent MetalToolchain
```

It is checked because the failure without it is actively misleading — SwiftPM stops treating
`Shaders.metal` as compilable, no resource bundle is emitted, and the build dies in `Renderer.swift`
complaining that `Bundle` has no member `module`. That was observed for real on 2026-07-30, when the
component was found missing on a machine where everything had previously built.

---

## Validation matrix

### Visible output

> **Since 003-debug-overlay**: a Debug or Profiling build shows the live debug overlay by default.
> Launch with `--no-debug-overlay` for every check below that expects a uniformly black surface.
> Release builds are unaffected.

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

**Check 3 — PASS on iOS (2026-07-28).** iPhone 17 Pro simulator, iOS 27.0, Debug build. Screenshot
captured with `xcrun simctl io booted screenshot` and every pixel counted programmatically:

```
ios-check3.png: 2622x1206  pixels=3162132  nonBlackPixels=0  maxRGB=(0,0,0)
```

All 3,162,132 pixels are exactly (0, 0, 0) — the full device framebuffer, so this covers the
safe-area insets and the notch region, not merely the layout-guide area. Repeated on the iPad Pro 11"
simulator (iOS 27.0): `1668x2420 pixels=4036560 nonBlackPixels=0 maxRGB=(0,0,0)`.

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

**Check 11 — PASS (2026-07-28).** Verified by putting the *device* in portrait and observing that the
app refuses to follow. The simulator's persisted device orientation was set to Portrait, confirmed by
capturing the home screen first:

```
home-portrait.png   1206 x 2622   (portrait — the device really is rotated)
ios-check11.png     2622 x 1206   (the app, landscape, on that same portrait device)
                    pixels=3162132 nonBlackPixels=0 maxRGB=(0,0,0)
```

The app presents landscape on a portrait device and stays uniformly black. This is stronger evidence
than a rotation gesture would have been: the device was already portrait *before* the app launched, so
there was no landscape state to merely persist.

**Check 12 — NOT VERIFIED (2026-07-28). Blocked, not failed.** Entering Split View needs an
interactive drag from the dock, and no UI-automation path is available in this environment: the
simulator-control MCP cannot load (`SimulatorKit.framework` is absent from the Xcode 27.0 Beta 4
bundle), `xcrun simctl` has no input-injection or orientation subcommand, and AppleScript UI scripting
is refused (`Not authorized to send Apple events to System Events`, error -1743) because Accessibility
permission is not granted. Granting it is a system-settings change.

Partial evidence that does exist: the same shared `MetalSurfaceView` filled two differently shaped
surfaces black with no code change (iPhone 2622×1206, iPad 1668×2420), and `MetalSurfaceView`
recomputes `drawableSize` from `bounds` on every `layoutSubviews`, with a zero-area surface handled as
a routine state rather than an error. **To finish this check**, run the app on an iPad, drag a second
app in from the dock to make Split View, and drag the divider to the 1/3 width where the surface
becomes portrait-shaped.

**Check 14 — PASS after a fix (2026-07-28).** It failed first. The iOS scheme offered:

```
{ platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:…, name:My Mac }
```

with no `error:` attached, meaning it was an *eligible* run destination — exactly what FR-016a and
SC-018 forbid. T008 had set `SUPPORTED_PLATFORMS` and `TARGETED_DEVICE_FAMILY` but never the two
settings that actually control this, which default to enabled. Adding
`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO` and `SUPPORTS_MACCATALYST = NO` to all three iOS build
configurations fixes it. The eligible list is now exactly:

```
{ platform:iOS, …, name:Any iOS Device }
{ platform:iOS Simulator, …, name:Any iOS Simulator Device }
```

No Catalyst row, no "Designed for" row. The remaining macOS and tvOS rows all carry
`error:… platform doesn't match swiftSky.app's supported platforms`, so they are ineligible.

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

**Check 41 — PASS after a fix (2026-07-28).** It failed first. The audit found
`GameSurfaceView.swift:57` painting `Color.black.ignoresSafeArea()` in a pre-setup branch — a SwiftUI
drawing primitive in the platform layer, outside `RendererFailureNotice.swift`, which is precisely
what SC-002 forbids. The branch justified itself as "launch appearance", but FR-004a's exception is
written for *the OS's* pre-first-frame appearance (iOS launch screen, macOS initial window
background), not for a view the app draws.

Fixed by removing the branch entirely: renderer construction is now a lazy `@MainActor` property on
`LoopHost`, so `body` has a resolved `Result` to switch on from its first evaluation and has no
third state to fill. The pre-first-frame appearance is now taken where the spec puts it — and the
macOS half of that had to be corrected too, because the plist's `NSRequiresAquaSystemAppearance
= false` only forces *dark* appearance, whose window background is dark grey. Grey is a non-black
frame under FR-004. `MetalSurfaceView.configureWindowBackground()` now sets the window black.

Post-fix audit — grep for `backgroundColor|NSColor|UIColor|draw(|.background(|Rectangle(|Color.`
across `Sources/SwiftSkyPlatform/`, excluding `RendererFailureNotice.swift` — leaves two matches, both
inspected and neither user-visible drawing:

| Match | Verdict |
|-------|---------|
| `MetalSurfaceView.swift:45` `metalLayer.backgroundColor = nil` | *Disables* a background rather than drawing one. Keeps FR-001 airtight. |
| `MetalSurfaceView.swift:157` `window?.backgroundColor = .black` | The window, not a view — FR-004a's named exception, taken literally. |

Zero SwiftUI drawing primitives, zero `draw(_:)`/`drawRect` overrides, zero view background colours.


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
| 20 | Headless suite | `swift test --build-system swiftbuild` | Passes, under 10 s, no GPU or simulator UI | SC-007, FR-017 |
| 21 | Determinism | Run the suite 10 times | Identical results every run | SC-007, SC-013 |
| 22 | Clamp behaviour | Included in suite | 10 s elapsed span advances exactly 4 ticks, not 600 | SC-013, FR-021b |
| 23 | Break a test deliberately, run `verify.sh` | Exits non-zero. Revert. | SC-008a |

**Checks 20–23 — PASS (2026-07-27).**

- **20**: `swift test` runs 23 tests in 2 suites, ~2.3 s, no GPU and no simulator UI. (Command is
  `swift test`, not `xcodebuild test` — topology B, research.md R1.)

**Check 20 — command corrected (2026-07-30).** `swift test` alone does **not** work, and did not on
2026-07-27 either; the original evidence was gathered through a build system the recorded command does
not select. SwiftPM's default `native` build system does not compile `.metal` sources — it reports
`found 1 file(s) which are unhandled` for `Shaders.metal`, emits no resource bundle, so `Bundle.module`
is never synthesised, and the build dies in `Renderer.swift:43` with `type 'Bundle' has no member
'module'` — naming a file that is not wrong. `--build-system swiftbuild` (what Xcode drives) compiles it.
research.md R1's verification of SwiftPM `.metal` support holds for that build system only.

Confirmed by artefact path: the resource bundle left from the 2026-07-28 session sat under `.build/out/`,
which is `swiftbuild`'s output directory, not `native`'s `.build/<triple>/debug/`.

Re-verified 2026-07-30 with the corrected command: 23 tests in 2 suites pass, exit 0. Determinism
(check 21) re-confirmed over 10 consecutive runs, all reporting "23 tests in 2 suites passed".
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

> **SC-005 baseline — STILL OPEN. The baseline devices are not available here.** Later features are
> measured against these, with a 10% regression margin.
>
> - iOS idle footprint: `___ MB` on iPhone 11 — **not measured**, no iPhone 11 available
> - macOS idle footprint: `___ MB` on MacBook Pro (16-inch, 2019) — **not measured**, no Intel Mac
>   available
> - iOS median frame time: `___ ms` · macOS median frame time: `___ ms` — **not measured**
>
> These four numbers are the feature's only genuinely outstanding deliverable. They cannot be
> substituted with numbers from other hardware: R2 established that the macOS baseline is an *Intel*
> Mac with a discrete GPU, and a measurement taken on Apple silicon would be a different machine's
> answer wearing the baseline's label — worse than a blank, because later features would regress
> against it and appear fine.

**Checks 24, 25, 26 — measured on NON-BASELINE hardware (2026-07-28). Indicative only; the gate above
remains open.** Machine: MacBook Pro 18,1 (Apple M1 Pro), macOS 26.5, 120 Hz ProMotion display, Debug
build with instrumentation. 60-second idle session:

```
frames=9240 skipped=0 dropped=0 mean=0.159545ms worst=7.651917ms budget=8.333333ms ticks=4629
phys_footprint: 101 MB   phys_footprint_peak: 129 MB
```

- **Check 24**: zero dropped and zero skipped across the whole session, against a budget of 8.333 ms —
  the display's true interval, not the 16.6 ms default. See the SC-003 note below.
- **Check 26**: 101 MB resident against the 250 MB macOS tripwire. A Debug build with instrumentation
  compiled in, so a Release figure would be lower.
- **Check 25** (zero heap allocations in the draw path) — **iOS: PASS (2026-10-01, 011); macOS: PASS
  (2026-10-01, SKY-4)**. FR-021d's allocation counter was built by `specs/011-draw-allocation-counter` and reports in
  this summary line (`allocs= allocframes= eventallocs= gfxallocs=`). iPhone 17 Pro simulator (iOS 27.0),
  an optimised build with the counter compiled in (Release plus the instrumentation condition on the
  command line — a Profiling build carries no instrumentation, 011 research R1, R12), default launch
  arguments, 60 s idle: `allocation counter ready`, then all 21 summaries `allocs=0 allocframes=0
  eventallocs=0`, e.g. `frames=1196 skipped=0 dropped=0 mean=0.201342ms worst=2.388417ms
  budget=16.666667ms ticks=1691 allocs=0 allocframes=0 eventallocs=0 gfxallocs=3360`. Metal allocates
  28 times per frame internally (`gfxallocs ÷ frames`, 28.0 in every summary), recorded as a reference,
  not a gate. Getting there fixed one real per-frame allocation: the text renderer's completion handler
  was re-bridged and heap-copied on every frame with text (011 research R13). How to repeat it:
  `specs/011-draw-allocation-counter/quickstart.md`, "The method".
  macOS (SKY-4), by the same method: Apple M1 Pro, macOS 26.7, 120 Hz display, the same optimised
  build of `swiftSky (macOS)`, no launch arguments, 62 s idle: `allocation counter ready`, then all 62
  summaries `allocs=0 allocframes=0`, `budget=8.333333ms` throughout. `eventallocs=2` in the first
  summary (start-up events), 0 in the other 61. Last summary: `frames=7434 skipped=0 dropped=0
  mean=0.161551ms worst=6.112208ms budget=8.333333ms ticks=3751 allocs=0 allocframes=0 eventallocs=0
  gfxallocs=1200`. Metal's per-frame reference on this Mac: 10.0 (`gfxallocs ÷ frames`, lowest 10.0,
  highest 10.0). No fix was needed: 011's R13 fix had already removed the one per-frame allocation the
  macOS run had shown (`allocs=120` per 120 frames before it).

> **The frame budget was wrong until 2026-07-28, and the gate was passing because of it.** It was
> hardcoded to 1/60 and `Instrumentation.updateBudget` was never called, so on this 120 Hz display a
> 12 ms frame missed its deadline without being counted as dropped. `FrameLoop` now learns the interval
> from the display link. Measured distribution of inter-frame gaps on this panel: p10 = median = p90 =
> exactly 8.333333 ms, max 16.67 ms (an occasional missed frame). The learner takes the *minimum* gap,
> because gaps are whole multiples of the interval and a missed frame can only ever double one — so a
> dropped frame cannot inflate the budget meant to catch it. A second agreeing sighting is required
> before a shorter gap is adopted, after an early run locked onto a spurious 5.18 ms startup gap.
>
> A related inconsistency surfaced in the same output: `worst=11.0ms dropped=0 budget=8.3ms`, which is
> self-contradictory. That worst frame had been judged against the old 16.6 ms default before the
> budget narrowed. `updateBudget` now resets the counters, so every number in a summary line belongs to
> one budget.

**Check 27 — PASS (2026-07-28).** Release build, `swiftSky.app/Contents/MacOS/swiftSky` (arm64):

| Probe | Count |
|-------|-------|
| `recordPresented`, `recordSkipped`, `updateBudget`, `summary` symbols | **0** |
| `SWIFTSKY_INSTRUMENTATION` in strings | **0** |
| log format strings `skipped=`, `dropped=`, `worst=` | **0** |
| symbols matching `Instrumentation` (unstripped) | 16 |
| symbols matching `Instrumentation` (after `strip -rSTx`) | **1** |

Every piece of measurement *behaviour* is absent: no counter methods, no logging, no format strings,
no compilation-condition marker. What survives unstripped is type metadata and debug-map entries for a
struct that, in Release, has no members at all; after stripping, a single Objective-C ivar *name*
(`_OBJC_IVAR_$_SwiftSkyPlatform.FrameLoop` with suffix `.instrumentation`), because `FrameLoop` derives
from `NSObject` and its stored property becomes an ivar. Driving that last name to zero would mean
`#if`-ing the property and its seven call sites through `FrameLoop`, trading Principle V's simplicity
for a symbol that carries no instrumentation. Recorded as a judgement, not hidden.

### Concurrency

| # | Check | Expected | Criterion |
|---|-------|----------|-----------|
| 28 | Build with strict concurrency checking | Zero warnings | SC-015 |
| 29 | Resize continuously 10 s under Thread Sanitizer | Zero data races; no main-thread stall over one frame interval | SC-015, SC-016 |
| 30 | Sustained run under Address Sanitizer | Zero memory errors | SC-015 |
| 31 | Launch and quit 20 times, some quits mid-draw | Zero crashes, zero hangs on exit | SC-017, FR-032 |

**Check 28 — PASS after a fix (2026-07-30). The previous PASS was wrong, and its reasoning was the
reason it was wrong.**

That earlier entry argued: warnings-as-errors is on, so a strict-concurrency warning would be a build
failure, so "zero warnings" cannot drift. Every step is true and the conclusion still did not hold,
because the build was **failing for an unrelated reason before any Swift file compiled**. Re-verifying
on 2026-07-30 found:

1. `.treatAllWarnings(as: .error)` in `Package.swift` conflicts with the `-suppress-warnings` Xcode
   passes to package targets — `error: conflicting options '-warnings-as-errors' and
   '-suppress-warnings'`. **Both app targets failed to build outright.**
2. The command-line `swift build`/`swift test` path failed even earlier, in `Renderer.swift`, because
   SwiftPM's default `native` build system does not compile `.metal` (see check 20).
3. So neither path ever reached `SwiftSkyPlatform` — and it held three genuine violations:

```
MetalSurfaceRepresentable.swift:28:20: warning: call to main actor-isolated initializer 'init(device:)' in a synchronous nonisolated context
MetalSurfaceRepresentable.swift:29:14: warning: main actor-isolated property 'onSurfaceChange' can not be mutated from a nonisolated context
MetalSurfaceRepresentable.swift:29:44: warning: main actor-isolated property 'metalLayer' can not be referenced from a nonisolated context
```

Cause: `makeSurfaceView()` sits in the nonisolated `struct MetalSurface` body while touching
main-actor-isolated `NSView`/`UIView` members. The isolation conferred by
`NSViewRepresentable`/`UIViewRepresentable` reaches `makeNSView`/`makeUIView` in the extensions, not the
struct's own declaration — a conformance declared in an extension does not isolate the original type.

Fixed by annotating `makeSurfaceView()` `@MainActor`. The gate was moved too: warnings-as-errors is
gone from `Package.swift` (it cannot coexist with Xcode's package build) and `Scripts/verify.sh` now
fails any stage that emits a `warning:` line, which covers the SwiftPM *and* xcodebuild paths that the
manifest setting could not.

**The lesson worth keeping**: a mechanical gate is only as good as its reachability. This one broke the
build for an unrelated reason and thereby hid exactly what it existed to catch, while presenting as
enforcement. When a gate's failure mode is "the build fails," a green build is evidence; a *red* build
is not evidence that the gate is working.

**The new gate then immediately earned its place.** On its first run it failed the iOS stage — which had
exited 0 — on a warning nothing else had surfaced:

```
warning: 'UIRequiresFullScreen' has been deprecated starting in iOS 26.0 and will be ignored in a
future release. (in target 'swiftSky (iOS)')
```

`Apps/iOS/Info.plist` carried `UIRequiresFullScreen = false`. That key appears nowhere in spec.md,
plan.md, research.md, or tasks.md — T036 specifies three keys for this file and this is not one of them
— and `false` is already the iOS 26 default, so it changed no behaviour while contradicting FR-022's
"no availability fallbacks below the floor". Removed, with a note in the plist against re-adding it;
iPad multitasking sizes are handled in code per T037 regardless.

Post-fix: `swift build`, `swift test`, and both `xcodebuild` schemes each exit 0 with zero `warning:`
lines, from a clean `.build` — `verify.sh` reports `VERIFICATION PASSED`.

**Live-run re-confirmation (2026-07-30).** Because the fix touched the view-creation path, the macOS app
was run for ~10 s to confirm it still renders rather than merely compiles:

```
frames=113 skipped=0 dropped=3 mean=7.615262ms worst=495.790667ms budget=8.333333ms ticks=174
frames=473 skipped=0 dropped=3 mean=1.951242ms worst=495.790667ms budget=8.333333ms ticks=356
frames=953 skipped=0 dropped=3 mean=1.045552ms worst=495.790667ms budget=8.333333ms ticks=609
```

953 frames on a 120 Hz display, `ticks` advancing at 60 Hz as the fixed timestep requires, mean frame
time converging to ~1 ms against an 8.33 ms budget, `skipped=0`.

**Two things here are not clean and should not be read as passing:**

- `dropped=3`, with `worst=495.79 ms`. Both are launch artefacts — the count is already 3 at the first
  sample and never rises again, and 496 ms is window and pipeline creation. But SC-003 says *zero*
  dropped frames, and this run does not show zero. T048's recorded "0 dropped / 0 skipped over 60 s"
  was presumably measured after warm-up; whether launch frames are in scope for SC-003 is an open
  question, not one this entry settles.
- The log format no longer matches what check 40 records (`presented=… tickCount=… rendererSaw=…
  frameMs=…`). The T048/T058 fixes changed it to the aggregate form above. `ticks=` still evidences the
  logic→render hand-off, but check 40's literal transcript is stale.

**Check 28 — PASS again after a gate exemption (2026-09-30), Xcode 27.0 RC (27A266a), Swift 6.4.**
On this toolchain `verify.sh` failed from a clean `.build`: `swift build` and `swift test` both exited 0
but printed

```
warning: missing creator for mutated node: ('<repo>/.build/out/Products/Debug/swiftSky_SwiftSkyRendering.bundle/Contents/MacOS')
```

This is not a concurrency warning, and not a code defect. It comes from swiftbuild's build-graph checks,
not from the compiler. Because the resource bundle's Sources phase compiles `Shaders.metal`, swiftbuild
treats the bundle as holding a binary, so its CodeSign task lists `Contents/MacOS`
(`$(EXECUTABLE_FOLDER_PATH)`) as a node it mutates. A resource bundle has no executable, so no task
creates that folder. The generated build manifest confirms it: there are MkDir tasks for the bundle,
`Contents` and `Contents/Resources`, but none for `Contents/MacOS`. Our `Package.swift` declaration is
not the cause. A minimal package with a single `.metal` resource warns identically, whether the file is
picked up implicitly or declared with `.process`, and the same package with a `.txt` resource (`.process`
or `.copy`) builds clean. An upstream fix, swiftlang/swift-build#1789, was closed unmerged on 2026-09-24.

The source-level workarounds would change the shader pipeline itself, by checking in a precompiled
`.metallib` or compiling the shader source at runtime. Neither is worth trading for a log line. Instead,
`run_stage` in `Scripts/verify.sh` exempts exactly this line: the whole line must match, and the path
must end in `swiftSky_SwiftSkyRendering.bundle/Contents/MacOS`. Every other `warning:` line still fails
the stage. **Remove the exemption once a toolchain builds without it.**

Post-change: `./Scripts/verify.sh` from a clean `.build` reports `VERIFICATION PASSED`.

**Check 30 — PASS (2026-07-28).** Address Sanitizer build, 35-second sustained run: 2,994 frames,
zero ASan reports, zero bytes on stderr.

**Check 29 — PARTIAL (2026-07-28).** Thread Sanitizer build, 30-second sustained run: 3,120 frames,
**zero data races**, zero TSan reports, no log files emitted. The *continuous-resize* half of the check
is **not verified** — dragging a resize handle for 10 s needs UI automation, blocked for the same
reason as check 12 (Accessibility permission is not granted). Resize handling is the code path most
likely to race, since it is the one that crosses the main-thread → loop boundary, so this gap is worth
closing by hand: run the TSan scheme and drag a corner continuously for 10 seconds.

**Check 31 — PASS (2026-07-28), both platforms.**

- **macOS**: 20 consecutive launch/quit cycles, quits issued by Apple event. Odd cycles quit after the
  loop had settled (2 s), even cycles at 0.35 s — mid-draw, before the first instrumentation summary.
  20/20 exited cleanly, 843–2106 ms each, **zero hangs** (3 s cutoff) and **zero crash reports** in
  `~/Library/Logs/DiagnosticReports` before or after.
- **iOS**: 20 `simctl launch` / `simctl terminate` cycles on the iPhone 17 Pro simulator, same
  alternating settled/mid-draw timing. `FAILURES=0`, and zero `.ips` crash reports on the device.

### Failure paths

| # | Check | How | Expected | Criterion |
|---|-------|-----|----------|-----------|
| 32 | Renderer init failure | Temporarily rename a shader function so lookup fails | Text-only notice naming the cause; exits on dismissal; matching diagnostic in log; debug build traps | SC-012, FR-024, FR-026 |
| 33 | Same, with VoiceOver on | Notice is readable by the screen reader and honours Dynamic Type | SC-012, FR-025 |
| 34 | No fallback surface | Confirm the failure path never shows a black screen instead of the notice | FR-027 |
| 35 | Drawable unavailable | Force drawable acquisition to return nothing intermittently | App keeps running; skips counted separately from drops; nothing shown to user; tick count tracks elapsed time within the clamp | SC-021, FR-027a–c |

**Check 35 — PASS (2026-07-28).** `Renderer.render` was temporarily made to return `false` on every
third frame, simulating intermittent drawable-acquisition failure. After 20 s:

```
frames=76 skipped=38 dropped=0 mean=0.200223ms worst=1.184625ms budget=8.333333ms ticks=124
```

- **App keeps running**: window still present at 1280×720, alpha 1, no crash.
- **Skips counted separately from drops**: `skipped=38` against `presented=76` is exactly the 2:1 ratio
  a fail-every-third-frame injection produces, and `dropped=0` — the two counters did not merge.
- **Nothing shown to the user**: zero `renderer` diagnostics logged, no failure notice, no change in
  what is on screen.
- **Tick count tracks elapsed time**: ticks continued advancing at 60 Hz through the skips rather than
  following the presented-frame count, which is FR-027b's "retain accumulated time" holding.

Change reverted; `git status` clean on `Sources/SwiftSkyRendering/`.

**Checks 32, 34 — PASS (2026-07-28). Check 33 — NOT VERIFIED.** The fragment shader entry point was
temporarily renamed to `swiftsky_quad_fragment_RENAMED_T052` so function lookup fails at init.

- **Debug build**: exits with code **133** (SIGTRAP) — FR-026's debug trap — printing
  `Fatal error: Renderer initialisation failed: shader_function_missing — swiftSky's shader library is
  missing the function "swiftsky_quad_fragment". The installation may be incomplete.` The cause is
  named, not a generic failure.
- **Diagnostic (FR-026)**: logged at `Error` level in both Debug and Release:
  `[com.swiftsky.app:renderer] renderer initialisation failed code=shader_function_missing detail=…`
- **Release build**: does **not** trap. The process stays alive with a 1280×720 window on screen
  (confirmed via `CGWindowListCopyWindowInfo`: `owner=swiftSky layer=0 bounds=1280×720 alpha=1`), which
  is the notice being presented rather than the app dying.
- **Check 34 (no fallback surface)**: structural and now airtight. `GameSurfaceView.content` has
  exactly two branches — `.success` → the Metal surface, `.failure` → the notice. Since the fix
  recorded under check 41 removed the third branch, there is no longer any code path that can render
  black when the renderer is unavailable.
- **Check 33 is NOT verified**: reading the notice with VoiceOver, and clicking Dismiss to confirm it
  exits, both need UI automation — blocked as in check 12. `screencapture` is also refused
  (`could not create image from display`; Screen Recording permission not granted), so the notice's
  appearance was not visually inspected either. Code-level: the notice is `Text`-only with `.headline`
  and `.body` fonts (Dynamic Type by default), no images or shapes, and carries
  `.accessibilityElement(children: .contain)`, `.accessibilityLabel`, `.accessibilityValue`.

Change reverted; `git status` clean on `Sources/SwiftSkyRendering/`.

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

**Checks 36, 37 — NOT VERIFIED (2026-07-28).** Both need VoiceOver running and observed, and check 37
needs Reduce Motion toggled — a system accessibility setting. Neither is available here.

What is verified structurally: `MetalSurfaceView.configureAccessibility()` sets
`setAccessibilityElement(true)` / `.image` role / label `"swiftSky game surface"` on macOS and the
`isAccessibilityElement` / `.image` traits / same label on iOS, so the surface is not an unlabelled
region by construction (FR-009). For check 37, the reduced-motion requirement is vacuous by
construction rather than by handling: the app contains no animation, transition, or interpolation of
any kind — check 42 already confirms zero `interpolat`/`lerp`/`mix(` in the render layer — so there is
nothing for the setting to change. **To finish these**, enable VoiceOver, focus the surface, and
confirm it is announced; then enable Reduce Motion and confirm no assertion fires.

**Check 38 — PASS (2026-07-28).** Zero third-party dependencies. `Package.swift` declares no
`dependencies:` on the package itself (only inter-target ones: Rendering → Simulation, Platform →
both, Tests → Simulation). `swiftSky.xcodeproj` contains **0** `XCRemoteSwiftPackageReference` entries
and exactly one `XCLocalSwiftPackageReference` pointing at `.`. No `Package.resolved` exists, which is
itself the tell: there is nothing external to resolve.

**Check 39 — PASS (2026-07-28).** `git status --porcelain` is empty after full Debug, Release, TSan
and ASan builds of both schemes plus `swift build` and `swift test`. `.gitignore` covers
`DerivedData/`, `.build/`, `xcuserdata/`, `*.xcodeproj/xcuserdata/` and
`*.xcodeproj/project.xcworkspace/xcuserdata/`.

---

## Definition of done

All 42 checks pass, and the three fill-in blocks above are completed: SC-009's compiler errors, and
SC-005's measured memory and frame-time baselines. Checks 40–42 are numbered out of sequence because
they were added by `/speckit-analyze` after the original 39; they sit in the tables where they belong
topically rather than at the end. The spec's remaining unchecked quality-checklist
items are accepted and do not block completion — see
[checklists/requirements.md](./checklists/requirements.md) Notes 1 and 2.

### Status roll-up (2026-07-28)

**31 of 42 checks recorded as PASS. 11 remain open, and none of them failed** — every one is blocked
on something this environment cannot provide. Two checks passed only *after* a defect they exposed was
fixed (14 and 41), and a third gate (24) was passing for the wrong reason until the frame budget was
corrected.

Since then, check 25 has passed on both platforms (iOS 2026-10-01 in 011, macOS 2026-10-01 in SKY-4)
and is no longer open.

| # | Check | Why it is still open |
|---|-------|----------------------|
| 2 | No flash on launch | Needs a human watching, or screen recording (permission not granted) |
| 4 | GPU frame capture shows a draw call | Needs Xcode's GPU debugger, interactive |
| 5 | Pipeline state built once | Same; structural evidence in `FullscreenQuad` |
| 7, 8 | Resize range, minimum size | Needs interactive window dragging |
| 9, 10 | Menus, close-to-quit | Needs menu inspection / window close; Accessibility permission denied |
| 12 | iPad Split View | Needs an interactive dock drag |
| 29 | Continuous resize under TSan | Race half PASSES; the resize half needs UI automation |
| 33 | Notice under VoiceOver, dismiss exits | Needs VoiceOver and a click |
| 36, 37 | VoiceOver on the surface, Reduce Motion | Needs VoiceOver and a system settings change |

The common blocker for most of these is that Accessibility (UI scripting) and Screen Recording
permission are not granted to this session, so nothing can drive or capture the UI:
AppleScript returns `-1743`, `screencapture` returns `could not create image from display`, and the
simulator-control MCP cannot load at all because
`SimulatorKit.framework` is missing from the Xcode 27.0 Beta 4 bundle. `xcrun simctl` has no
input-injection subcommand. These are environment limits, not product defects — the same checks are a
few minutes of manual work for someone at the keyboard.

Separately, **SC-005's four baseline numbers cannot be produced on any hardware available here** and
are the feature's one substantive outstanding deliverable. See the SC-005 block above for why
substituting Apple-silicon numbers would be worse than leaving them blank.
