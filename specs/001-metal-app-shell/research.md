# Phase 0 Research: Metal App Shell

**Feature**: `001-metal-app-shell` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

This resolves every open item the spec deferred to the plan, plus the API-level choices the
requirements imply but do not name. Each entry gives the decision, why, and what was rejected.

---

## R1. Module topology for build-time layer enforcement (FR-013)

> **REVISED during implementation, 2026-07-27.** The original decision and its rationale are kept
> below for the record, followed by the revision and the evidence that forced it.

**Decision (revised)**: A root `Package.swift` declaring the three layer targets —
`SwiftSkySimulation`, `SwiftSkyRendering`, `SwiftSkyPlatform` — plus the `SwiftSkySimulationTests`
test target, with a minimal hand-written `swiftSky.xcodeproj` holding only the two app targets and
referencing the package. Layer enforcement comes from package target dependencies: a target can only
`import` a module it declares as a dependency, so a forbidden import fails to compile.

**Rationale for the revision**: the original decision rested on an unverified claim — that SwiftPM
could not be relied on to compile `.metal` files in a library target. Tested empirically at
implementation time, **SwiftPM does support them**: it invokes `CompileMetalFile` and emits a resource
bundle. The stated reason for preferring hand-written Xcode targets therefore evaporated, while the
cost of that choice (authoring ~600 lines of `project.pbxproj` for five targets, with no generator
available and `xcodegen`/`tuist` both absent and forbidden by FR-018) remained. `swift test` also
satisfies SC-007's headless requirement more directly than `xcodebuild test`.

**Requires `swift-tools-version: 6.2`** — the `.iOS(.v26)` and `.macOS(.v26)` platform cases were
introduced in PackageDescription 6.2. Verified against the Swift 6.4 toolchain.

**Correction to the revision's own claim (2026-07-27).** The revision above asserted that package
target dependencies give FR-013's enforcement "more cleanly" than Xcode target dependencies. That was
wrong as stated, and testing caught it: **a bare `swift build` does not enforce the boundary.** SwiftPM
reports a forbidden cross-layer import as a warning from its dependency scanner and exits 0. Two of the
three forbidden directions built successfully; only rendering→platform failed, and incidentally, as a
module cycle. Compiler-level `treatAllWarnings(as: .error)` does not reach it, because the diagnostic
does not come from the compiler.

Enforcement requires SwiftPM's `--explicit-target-dependency-import-check=error`, which
`Scripts/verify.sh` now always passes. With it, all three directions hard-error and the clean build
still passes. The practical consequence: **the layer boundary is enforced by the verification script,
not by any `swift build` a developer happens to type.** That satisfies FR-013's intent — a violation
fails the build gate rather than passing review — but it is weaker than the "structurally impossible"
framing the plan originally used, and worth knowing before relying on it.

If stronger enforcement is ever wanted, splitting each layer into its own package would make a
forbidden import an unresolvable module rather than a suppressible diagnostic. Not done here: three
package manifests for one small app is disproportionate under Principle V while the flag works.

**Second correction — `.metal` support is build-system-specific (2026-07-30).** The revision above
states flatly that "SwiftPM does support them: it invokes `CompileMetalFile` and emits a resource
bundle." That is true of SwiftPM's **`swiftbuild`** build system — the one Xcode drives — and false of
the **`native`** build system, which is what a bare `swift build` selects by default. Under `native`,
`Shaders.metal` is reported as `found 1 file(s) which are unhandled`, no resource bundle is emitted,
`Bundle.module` is therefore never synthesised, and the build fails in `Renderer.swift` with `type
'Bundle' has no member 'module'` — an error naming a file that is not wrong.

The original verification was real; it simply did not record *which* build system produced it. The
evidence is legible after the fact from the output path: the resource bundle left behind sat under
`.build/out/`, which is `swiftbuild`'s directory, not `native`'s `.build/<triple>/debug/`.

`Scripts/verify.sh` now passes `--build-system swiftbuild` explicitly. This is the same shape of
mistake as the first correction above: a capability confirmed once, then generalised past the
configuration that produced it.

**Original decision, superseded**: a single Xcode project with three library targets plus two app
targets and one test target, chosen because Xcode targets handle `.metal` compilation as a
first-class build phase. This is still true; it simply is not exclusive to Xcode targets.

**Alternatives rejected**:

