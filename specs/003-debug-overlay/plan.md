# Implementation Plan: Live Debug Overlay

**Branch**: `003-debug-overlay` | **Date**: 2026-09-30 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-debug-overlay/spec.md`

## Summary

This puts 001's frame statistics on screen. In every Debug and Profiling build, six lines drawn with
002's text path sit 8 points in from the safe area's top-left corner: mean and worst frame time over
the last second, the budget, dropped and skipped counts, and the tick count. They refresh four times a
second. `--no-debug-overlay` hides them, so the black-surface checks still run, and 002's
`--debug-text` options replace them. Release contains none of it. The ticket's ship and order lines
wait for SKY-24 and SKY-25.

**Technical approach**:
- **Measurement stays in the platform layer**: `Instrumentation` gains a `FrameTimeWindow` (four
  0.25 s buckets in an `InlineArray`) and an `OverlayRefreshSchedule` (a fixed 4 Hz grid on the loop's
  timestamp).
- **One value crosses into rendering**: on each due refresh, the frame loop hands a
  `DebugOverlayStatistics` snapshot to `Renderer.updateDebugOverlay`. The budget, dropped, skipped and
  tick values are the same fields the log line prints.
- **Presentation in rendering**: `DebugOverlay`, in `Debug/` beside 002's `DebugTextPattern`, rewrites
  six labelled lines into the existing `TextBuffer` every frame. A new allocation-free
  `writeHundredths` writes the milliseconds.
- **Build gating**: everything except `writeHundredths` is inside `#if SWIFTSKY_INSTRUMENTATION`, and
  001's Release symbol check is extended to the new names.
- **Tests**: a new headless `SwiftSkyPlatformTests` target covers the window and the schedule, and
  `SwiftSkyRenderingTests` gains the decimal and overlay-composition tests.

See [research.md](./research.md) for the decision record.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: none new. It uses 002's text path, 001's instrumentation and frame loop,
and the standard library's `InlineArray`. There are zero third-party dependencies.

**Storage**: N/A.

**Testing**: Swift Testing, headless. A new `SwiftSkyPlatformTests` target depends on
`SwiftSkyPlatform` only and exercises pure structs, with no view, layer or `FrameLoop`. The existing
`SwiftSkyRenderingTests` is extended. Everything runs through `Scripts/verify.sh`.

**Target Platform**: iOS 26+ (landscape-only iPhone and iPad) and macOS 26+. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: 001's frame budget holds with the overlay showing. Zero heap allocations on the
per-frame path, including refresh frames.

**Constraints**:
- **Memory**: under 200 bytes of new state. No new GPU resources.
- **Log**: the instrumentation's log output is byte-for-byte unchanged in format and cadence
  (FR-013).
- **Release**: nothing new is drawn, and the new names are absent from the stripped binary (FR-009).
- **Baseline**: evidence is recorded as same-device deltas, as in 002, because SKY-31 and SKY-32 are
  still pending.

