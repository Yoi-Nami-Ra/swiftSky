# Implementation Plan: Metal App Shell

**Branch**: `001-metal-app-shell` | **Date**: 2026-07-26 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-metal-app-shell/spec.md`

## Summary

Stand up the swiftSky Xcode project with three compile-time-separated layers, and a real Metal
rendering path that draws a full-screen black quad through compiled shaders every frame, paced to the
display and driven from a dedicated off-main isolation domain. The user sees a black window on macOS
and a black full-screen surface on iOS; nothing else. The point is that the whole chain — project,
layer boundaries, shader compilation, pipeline state, draw submission, present, and the logic→render
hand-off — is proven working before any content exists.

Technical approach: one Xcode project, three library targets (`SwiftSkySimulation` → no dependencies,
`SwiftSkyRendering` → depends on Simulation, `SwiftSkyPlatform` → depends on both) plus two thin app
targets. SwiftUI provides only the app lifecycle and a `Window` scene hosting a `CAMetalLayer`-backed
view. A `CAMetalDisplayLink` delivers frame callbacks onto a serial `.userInteractive` queue that owns
the simulation state, advances it on a fixed 60 Hz timestep via a pure function, and calls the
renderer. See [research.md](./research.md) for the decision record.

## Technical Context

**Language/Version**: Swift 6.4, strict concurrency checking enabled (Swift 6 language mode)

**Primary Dependencies**: Metal, QuartzCore (`CAMetalLayer`, `CAMetalDisplayLink`), SwiftUI, and the
thinnest possible use of AppKit/UIKit for view hosting only. Zero third-party dependencies (FR-018).

**Storage**: N/A — no persistence in this feature

**Testing**: Swift Testing, headless, simulation library only (rendering exempt per Principle II)

**Target Platform**: iOS 26+ (iPhone, iPad — landscape only), macOS 26+ (native target only, no
Catalyst, no "Designed for iPad")

**Project Type**: Cross-platform application — shared layer libraries with thin per-platform app targets

**Performance Goals**: 60 fps / 16.6 ms per frame or the display's native rate; zero dropped frames and
zero skipped frames over a 60 s idle session; zero heap allocations in the per-frame draw path;
simulation fixed at 60 Hz with a 4-tick catch-up clamp

**Constraints**: Baseline devices are **iPhone 11** and **MacBook Pro (16-inch, 2019 — Intel)**. Idle
memory tripwire 150 MB iOS / 250 MB macOS. Main thread must never block on a frame. Instrumentation
must be provably absent from release builds.

**Scale/Scope**: ~15 source files across 3 libraries + 2 app targets + 1 test target. One window, one
renderer, one simulation instance. No assets.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.0.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Three layers separated; logic free of Metal/SwiftUI; unidirectional input→update→render; platform code behind a thin boundary; no global mutable state | **PASS** — three library targets with inward-only dependencies (FR-010–FR-015); `SwiftSkySimulation` imports nothing |
| II. Test Coverage Discipline | Tests required for non-trivial logic; deterministic and headless; visual code exempt | **PASS with recorded deferral** — simulation logic fully tested headlessly; rendering exempt; **CI clause deferred, no remote configured** (see Complexity Tracking) |
| III. Performance & Resource Efficiency | Frame budget on minimum device; no hot-path allocation; stated memory budgets; before/after measurement | **PASS** — budgets and baseline devices named above; instrumentation is FR-021d–f |
| IV. Accessibility & Platform UX | Dynamic Type, VoiceOver, contrast; reduced motion; per-platform HIG; multi-channel critical info | **PASS** — FR-009 (surface description), FR-025 (notice is Dynamic Type + screen-reader readable); reduced motion vacuous (no motion); HIG satisfied via native `Window` scene and landscape-only iOS |
| V. Simplicity & YAGNI | Simplest thing that satisfies the requirement; no speculative abstraction; dependencies justified; deviations recorded | **PASS with justified violations** — see Complexity Tracking below |

**Gate result: PASS.** No unjustified violations. Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Strengthened. R6 confirmed the platform layer needs only a bare layer-backed view; the renderer owns no window or view type at all. |
| II | **PASS with recorded deferral** | Unchanged. Swift Testing chosen (R9); still headless; CI still deferred for the same recorded reason. |
| III | **PASS** | Materially sharpened, and **the news is worse than assumed**: R2 established the macOS baseline is an *Intel* Mac, not Apple silicon. The budget still holds trivially for a black quad, but no unified-memory or Apple-GPU assumption may enter the codebase. |
| IV | **PASS** | Unchanged. |
| V | **PASS with justified violations** | **One anticipated violation removed by design.** R7 found that SwiftUI's `Window` scene delivers single-window *and* close-to-quit as platform behaviour, so FR-006c/FR-006d need no custom machinery — the spec had anticipated defensive code that turns out to be unnecessary. Remaining violations unchanged. |

**Gate result: PASS.** The design introduces no new violations and eliminates one anticipated source of
complexity.

## Project Structure

### Documentation (this feature)

```text
specs/001-metal-app-shell/
├── plan.md              # This file
├── research.md          # Phase 0 output — decision record
├── data-model.md        # Phase 1 output — entity shapes and invariants
├── quickstart.md        # Phase 1 output — validation guide
├── contracts/
│   ├── layer-interfaces.md   # The three inter-layer seams
│   └── frame-loop.md         # Loop lifecycle and event marshalling contract
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks — NOT created here)
```

### Source Code (repository root)

```text
swiftSky.xcodeproj                      # 3 library targets, 2 app targets, 1 test target

