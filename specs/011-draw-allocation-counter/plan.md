# Implementation Plan: Count Draw-Path Allocations and Verify Zero on iOS

**Branch**: `011-draw-allocation-counter` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-draw-allocation-counter/spec.md`

## Summary

Debug builds count every heap allocation the frame loop's thread makes while it handles a frame, split
into the app's own and the graphics framework's, and add four fields to the frame summary that is already
written every 120 frames. The count comes from a small C target that installs a callback in libmalloc's
`malloc_logger` hook for the life of the frame loop. With it, a 60-second idle run on the iPhone 17 Pro
simulator decides 001's check 25, and the procedure is written down for SKY-4 and the six later checks
that cite it.

**Technical approach** (decision record in [research.md](./research.md)):
- **Debug decides** (R1): the Profiling configuration builds the package with Release settings, so it
  carries no instrumentation; found while planning, reported for its own ticket.
- **`malloc_logger`** (R2): sees every allocation, in every zone, on every destination; spike: 16 of 16
  counted, 0 of 100,000 from another thread.
- **One thread, no TLS** (R3): `pthread_equal(pthread_self(), recorded)` plus an atomic flag.
- **Attribution by stack walk** (R4): a frame-pointer walk up to the frame callback; any return address in
  Metal, QuartzCore, IOGPU, IOSurface, MTLSimDriver or an AGX driver image → framework, else app. Fails
  safe. Spike: 11 / 5 exactly. No rendering-layer change.
- **A C target** (R5): `SwiftSkyAllocationCounter`, compiled empty without `SWIFTSKY_INSTRUMENTATION`.
- **Counted stretch** (R6): from the delegate's entry to the end of the draw; summary outside it.
- **Chained, self-tested** (R7, R8): an existing logger keeps working; a one-allocation self-test at start
  logs `allocation counter ready`, so a dead counter cannot report a false zero.
- **Format** (R9): `allocs= allocframes= eventallocs= gfxallocs=` after `ticks=`.
- **Tests** (R10): headless, serialized, on a dedicated thread, through the same C functions.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency; C (C17) for the new target.

**Primary Dependencies**: none new. libmalloc's exported `malloc_logger` and dyld's image APIs
(`<mach-o/dyld.h>`) from the system SDK.

**Storage**: N/A.

**Testing**: Swift Testing, headless, in `SwiftSkyPlatformTests`, run by `Scripts/verify.sh`.

**Target Platform**: iOS 26+ and macOS 26+, device and simulator. Unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: 001's frame budget, unchanged. On a frame with no allocation the counter adds two
C calls; per allocation on another thread, one flag load. SC-005's before/after checks the result.

**Constraints**:
- The hook must not allocate, lock, or trigger lazy initialisation (R3, R5).
- Compiled into Debug builds only; Release contains none of it (FR-009).
- No change to the logic or rendering layers (FR-010).
- **Memory**: about 600 bytes of static state (32 address ranges, counters); no heap.

**Scale/Scope**: 1 new C target (1 source file, 1 header, 1 module map by convention); 2 changed platform
files (`FrameLoop.swift`, `Instrumentation.swift`) and 1 new one (`FrameAllocationCounts.swift`);
`Package.swift`; 1 new test file. Docs: 001's quickstart check 25 and pointers, `CLAUDE.md`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; logic free of Metal and UI; unidirectional flow | **PASS**. Instrumentation stays in the platform layer (FR-010); logic and rendering untouched. |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command; CI once a remote exists | **PASS**. The counter's counting, filtering and attribution, and the buckets, are tested headlessly (FR-011). No remote yet: recorded below. |
| III. Performance & Resource Efficiency | Frame budget; no hot-path allocation; before/after | **PASS**. This feature is the measurement Principle III asks for; it allocates nothing itself and reports a before/after (SC-005). |
| IV. Accessibility & Platform UX | Dynamic Type, VoiceOver; reduced motion; HIG | **PASS (N/A)**. Nothing visible changes. |
| V. Simplicity & YAGNI | Simplest solution; no speculative abstraction | **PASS**, with one structural addition recorded below (a C target). |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | The C target has no dependencies and only the platform layer imports it; the package diagram gains one leaf. Attribution by stack walk (R4) is what keeps the renderer free of instrumentation. |
| II | **PASS** | Strengthened: the self-test (R8) checks the counter on every launch, not only in tests. |
| III | **PASS** | Unchanged. The walk runs only for allocations on the counted thread, which the frame path should not make. |
| IV | **PASS (N/A)** | Unchanged. |
| V | **PASS** | No launch argument (the self-test replaces one), no overlay change, no configuration knob. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/011-draw-allocation-counter/
├── plan.md                        # This file
├── research.md                    # Phase 0 output: decision record R1–R11
├── data-model.md                  # Phase 1 output: counter state and FrameAllocationCounts
├── quickstart.md                  # Phase 1 output: the method, checks 1–9
├── contracts/
│   └── allocation-counter.md      # C API, frame-loop order, summary format, PASS rule
├── checklists/
│   └── requirements.md            # Spec quality checklist (from /speckit-specify)
└── tasks.md                       # Phase 2 output (/speckit-tasks, NOT created here)
```

### Source Code (repository root)

```text
Package.swift                                   # CHANGED: + SwiftSkyAllocationCounter (C), platform and
                                                #          platform-tests depend on it; diagram updated
Sources/
├── SwiftSkyAllocationCounter/                  # NEW (C)
│   ├── AllocationCounter.c                     #   hook, thread filter, stack walk, install, probe
│   └── include/AllocationCounter.h             #   the API of contracts/allocation-counter.md
├── SwiftSkySimulation/                         # unchanged
├── SwiftSkyRendering/                          # unchanged
└── SwiftSkyPlatform/
    ├── FrameAllocationCounts.swift             # NEW: the four buckets, record and reset
    ├── Instrumentation.swift                   # CHANGED: buckets, self-test result, summary fields
    └── FrameLoop.swift                         # CHANGED: install/self-test/uninstall; counted stretch

Tests/
└── SwiftSkyPlatformTests/
    └── AllocationCounterTests.swift            # NEW: the counter through its C API; the buckets

specs/001-metal-app-shell/quickstart.md         # CHANGED: check 25's result; pointer to the method
CLAUDE.md                                       # CHANGED: spec 011, the counter, the Profiling finding
```

**Structure Decision**: a leaf C target beside the three layers, because SwiftPM targets are
single-language and the hook must be C (R5). Its only client is the platform layer, where the rest of the
instrumentation lives.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **A fourth source target, in C** | A malloc hook must not allocate or lazily initialise, and Swift cannot declare `malloc_logger` (R5) | Swift with `dlsym`: lazy globals and retain/release inside the allocator's callback can re-enter it |
| **A process-wide hook in Debug builds** | Only the allocator sees every allocation, including those inside system code (R2) | Instruments: does not work from a session; `malloc_zone_statistics`: process-wide and net of frees |
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command and runs the new tests. |