**Scale/Scope**: 3 new source files (2 platform, 1 rendering), 5 changed source files, 1 new test
target with 2 test files, 2 new rendering test files, and a `Package.swift` entry.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow; platform code thin | **PASS**. The logic layer is untouched. Measurement stays with the platform layer's instrumentation, and a plain value crosses into rendering, consumer-defined as `RenderSurface` is (FR-015). The tick count reaches the screen through the instrumentation's own counter, not a new path from simulation state. |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command; CI once a remote exists | **PASS**. The window, the schedule, the decimal formatting and the composition are logic, and all get headless tests (FR-016). `verify.sh` remains the single command. There is no remote yet, so the CI absence is recorded below. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; memory budget; before/after | **PASS**. The design is allocation-free, with fixed-size stores (R2, R5). The memory budget is stated above. Before/after evidence comes from quickstart checks 13 and 14. |
| IV. Accessibility & Platform UX | Dynamic Type, VoiceOver, contrast; reduced motion; HIG | **PASS**. It is developer-only content, hidden from assistive technology (FR-010), as in 002, and white on black. A value changing four times a second is not motion. The safe area is respected (FR-003). |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction | **PASS**. It uses one text path and one colour, and no backdrop, configuration or run-time toggle. Ship and order lines are not pre-built. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Sharpened. R1 rejected putting the window in rendering just to reuse the existing tests: a measurement type in the wrong layer. It takes a test target instead. |
| II | **PASS** | Strengthened. The platform layer gets its first test target. R2 found that the obvious window-restart rule (copied from 002's FPS) would have erased the frames the worst line exists for. The spec was corrected, and a test pins the corrected behaviour (quickstart check 4). |
| III | **PASS** | Unchanged. Per refresh, the cost is O(4). |
| IV | **PASS** | Unchanged. |
| V | **PASS** | The one addition beyond the naive design is the refresh *grid* in place of "0.25 s since the last refresh" (R3). It is needed to meet SC-002, and it is five lines, which is not complexity worth tracking. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/003-debug-overlay/
├── plan.md              # This file
├── research.md          # Phase 0 output: decision record R1–R11
├── data-model.md        # Phase 1 output: entity shapes and invariants
├── quickstart.md        # Phase 1 output: validation guide, checks 1–18
├── contracts/
│   └── debug-overlay.md # New and changed seams, text layout, launch arguments
├── checklists/
│   └── requirements.md  # Spec quality checklist (from /speckit-specify)
└── tasks.md             # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Package.swift                              # + testTarget SwiftSkyPlatformTests → [SwiftSkyPlatform]

Sources/
├── SwiftSkySimulation/                    # unchanged
│
├── SwiftSkyRendering/
│   ├── Renderer.swift                     # CHANGED: debugOverlay, updateDebugOverlay, prepareText picks pattern or overlay
│   ├── Text/
│   │   └── TextBuffer.swift               # CHANGED: + writeHundredths, + writePadded (all builds)
│   └── Debug/
│       └── DebugOverlay.swift             # NEW: DebugOverlayStatistics + DebugOverlay (instrumentation only)
│
└── SwiftSkyPlatform/
    ├── FrameTimeWindow.swift              # NEW: FrameTimeBucket + FrameTimeWindow (instrumentation only)
    ├── OverlayRefreshSchedule.swift       # NEW: the 4 Hz grid (instrumentation only)
    ├── Instrumentation.swift              # CHANGED: window, schedule, overlayStatistics(at:), restartOverlayWindow
    ├── FrameLoop.swift                    # CHANGED: step 3a, restart on becoming visible
    └── GameSurfaceView.swift              # CHANGED: DebugTextMode gains .overlay (default) and --no-debug-overlay

Tests/
├── SwiftSkySimulationTests/               # unchanged
├── SwiftSkyRenderingTests/
│   ├── DecimalWritingTests.swift          # NEW: contract table, rounding, width, NaN, clamping
│   └── DebugOverlayTests.swift            # NEW: six lines, labels, --, ≤ 33 chars, UInt64.max, no draw before first snapshot
└── SwiftSkyPlatformTests/                 # NEW target
    ├── FrameTimeWindowTests.swift         # --, last four buckets, slow frame survives a gap, restarts
    └── OverlayRefreshTests.swift          # grid rate at 60/120 Hz, no burst after a gap, snapshot fields = counters

CLAUDE.md                                  # CHANGED: mention spec 003, the platform test target, --no-debug-overlay
```

**Structure Decision**: the platform files sit beside `Instrumentation.swift`, the code they extend,
because the platform target has no subfolders. `DebugOverlay` goes in rendering's `Debug/` folder, the
same `SWIFTSKY_INSTRUMENTATION` boundary as 002's test string. Keeping the statistics value and its
only consumer in one file, as `DebugTextPattern` does, keeps the Debug-only surface to one file per
layer, plus the two small measurement structs.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command, and it now runs the new platform test target too. |
| **Supersedes 001 FR-012b, FR-021e and FR-002, and 002 SC-006, in Debug and Profiling builds only** | The ticket's purpose is to show instrumentation, including the tick count, on the surface | Recorded in spec.md's relationship section. Release keeps every rule exactly. Not a constitution violation: the constitution does not forbid debug-only drawing. It is listed here so that a reviewer comparing against 001 finds it in one place. |