Sources/
├── SwiftSkySimulation/                 # LOGIC LAYER — imports nothing
│   ├── SimulationState.swift           # value type; holds tickCount
│   ├── FixedTimestep.swift             # tickRate (60 Hz) + catchUpClamp (4) constants
│   ├── TimeAccumulator.swift           # value type; consume(elapsed:) -> tick count
│   └── Simulation.swift                # advance(_ state:, ticks:) -> SimulationState (pure)
│
├── SwiftSkyRendering/                  # RENDER LAYER — imports SwiftSkySimulation, Metal
│   ├── Renderer.swift                  # init(device:pixelFormat:) throws; render(state:to:)
│   ├── RenderSurface.swift             # value type: pixel dimensions + backing scale
│   ├── FullscreenQuad.swift            # buffer + pipeline state, built once
│   ├── RendererError.swift             # init failure reasons, human-readable
│   └── Shaders.metal                   # vertex + fragment; fragment returns (0,0,0,1)
│
└── SwiftSkyPlatform/                   # PLATFORM LAYER — imports both + SwiftUI
    ├── FrameLoop.swift                 # serial .userInteractive queue; owns state; display link
    ├── MetalSurfaceView.swift          # NSView/UIView backed by CAMetalLayer; draws nothing
    ├── MetalSurfaceRepresentable.swift # NSViewRepresentable / UIViewRepresentable
    ├── SurfaceEvent.swift              # resize / scaleChange / visibility / terminate
    ├── RendererFailureNotice.swift     # FR-024 text-only notice
    └── Instrumentation.swift           # compiled under SWIFTSKY_INSTRUMENTATION only

Apps/
├── iOS/
│   ├── SwiftSkyApp.swift               # @main; single scene, no multi-window
│   └── Info.plist                      # landscape only; no multiple scenes; black launch screen
└── macOS/
    ├── SwiftSkyApp.swift               # @main; Window scene, defaultSize, contentMinSize
    └── Info.plist

Tests/
└── SwiftSkySimulationTests/
    ├── TimeAccumulatorTests.swift      # clamp behaviour, tick counts, SC-013
    └── SimulationTests.swift           # determinism across identical tick sequences

Scripts/
└── verify.sh                           # FR-019a: builds both destinations, runs headless suite
```

**Structure Decision**: Three library targets under `Sources/` give FR-013 its compile-time
enforcement — `SwiftSkySimulation` declares no dependencies, so a forbidden `import SwiftSkyRendering`
inside it cannot compile. App targets under `Apps/` hold only the `@main` entry point and Info.plist,
keeping FR-014's platform boundary as thin as possible: everything except the scene declaration and
plist configuration lives in shared code. `Instrumentation.swift` sits in the platform layer rather
than the render layer because the frame loop is what brackets the draw call, which keeps the render
layer free of measurement concerns.

## Complexity Tracking

> Violations of Principle V (Simplicity & YAGNI) and Principle II (CI), each justified.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **Off-main-thread frame loop** (FR-028–FR-033): dedicated serial queue, event marshalling boundary, compiler-enforced transfer safety, explicit drain-on-teardown | Chosen deliberately for CPU headroom as the simulation grows, so the frame budget is never coupled to main-thread contention or UI work | **Running the loop on the main actor** would satisfy every requirement in *this* feature with materially less machinery — no marshalling, no transfer-safety obligations, no drain ordering, and no need for SC-015–SC-017's sanitiser gates. It was explicitly considered and declined. This is the single largest source of complexity in the feature and is recorded here because Principle V requires the rejected alternative to be named, not because the choice is unsound. FR-012c/d contain the cost: the logic layer stays free of concurrency, so the complexity is confined to `FrameLoop.swift`. |
| **Debug/profiling instrumentation** (FR-021d–f, R12): a third build configuration plus a custom compilation condition | Principle III obliges *every* future hot-path feature to report before/after frame-time and allocation measurements. Without a standing mechanism each one becomes a manual profiler session that cannot be scripted or diffed. | **External profiler only** was considered and rejected: the obligation recurs indefinitely, so building the mechanism once is cheaper than paying the manual cost per feature. Arguably this is Principle III mandating machinery rather than Principle V being violated — recorded here for the reviewer to judge rather than assumed away. |
| **Shader-backed quad instead of a clear pass** (FR-002a–b): shaders, pipeline state, vertex buffer, draw call | A clear-only pass would satisfy FR-001's literal wording while leaving shader compilation, pipeline-state creation, geometry binding and draw submission entirely unexercised — defeating the feature's stated purpose and making FR-024/FR-026's named failure modes unreachable | **A clear pass** is genuinely simpler and was considered. Rejected because it defers the pipeline's first real test to the first content feature, which is exactly the coupling this feature exists to remove. The added code is a handful of lines with no ongoing cost. |
| **CI deferred** — Principle II requires headless tests *in CI* | No git remote is configured, so there is nowhere for a pipeline to run | Not a simpler-alternative trade: the requirement is **blocked**, not declined. Mitigated by FR-019a's `Scripts/verify.sh`, which does what the CI job will do and can become its body verbatim once a remote exists. Revisit when a remote is added. |