- **One app target per platform with folder conventions.** No build-time enforcement at all — a
  forbidden import would compile happily. Fails FR-013 outright.
- **Package only, no app targets.** Not viable: FR-006 requires a real Mac window, which needs an
  app target that SwiftPM cannot produce.

**Discovered blocker, unrelated to topology**: the Metal compiler is a separately downloadable Xcode
component (`xcodebuild -downloadComponent MetalToolchain`, ~690 MB). No `.metal` file can be compiled by
any route until it is installed. The Metal *framework* is present in the SDK, so Swift code that imports
Metal still compiles; only shader compilation is blocked.

**This recurred, and that is the point (2026-07-30).** The component was installed to unblock T017–T019,
then found **missing again** on the same machine on 2026-07-30 — every build stage failed. It is
environment state, not repository state, so a clean clone carries no guarantee of it and nothing in the
build fails in a way that names it. `Scripts/verify.sh` now checks for it first and prints the remedy,
because the unaided failure points at `Renderer.swift` (see the second correction under R1) and costs
real time to trace. `xcrun -f metal` is insufficient as a probe — the shim resolves to a path even when
the toolchain behind it is absent — so the check executes `xcrun metal --version`.

---

## R2. Performance-gate baseline devices (FR-023)

**Decision**:

| Platform | Baseline device | Notes |
|----------|-----------------|-------|
| iOS | **iPhone 11** (A13 Bionic, 2019) | Oldest iPhone on Apple's iOS 26 compatibility list |
| macOS | **MacBook Pro (16-inch, 2019)** — Intel | Oldest Mac on Apple's macOS Tahoe 26 compatibility list |

**Rationale**: FR-023 defines the baseline as the oldest device each supported OS runs on. The iOS
list was read directly from Apple's compatibility page and is confirmed.

**This is the most consequential research finding in the plan**: macOS 26 still supports some
**Intel** Macs, so the Mac baseline is *not* an Apple-silicon machine. Every "it's fast because it's
M-series" assumption is invalid. The 16.6 ms budget must be held on an Intel CPU with an AMD discrete
GPU, on a high-resolution display. For a black quad this is not in doubt, but it changes the frame
budget conversation for every later feature and it means the plan must not quietly assume unified
memory.

**Verification status — CONFIRMED (2026-07-28, T045).** Apple's own page still resists text
extraction (it renders its table client-side), so the confirmation is from Apple's search summary plus
two independent secondary sources. All agree:

- The only Intel MacBook Pros on the macOS 26 list are the **MacBook Pro (16-inch, 2019)** and the
  **MacBook Pro (13-inch, 2020, Four Thunderbolt 3 ports)**. The 13-inch 2019, the whole 2018 line, the
  2019 iMacs, the iMac Pro (2017) and the Mac mini (2018) are all dropped.
- macOS 26 is the last release to support any Intel Mac.

**The baseline in the table above stands unchanged.** One wording caveat, recorded rather than
silently smoothed over: the **Mac Pro (2019)** is also Intel and also 2019, so "oldest Mac on the list"
is a tie by year rather than an outright winner. `MacBook Pro (16-inch, 2019)` is unambiguously the
oldest supported *portable*, which is the machine FR-023's budget should be held on, so it remains the
right baseline. The Intel-not-Apple-silicon conclusion — the finding that actually matters — is firm.

