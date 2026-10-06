# Implementation Plan: Frame Budget That Does Not Lock Onto Stray Gaps

**Branch**: `016-frame-budget-learner` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/016-frame-budget-learner/spec.md`

## Summary

The frame budget is learned by a new pure value, `DisplayIntervalLearner`, in the platform layer,
replacing `FrameLoop.learnDisplayInterval` and `forgetDisplayInterval`. It confirms a shorter interval
only on the very next plausible gap, and never goes below a floor: the current display's fastest refresh
interval, which the surface view reports through the existing event queue as a new
`SurfaceEvent.displayRateChanged(maximumFramesPerSecond:)`. `FrameLoop` feeds it one gap per frame and
calls `Instrumentation.updateBudget` whenever it reports a new budget. Headless tests cover the seven
series of FR-008.

**Technical approach** (decision record in [research.md](./research.md)):
- **Consecutive confirmation** (R1): a candidate lives for exactly one plausible gap.
- **Floor, not settling period** (R2): `1 / maximumFramesPerSecond` of the screen the view is on, with
  the 5% tolerance; gaps below it are not plausible; an adopted interval is clamped to it.
- **Transport** (R3): a new `SurfaceEvent` case posted by `MetalSurfaceView` before a geometry event
  whenever the screen's maximum rate differs from the last one posted; no change to `RenderSurface`.
- **Relearn on a slower display** (R4): a floor above the learned budget forgets it (FR-004).
- **Shape** (R5): a value type of a few `Double`s, `mutating` methods that return the new budget or
  `nil`, outside `#if SWIFTSKY_INSTRUMENTATION` like today's learner (Release behaves as today).

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: UIKit / AppKit (`UIScreen.maximumFramesPerSecond`,
`NSScreen.maximumFramesPerSecond`), QuartzCore (`CAMetalDisplayLink`, unchanged). None new.

**Storage**: N/A.

**Testing**: Swift Testing, headless, new `Tests/SwiftSkyPlatformTests/DisplayIntervalLearnerTests.swift`,
run by `Scripts/verify.sh`. No test creates a Metal device.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.

**Performance Goals**: zero heap allocations per frame (011 check 25); the learner is O(1) per frame, a
handful of comparisons.

**Constraints**: the learner must not touch the screen, the display link or Metal (FR-006); the screen
is read on the main thread only, in the view.

**Scale/Scope**: 1 new source file (`DisplayIntervalLearner.swift`), 3 changed (`FrameLoop.swift`,
`SurfaceEvent.swift`, `MetalSurfaceView.swift`), 1 new test file. No change to `Package.swift` or
`verify.sh`. `CLAUDE.md` gains a line.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; unidirectional flow | **PASS**. The view (main thread) posts a value event; the loop applies it at a frame boundary; the learner is a pure value inside the platform layer. |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command | **PASS**. All seven FR-008 series, plus floor and forget rules, in a headless suite run by `verify.sh`. |
| III. Performance & Resource Efficiency | No hot-path allocation | **PASS**. Stack value, no collections; check 25 unchanged (FR-007). |
| IV. Accessibility & Platform UX | Player-facing UI rules | **PASS (N/A)**. Instrumentation only. |
| V. Simplicity & YAGNI | Simplest solution | **PASS**. A floor instead of a settling period with timers; no rising budget within one display. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | The rate travels in the existing ordered event queue (R3), not a side channel. |
| II | **PASS** | Contract C1's rules each map to a test (C3). |
| III | **PASS** | The new event's payload is an `Int`; the queue already exists. |
| IV | **PASS** | Unchanged. |
| V | **PASS** | One struct, one event case, no new launch argument or log field. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/016-frame-budget-learner/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R6
├── data-model.md        # Phase 1 output: the learner's state and transitions
├── quickstart.md        # Phase 1 output: validation guide
├── contracts/
│   └── display-interval-learner.md   # C1–C3: learner rules, event, test series
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/SwiftSkyPlatform/
├── DisplayIntervalLearner.swift   # NEW: the pure learner
├── FrameLoop.swift                # CHANGED: uses the learner; applies .displayRateChanged
├── SurfaceEvent.swift             # CHANGED: + displayRateChanged(maximumFramesPerSecond:)
└── MetalSurfaceView.swift         # CHANGED: posts the screen's maximum rate on change

Tests/SwiftSkyPlatformTests/
└── DisplayIntervalLearnerTests.swift   # NEW: FR-008 series and floor/forget rules

CLAUDE.md                          # CHANGED: mention spec 016
```

**Structure Decision**: the learner sits beside `FrameTimeWindow.swift` in the platform layer, as the
ticket asks; the screen reading stays in the view that already reads the backing scale.

## Complexity Tracking

No violations.
