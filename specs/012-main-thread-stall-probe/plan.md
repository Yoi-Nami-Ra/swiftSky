# Implementation Plan: Measure Main-Thread Stalls and Verify Continuous Resize Under Thread Sanitizer

**Branch**: `012-main-thread-stall-probe` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/012-main-thread-stall-probe/spec.md`

## Summary

Builds with the instrumentation measure how long the main thread stays busy between two waits of its run
loop, in every mode including live resize, and add the worst stretch and the number over the frame
interval to the frame summary as `mainworst=…ms mainover=…`. A drag is bracketed in the log by
`live resize began` / `live resize ended`. With that, a person drags a window corner for 10 s in a Thread
Sanitizer build (races) and in an optimised instrumented build (stalls), and 001's check 29 is decided.

**Technical approach** (decision record in [research.md](./research.md)):
- **Run-loop observers** (R1): after-waiting opens a stretch, before-waiting closes it; two clock reads per
  pass.
- **Common modes** (R2): covers live resize, menus and modal panels; a missed mode fails loud.
- **One packed atomic** (R4): worst (µs) and count in one `Atomic<UInt64>`; the loop takes both with one
  `exchange`. No lock, no allocation, no race for the sanitizer to find.
- **Restart with the budget** (R6), **markers** (R7), **`--debug-main-stall`** (R8), **format** (R9).
- **Tests** (R10): the tracker and the packed figures are plain types, tested headlessly.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency.

**Primary Dependencies**: none new. Core Foundation's `CFRunLoopObserver`, the Synchronization module's
`Atomic` (already imported by `FrameLoop.swift` for `Mutex`), `os.Logger`.

**Storage**: N/A.

**Testing**: Swift Testing, headless, in `SwiftSkyPlatformTests`, run by `Scripts/verify.sh`.

**Target Platform**: macOS 26+ (required); iOS 26+ runs the probe too (R11). Unchanged floors.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets. Unchanged.

**Performance Goals**: 001's frame budget, unchanged. Main thread: two clock reads and one CAS per
run-loop pass. Loop thread: one `exchange` per summary. SC-005 checks the result.

**Constraints**:
- No allocation, lock or blocking on either thread (FR-007); zero app-side allocations per frame still
  (SC-006).
- Instrumented builds only; Release contains none of it (FR-008).
- No change to the logic or rendering layers (FR-009).
- **Memory**: two atomics, one optional integer, two observers: well under 1 KB, allocated once.

**Scale/Scope**: 2 new platform files (`MainThreadStallFigures.swift` with the tracker and figures,
`MainThreadStallProbe.swift`); 4 changed (`Instrumentation.swift`, `FrameLoop.swift`,
`MetalSurfaceView.swift`, `GameSurfaceView.swift`); 1 new test file. Docs: 001's quickstart check 29,
`CLAUDE.md`, `.tickets/5.yaml`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. Platform layer only (FR-009). |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command; CI once a remote exists | **PASS**. The tracker and the figures are tested headlessly (FR-010). No remote yet: recorded below. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; before/after | **PASS**. Measures a Principle III/IV gate; allocates nothing; before/after in SC-005, allocations re-checked in SC-006. |
| IV. Accessibility & Platform UX | Responsiveness, HIG | **PASS**. Nothing visible changes; this measures responsiveness. |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction | **PASS**. Two observers and two atomics; no new target, no overlay change. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Unchanged. |
| II | **PASS** | Unchanged; the observers' wiring is checked by quickstart checks 2–3. |
| III | **PASS** | Unchanged. The loop thread gains no per-frame work. |
| IV | **PASS** | Unchanged. |
| V | **PASS** | One launch argument (`--debug-main-stall`), needed by SC-002 and following the existing `--debug-*` pattern. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/012-main-thread-stall-probe/
├── plan.md                          # This file
├── research.md                      # Phase 0 output: decision record R1–R11
├── data-model.md                    # Phase 1 output: tracker, figures, probe
├── quickstart.md                    # Phase 1 output: the drag procedure, checks 1–9
├── contracts/
│   └── main-thread-stall-probe.md   # Summary format, measurement, cost, markers, PASS rules
├── checklists/
│   └── requirements.md              # Spec quality checklist (from /speckit-specify)
└── tasks.md                         # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Sources/
└── SwiftSkyPlatform/
    ├── MainThreadStallFigures.swift   # NEW: BusyStretchTracker, MainThreadStallFigures (every build)
    ├── MainThreadStallProbe.swift     # NEW: atomics + run-loop observers (instrumented builds)
    ├── Instrumentation.swift          # CHANGED: holds the probe; summary fields; restart on budget
    ├── FrameLoop.swift                # CHANGED: creates the probe, installs in start(), removes in stopAndDrain()
    ├── MetalSurfaceView.swift         # CHANGED: live-resize markers (macOS, instrumented)
    └── GameSurfaceView.swift          # CHANGED: --debug-main-stall

Tests/
└── SwiftSkyPlatformTests/
    └── MainThreadStallTests.swift     # NEW: tracker and figures

specs/001-metal-app-shell/quickstart.md   # CHANGED: check 29 result, open-checks row
CLAUDE.md                                 # CHANGED: spec 012, the probe, the markers, the argument
```

**Structure Decision**: everything in the platform layer, beside `Instrumentation.swift` and
`FrameAllocationCounts.swift`, following 011's split between a plain tested value type and the
instrumented-only machinery around it.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote (SKY-9) | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command and runs the new tests. |
| **A manual step in verification** | The drag needs a person: Accessibility permission is not granted | UI automation: blocked; a synthetic `setFrame` sweep: not a live resize (no tracking mode), so it would not exercise the path the check is about |