Sources: [Apple](https://support.apple.com/en-us/122867),
[iClarified](https://www.iclarified.com/97613/macos-tahoe-supported-devices-the-full-list-of-compatible-macs),
[Mac Install Guide](https://mac.install.guide/macos/compatibility).

---

## R3. Idle memory tripwire ceiling (SC-005)

**Decision**: 150 MB on iOS, 250 MB on macOS, as resident footprint at idle.

**Rationale**: SC-005 asks for a bloat tripwire, deliberately not a tuning target. A shell of this
shape should land far below both. These numbers exist only to fire if something is badly wrong — a
leak per frame, an accidental full-screen texture allocation, a retained drawable pool. The real gate
is the measured baseline recorded at implementation time plus the 10% regression margin in the spec's
Assumptions.

**Alternatives rejected**: tighter numbers (e.g. 60/120 MB) would be guesses about an app with
nothing in it and would likely need revising in the first content feature — exactly what the spec
warned against.

---

## R4. Frame-loop scheduling and quality of service (FR-028)

**Decision**: The loop runs on a dedicated serial `DispatchQueue` with QoS `.userInteractive`, and
that queue is the loop's isolation domain.

**Rationale**: `.userInteractive` is the only class that expresses a hard per-frame deadline; anything
lower can be preempted by system work and blow the 16.6 ms budget on the Intel baseline. A serial
queue gives single-threaded semantics for the loop's state without any lock, which is what makes
FR-012c's "no locks in the logic layer" achievable.

**Alternatives rejected**:

- **`.userInitiated`** — less likely to be throttled than `.default`, still not deadline-oriented.
- **A raw `Thread` with explicit priority** — finer control, but bypasses the structured concurrency
  the rest of the codebase uses and makes FR-030's compiler-enforced transfer safety harder to obtain.
- **A custom `actor`** — reentrancy and non-FIFO execution make frame ordering harder to reason about
  than a serial queue.

---

## R5. Display-paced frame driving, off the main thread (FR-020, FR-028)

**Decision**: `CAMetalDisplayLink`, with its callback delivered onto the loop's serial queue.

**Rationale**: This is the one mechanism that satisfies both requirements simultaneously — it paces to
the display's actual refresh rate (FR-020, and the variable-refresh and Low Power Mode edge cases come
free) and it can deliver its callback on a queue we choose rather than the main thread (FR-028). It is
available well below the iOS 26 / macOS 26 floor, so no availability guards are needed.

**Alternatives rejected**:

- **`MTKView`** — drives its own draw loop on the main thread and owns the drawable lifecycle. It
  fights FR-028 directly, and its convenience is irrelevant when the view must draw nothing of its own
  (FR-001, FR-007).
- **`CVDisplayLink`** — macOS-only with no iOS counterpart, so it would force two different pacing
  mechanisms and violate FR-005's single-shared-codebase intent.
- **A timer at 60 Hz** — cannot honour actual refresh rate; breaks FR-020 and the variable-refresh
  edge case.

---

## R6. Hosting the Metal surface in SwiftUI (FR-001, FR-003, FR-007)

**Decision**: A plain `NSView`/`UIView` subclass whose backing layer is a `CAMetalLayer`, wrapped in
`NSViewRepresentable`/`UIViewRepresentable`. The view implements no drawing of its own and sets no
background.

**Rationale**: FR-007 confines the platform layer to hosting, and FR-001 forbids any pixel from a
platform-UI view. A bare layer-backed view is the thinnest thing that can present a Metal surface.
Owning the `CAMetalLayer` directly also means the loop controls drawable acquisition, which FR-027a's
skip-on-unavailable behaviour requires.

**Alternatives rejected**: `MTKView` (see R5); a SwiftUI-native drawing primitive (would violate
FR-001 by definition).

---

## R7. Single window and close-to-quit (FR-006c, FR-006d)

**Decision**: SwiftUI's `Window` scene, not `WindowGroup`.

**Rationale**: This resolves two requirements with one choice and no custom code. Apple's
documentation states that `Window` is for apps "where multiple windows are inappropriate", that it
provides no New Window command, and that **the app quits when the window is closed**. FR-006c and
FR-006d are therefore platform behaviour rather than something to implement and test defensively —
a genuine simplification over what the spec anticipated.

**Alternatives rejected**:

- **`WindowGroup` with `.commandsRemoved()`** — suppresses the menu command, but it remains a group:
  the app keeps running after the last window closes, so FR-006d would need custom termination logic.
  Strictly worse on both counts.

On iOS, multi-window is disabled by omitting multiple-scene support in the app's Info.plist
(`UIApplicationSupportsMultipleScenes = false`), which is the iPadOS half of FR-006c.

---

## R8. macOS window sizing (FR-006a)

**Decision**: `.defaultSize(width: 1280, height: 720)` on the scene, a `.frame(minWidth: 640,
minHeight: 360)` on the hosted content, and `.windowResizability(.contentMinSize)`.

**Rationale**: Confirmed against Apple's documentation. `defaultSize` sets the opening size;
`contentMinSize` derives the window's minimum from the content's minimum and imposes no maximum,
which is exactly FR-006a's "minimum enforced, aspect ratio free". Note that the system restores the
last-used size on relaunch rather than reapplying the default — expected, and not a violation.

---

## R9. Test framework (Principle II)

**Decision**: Swift Testing for the simulation test target.

**Rationale**: The constitution permits either. Swift Testing's parameterised tests map directly onto
SC-013's obligations — feeding many synthetic elapsed-time spans and asserting tick counts — with far
less boilerplate than `XCTest` subclasses. Both run headlessly, so SC-007 is unaffected.

**Alternatives rejected**: `XCTest` — no advantage here for a greenfield target; would only win if
integrating with an existing suite, and there isn't one.

---

## R10. Surface pixel format and colour space (FR-002c)

**Decision**: `CAMetalLayer` with pixel format `bgra8Unorm_srgb`, `isOpaque = true`, and the sRGB
colour space. The fragment shader returns `(0, 0, 0, 1)`.

**Rationale**: Directly implements FR-002c. An opaque layer also avoids any compositing blend that
could let something behind the surface influence a pixel, which keeps FR-001 airtight.

---

## R11. Full-screen quad geometry (FR-002a, FR-002b)

**Decision**: A four-vertex triangle strip in clip space, held in one small buffer created at
initialisation, drawn with one pipeline state created at initialisation. Vertex positions are
constant; no per-frame buffer writes.

**Rationale**: FR-002b forbids per-frame rebuilding, and FR-020 forbids per-frame allocation. Clip-
space coordinates mean the quad needs no resize-time updates at all — a surface resize changes the
viewport, not the geometry, which removes a whole class of resize bug.

**Alternatives rejected**: a three-vertex oversized "full-screen triangle" (marginally cheaper, and a
common trick, but the saving is meaningless here and the strip is easier to read); generating vertices
in the vertex shader from `vertex_id` (fewer resources, but leaves no bound-geometry path to prove,
which FR-002a explicitly wants exercised).

---

## R12. Keeping instrumentation out of release builds (FR-021e, SC-004a)

**Decision**: A dedicated `Profiling` build configuration alongside `Debug` and `Release`, with the
instrumentation compiled under a custom Swift condition (`SWIFTSKY_INSTRUMENTATION`) set for `Debug`
and `Profiling` only. SC-004a is verified by inspecting the release binary's symbols, not the source.

**Rationale**: FR-021e demands provable absence, and `#if DEBUG` alone cannot express "debug and
profiling but not release". A named condition makes the intent explicit and greppable.

---

## R13. Landscape-only iOS and black launch appearance (FR-006b, FR-004a)

**Decision**: Info.plist supported orientations limited to `UIInterfaceOrientationLandscapeLeft` and
`UIInterfaceOrientationLandscapeRight`; launch screen configured via the `UILaunchScreen` dictionary
with a black background colour and no image; the macOS window's background set black.

**Rationale**: FR-006b and FR-004a. The launch-screen default would show a light background, which is
precisely the flash FR-004 forbids — so this is a required configuration, not a cosmetic one.

---

## R14. Restricting Mac destinations (FR-016a)

**Decision**: The iOS target's Supported Destinations list is limited to iPhone and iPad. "Mac
(Designed for iPad)" is removed and Mac Catalyst is not enabled. The macOS app target is the only
Mac path.

**Rationale**: FR-016a and SC-018. This is a project-configuration default that must be actively
turned off, which is why the spec called it out.

---

## Open items deliberately left to implementation

- ~~The exact oldest macOS 26 Mac model (R2)~~ — **closed 2026-07-28 (T045)**: confirmed as
  `MacBook Pro (16-inch, 2019)`, unchanged. See R2's verification status.
- Measured idle memory and frame-time baselines — these are *outputs* of implementation (SC-005),
  recorded once the app runs on the baseline devices.
- The `.metal`-in-library-target risk (R1) with its documented fallback.

## Sources

- [iPhone models compatible with iOS 26 — Apple Support](https://support.apple.com/guide/iphone/iphone-models-compatible-with-ios-26-iphe3fa5df43/ios)
- [macOS Tahoe 26 is compatible with these computers — Apple Support](https://support.apple.com/en-us/122867)
- [SwiftUI `Window` — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/window)
- [`Scene.defaultSize(_:)` — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/scene/defaultsize%28_%3A%29)
- [`Scene.windowResizability(_:)` — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/scene/windowresizability%28_%3A%29)
- [`Scene.commandsRemoved()` — Apple Developer Documentation](https://developer.apple.com/documentation/swiftui/scene/commandsremoved%28%29)
