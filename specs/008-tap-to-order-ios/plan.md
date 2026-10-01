# Implementation Plan: Tap to Order the Ship on iOS

**Branch**: `008-tap-to-order-ios` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-tap-to-order-ios/spec.md`

## Summary

A tap on the iOS game surface becomes the ship's move order. A `UITapGestureRecognizer` on
`MetalSurfaceView` reads the tap's position in view points and posts a new
`SurfaceEvent.moveOrderRequested(MoveOrderRequest)` through the frame loop's existing queue. At the
next frame boundary, in queue order, the loop applies the request: the camera for the surface the
loop has applied, view → world, then `SimulationState.setOrder(to:)`. The autopilot does the rest.
`MoveOrderRequest` is a pure, platform-neutral value, tested headlessly and reused by SKY-11. The
surface allows VoiceOver direct interaction. Debug builds log each order and arrival.

**Technical approach**:
- **Channel** (R1): one FIFO for surface events and taps, so ordering against a resize is free.
- **Conversion** (R2, R3): in the loop, against the applied surface, in a pure
  `MoveOrderRequest.apply(to:on:)` that returns an outcome.
- **Recognition** (R4): the system tap recogniser, one tap and one finger, iOS only.
- **Accessibility** (R5): `.allowsDirectInteraction` added to the surface's traits.
- **Logging** (R6): two `Instrumentation` methods, Debug and Profiling only.

The logic and rendering layers do not change. See [research.md](./research.md) for the decision record.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: Apple frameworks only. UIKit's `UITapGestureRecognizer` in the platform layer
(already imports UIKit). No third-party dependencies.

**Storage**: N/A.

**Testing**: Swift Testing, headless: a new `MoveOrderRequestTests` suite in `SwiftSkyPlatformTests`,
whose target gains `SwiftSkyRendering` and `SwiftSkySimulation` dependencies (R8). Run through
`Scripts/verify.sh`. The Metal-device guard stays. Gesture recognition, VoiceOver and logging are
verified in the quickstart.

**Target Platform**: iOS 26+ (iPhone and iPad) for the tap; macOS 26+ builds the shared types.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: Frame budget unchanged (001 SC-003). Per frame without a tap: one enum
comparison for arrival logging, in Debug only. Per tap: a camera build, two subtractions and one
autopilot evaluation (R9).

**Constraints**: No per-frame allocation on frames without a tap (FR-011). The main thread never
blocks (FR-004). The logic layer sees only a world point (FR-009). Release contains no order logging.

**Scale/Scope**: New: `Sources/SwiftSkyPlatform/MoveOrderRequest.swift`,
`Tests/SwiftSkyPlatformTests/MoveOrderRequestTests.swift`. Changed: `SurfaceEvent.swift`,
`FrameLoop.swift`, `MetalSurfaceView.swift`, `Instrumentation.swift`, `Package.swift` (test-target
dependencies), `CLAUDE.md`, `.tickets/10.yaml`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. Input → simulation → render, for the first time end to end. The tap is recognised and converted in the platform layer; the logic layer receives a world point through its existing `setOrder(to:)` and changes nothing (FR-009). |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command | **PASS**. The conversion and the order application are pure and tested headlessly (FR-013). Gesture glue is platform code, verified in the quickstart. `verify.sh` stays the single command. No remote, so no CI (recorded below). |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; before/after | **PASS**. No per-frame work without a tap beyond one comparison (R9). Before/after is quickstart check 12. |
| IV. Accessibility & Platform UX | VoiceOver, HIG input | **PASS**. The standard tap follows the iOS HIG for touch and leaves system gestures alone (R4). VoiceOver users can tap directly (R5, clarification). Reduced motion: nothing new moves except in response to the player. |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction | **PASS**. One value type, one enum case, one recogniser. No input-source protocol, no second queue, no rename (R1, R3, R4). |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Confirmed. `MoveOrderRequest` lives in the only layer allowed to see both `Camera` and `SimulationState` (R3). |
| II | **PASS** | Confirmed. Contract C1–C10 are headless tests; C11–C19 are structural or quickstart checks. The platform test target's new dependencies are GPU-free (R8). |
| III | **PASS** | Confirmed. Logging formats nothing on frames without a tap or arrival (R6). |
| IV | **PASS** | Confirmed. |
| V | **PASS** | Confirmed. R1 rejects a second queue and a rename; R4 rejects a SwiftUI gesture and custom touch handling. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/008-tap-to-order-ios/
├── plan.md              # This file
├── research.md          # Phase 0: decision record R1–R9
├── data-model.md        # Phase 1: request, outcome, event, logging
├── quickstart.md        # Phase 1: validation guide, checks 1–14, evidence
├── contracts/
│   └── tap-to-order.md  # API and guarantees C1–C19
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/
└── SwiftSkyPlatform/
    ├── MoveOrderRequest.swift       # NEW: request, outcome, pure apply(to:on:) (R3)
    ├── SurfaceEvent.swift           # CHANGED: .moveOrderRequested(MoveOrderRequest); doc widened (R1)
    ├── FrameLoop.swift              # CHANGED: apply the request in queue order; arrival logging (R2, R6)
    ├── MetalSurfaceView.swift       # CHANGED: iOS tap recogniser; .allowsDirectInteraction (R4, R5)
    └── Instrumentation.swift        # CHANGED: recordOrder, recordArrival; Release no-ops (R6)

Tests/
└── SwiftSkyPlatformTests/
    └── MoveOrderRequestTests.swift  # NEW: C1–C10

Package.swift                        # CHANGED: SwiftSkyPlatformTests gains SwiftSkyRendering, SwiftSkySimulation
CLAUDE.md                            # CHANGED: mention spec 008, MoveOrderRequest and the tap
.tickets/10.yaml                     # CHANGED: status done at the end
```

**Structure Decision**: Everything new is in the platform layer, one file per concept, as for
`FrameTimeWindow.swift`. No `Input/` subfolder for one file.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command. |
| **Platform tests depend on the rendering and logic layers** | The tests must name `RenderSurface`, `Vector2` and `SimulationState` under the explicit import check | Re-exporting them from `SwiftSkyPlatform` would widen the platform layer's public surface for tests' sake (R8). |
