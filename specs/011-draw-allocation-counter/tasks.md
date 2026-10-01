---

description: "Task list for 011-draw-allocation-counter"
---

# Tasks: Count Draw-Path Allocations and Verify Zero on iOS

**Input**: Design documents from `/specs/011-draw-allocation-counter/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/allocation-counter.md, quickstart.md

**Tests**: Required. FR-011 calls for headless tests of the counter (Principle II), and SC-001 is written
as test criteria. The running-app checks (SC-002–SC-005, SC-007) are verified through quickstart.md.

**Organization**: Tasks are grouped by user story, so each story can be implemented and validated on
its own.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: can run in parallel (different files, no dependency on an incomplete task)
- **[Story]**: which user story the task belongs to (US1–US3)
- Paths are relative to the repository root. `R<n>` refers to research.md and `check <n>` to
  quickstart.md; "the contract" is contracts/allocation-counter.md.

## Path Conventions

- New C target: `Sources/SwiftSkyAllocationCounter/` (`AllocationCounter.c`, `include/AllocationCounter.h`).
- Platform layer: `Sources/SwiftSkyPlatform/`; tests in `Tests/SwiftSkyPlatformTests/`.
- `SwiftSkySimulation` and `SwiftSkyRendering` MUST NOT change (FR-010).
- Every Swift use of the counter is inside `#if SWIFTSKY_INSTRUMENTATION`; the C file's body is inside the
  same condition (R5).
- Run the tests with `swift test --build-system swiftbuild --explicit-target-dependency-import-check=error`
  (as `Scripts/verify.sh` does).

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The new target and its API, so the platform layer and tests can import it.

- [X] T001 Change `Package.swift`: add `.target(name: "SwiftSkyAllocationCounter", cSettings: [.define("SWIFTSKY_INSTRUMENTATION", .when(configuration: .debug))])` with a comment (Debug-only malloc hook for 001 FR-021d, why C — R5, why the define mirrors `layerSettings`, and that Xcode's Profiling maps to Release so it carries none of it — R1); add `"SwiftSkyAllocationCounter"` to the dependencies of `SwiftSkyPlatform` and of `SwiftSkyPlatformTests` (with the reason in the test target's comment: the counter's tests call its C API, R10); extend the header diagram with the new leaf, depended on by the platform layer only
- [X] T002 Create `Sources/SwiftSkyAllocationCounter/include/AllocationCounter.h` and a stub `Sources/SwiftSkyAllocationCounter/AllocationCounter.c` (only `#include "AllocationCounter.h"`, so SwiftPM can build the target; T003 fills it). The header exactly per the contract: `SkyFrameAllocations`, `sky_alloc_counter_install`, `sky_alloc_counter_uninstall`, `sky_alloc_frame_begin`, `sky_alloc_frame_end`, `sky_alloc_probe`, `sky_alloc_app_allocation`, each with the contract's doc comment, `<stdbool.h>`/`<stddef.h>`/`<stdint.h>` includes, and a file comment: what the counter is (011, 001 FR-021d), that it is Debug-only, that none of it may be called from inside the hook. The declarations are unconditional (the header must parse in every configuration); only the definitions are conditional. Depends on T001

**Checkpoint**: `swift build` passes with no warnings.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The counter itself and the buckets, which every story uses.

- [X] T003 Fill `Sources/SwiftSkyAllocationCounter/AllocationCounter.c`, its whole body inside `#if defined(SWIFTSKY_INSTRUMENTATION)`, implementing the contract and data-model.md's C side: a private declaration of libmalloc's `malloc_logger` (`typedef void (sky_malloc_logger_t)(uint32_t, uintptr_t, uintptr_t, uintptr_t, uintptr_t, uint32_t); extern sky_malloc_logger_t *malloc_logger;`); static state (`installed`, `previousLogger`, up to 32 graphics `__TEXT` ranges and a count, atomic `countedThread`, atomic `counting`, `stackLimit`, `appCount`, `graphicsCount`); the hook — call `previousLogger` first if set, then return unless `type & 0x2`, `counting` and `pthread_equal(pthread_self(), countedThread)`; walk frame records from `__builtin_frame_address(0)` (`fp[0]` next, `fp[1]` return address) while `fp` is non-null, 8-byte aligned, below `stackLimit`, strictly increasing and fewer than 64 steps; graphics if any return address is in a captured range, else app (fail safe, R4); on app, increment `appCount` and call `sky_alloc_app_allocation()`; `install` — return false if installed; capture `__TEXT` of every dyld image whose path contains a given substring (NULL → the built-in list of R4: `/Metal.framework/`, `/MetalTools.framework/`, `/QuartzCore.framework/`, `/IOGPU.framework/`, `/IOSurface.framework/`, `/MTLSimDriver.framework/`, `AGX`), walking `LC_SEGMENT_64` load commands with the image slide; keep the current `malloc_logger` as `previousLogger`; publish ours with `__atomic_store_n(..., __ATOMIC_RELEASE)`; `uninstall` — restore `previousLogger` only if ours is installed; `frame_begin` (`__attribute__((noinline))`) — zero the counts, store `pthread_self()` and `stackLimit = *(uintptr_t *)__builtin_frame_address(0)` (the caller's frame), then set `counting`; `frame_end` — clear `counting`, return the counts; `sky_alloc_probe` (`noinline`) — `malloc(16)` into a `volatile` pointer, then `free`; `sky_alloc_app_allocation` (`noinline`, empty but with an `__asm__ volatile("")` so it is not removed). Comments: why `malloc_logger` (R2), why no TLS (R3), the walk and why it stops at the callback and fails safe (R4), why chaining (R7). Nothing in the file allocates, locks or uses thread-local storage. Depends on T002
- [X] T004 [P] Create `Sources/SwiftSkyPlatform/FrameAllocationCounts.swift`: `struct FrameAllocationCounts: Equatable` with `appAllocations`, `eventAppAllocations`, `allocatingFrames`, `graphicsAllocations` (`UInt64`, all `private(set)`, zero by default), `mutating func record(app: UInt64, graphics: UInt64, appliedEvent: Bool)` and `mutating func reset()` exactly per data-model.md (an allocating frame is one without an event with `app > 0`). Pure, platform-neutral, compiled in every configuration (no `#if`), so its tests run in Debug like the other platform structs. Doc comment: the four summary fields (R9), why event frames are separate (008 SC-006, spec FR-004)

**Checkpoint**: `swift build` passes with no warnings; every existing test still passes.

---

## Phase 3: User Story 1 - Read the frame path's allocations from the log (Priority: P1) 🎯 MVP

**Goal**: Debug summaries carry `allocs= allocframes= eventallocs= gfxallocs=`, with a self-tested
counter behind them.

**Independent Test**: `swift test --filter AllocationCounter` passes (SC-001); a Debug launch on macOS
and on the simulator logs `allocation counter ready` and summaries with the four fields (checks 3, 4).

### Tests for User Story 1

- [ ] T005 [P] [US1] Create `Tests/SwiftSkyPlatformTests/AllocationCounterTests.swift` (`import Testing`, `import Foundation`, `import SwiftSkyAllocationCounter`, `@testable import SwiftSkyPlatform`), whole file inside `#if SWIFTSKY_INSTRUMENTATION` except the buckets suite. A `@Suite(.serialized)` with a helper that runs a closure on a fresh `Thread` and waits for it (semaphore), and installs/uninstalls around each test. Tests per R10: for N in {0, 1, 10, 1,000}, N `sky_alloc_probe()` calls in a stretch → `app == N`, `graphics == 0` (parameterised); N Swift class instances (kept alive in a preallocated `ContiguousArray` with reserved capacity, after one warm-up instance outside the stretch) → `app == N`; a second thread making 100,000 probe calls during the stretch → the stretch still reports exactly its own count; with `install(["/libsystem_c.dylib"])`, 5 `strdup`+`free` → `graphics == 5`, and 10 probes → `app == 10`; probes on the counted thread with no stretch open, then an empty stretch → `app == 0`; installing twice returns `false` the second time; after uninstall, install succeeds again; the `malloc_logger` value read through `dlsym(RTLD_DEFAULT, "malloc_logger")` is unchanged by an install/uninstall pair and differs while installed (contract C4). Plus a non-conditional `@Suite` for `FrameAllocationCounts`: event versus non-event frames go to the right field, `allocatingFrames` counts non-event frames with `app > 0` only, `graphics` sums across both, `reset()` zeroes all four. Depends on T003, T004

### Implementation for User Story 1

- [ ] T006 [US1] Change `Sources/SwiftSkyPlatform/Instrumentation.swift` (instrumented branch): add `private var allocations = FrameAllocationCounts()` and `private(set) var allocationCounterReady = false` with a setter method `markAllocationCounter(ready:)`; add `mutating func recordFrameAllocations(app: UInt64, graphics: UInt64, appliedEvent: Bool)`; `updateBudget(seconds:)` also resets `allocations` (R9, FR-007); `summary()` appends ` allocs=… allocframes=… eventallocs=… gfxallocs=…` after `ticks=` when ready, or ` allocs=unavailable` when not, and must then reset `allocations` — `summary()` becomes `mutating` (update the one existing non-loop call site in `runLoopMain`); add `func logAllocationCounter(ready: Bool)` writing `allocation counter ready` / `allocation counter unavailable` at notice level. Keep the "only formatting site" doc note accurate (the summary and the one start-up line). Release branch: matching `@inline(__always)` no-ops for every new member. Update the type's doc comment: it now also reports draw-path allocation counts (001 FR-021d, 011). Depends on T004
- [ ] T007 [US1] Change `Sources/SwiftSkyPlatform/FrameLoop.swift`: `import SwiftSkyAllocationCounter` under `#if SWIFTSKY_INSTRUMENTATION`; `applyPendingEvents()` returns `Bool` (whether it applied at least one event; `@discardableResult` not needed if every call uses it); move 001's steps 1–5 out of `metalDisplayLink(_:needsUpdate:)` into `private func drawFrame(_ update:) -> (outcome: FrameOutcome, appliedEvent: Bool)` with a private `enum FrameOutcome { case notRenderable, skipped, presented }`, keeping every step comment; the delegate becomes: `sky_alloc_frame_begin()` (instrumented only) → `drawFrame` → `sky_alloc_frame_end()` → `instrumentation.recordFrameAllocations(...)` → step 6: `notRenderable` → `recordSkipped()` and return without advancing the summary cadence (today's early return), `skipped` → `recordSkipped()`, `presented` → `recordPresented(...)` with the frame time `drawFrame` measured — then the summary cadence. Today's accounting is preserved exactly. In `runLoopMain()`, before adding the display link: install (`nil` list), run the self-test (begin, `sky_alloc_probe()`, end; ready iff `app == 1 && graphics == 0`), `markAllocationCounter(ready:)`, log it once; after invalidating the link and writing the final summary: uninstall. Update the file and method doc comments: the counted stretch and why the summary is outside it (R6), the self-test (R8). Frame order otherwise unchanged. Depends on T003, T006
- [ ] T008 [US1] Run check 3 (macOS Debug app, 10 s) and check 4 (iOS Debug app on the booted iPhone 17 Pro simulator, 10 s) per the quickstart method steps 1–4; confirm `allocation counter ready` and the four fields after `ticks=`, existing fields unchanged; paste one line of each into quickstart.md's Results. If the self-test reports unavailable, stop and investigate (R2's fallback) before going on. Depends on T007
- [ ] T009 [US1] Run check 5: Release builds of both apps (`xcodebuild build -configuration Release`, derived data in the scratchpad), then `nm` and `strings -a` on each executable for `sky_alloc`, `allocs=`, `gfxallocs=`, `allocation counter`, plus 001 check 27's probes; record the counts in quickstart.md's Results. Depends on T007

**Checkpoint**: US1 complete — `./Scripts/verify.sh` passes; Debug summaries carry the counts.

---

## Phase 4: User Story 2 - Verify zero draw-path allocations on iOS (Priority: P2)

**Goal**: 001's check 25 recorded as PASS on iOS.

**Independent Test**: check 6 — the method, 60 s idle on the simulator, Debug.

- [ ] T010 [US2] Run check 6: iOS Debug app on the iPhone 17 Pro simulator, no launch arguments, 60 s idle, method steps 1–5. Record in quickstart.md's Results: date, destination, build, every summary line (or the first, last and any non-zero ones), the PASS/FAIL decision by the contract's rule, `eventallocs=` as reported, and `gfxallocs ÷ frames` lowest and highest (SC-004). Depends on T008
- [ ] T011 [US2] If T010 fails: follow method step 6 (breakpoint on `sky_alloc_app_allocation`, read the backtrace), remove the allocation at its source with the smallest change that keeps the frame order, and add a note to the fixing file's comment naming 011 SC-003. Re-run T010 until it passes. Record what was found and fixed. If T010 passed, mark this task done with "nothing to fix". Depends on T010
- [ ] T012 [US2] Run check 7 (SC-005): Debug builds of `main` (a `git worktree` of `main` in the scratchpad) and of this branch on the same simulator, 30 s idle each, no arguments; record both summaries' mean and worst frame time and `dropped=` side by side in quickstart.md's Results and the verdict (after mean within 10% or 0.1 ms of before, whichever larger; `dropped=0` outside launch in both). Depends on T011
- [ ] T013 [US2] Change `specs/001-metal-app-shell/quickstart.md`: in the results notes, replace "**Check 25** … is **not verified** …" with the iOS result (PASS, date, simulator, Debug, run length, the summary figures, the framework's per-frame reference), noting that the macOS run is SKY-4 and that the method is in `specs/011-draw-allocation-counter/quickstart.md` ("The method"); update the check-25 row in the summary table near line 598 likewise ("iOS PASS (011); macOS: SKY-4"). Depends on T012

**Checkpoint**: US2 complete — check 25 is PASS on iOS in 001's quickstart.

---

## Phase 5: User Story 3 - Reuse the method in later checks (Priority: P3)

**Goal**: A reader of any check that cites "the method of SKY-3" finds the procedure.

**Independent Test**: check 9 — follow "The method" for macOS without other guidance.

- [ ] T014 [US3] Review `specs/011-draw-allocation-counter/quickstart.md` "The method" against what T008–T012 actually did (exact build commands, the simulator and Mac log commands, the time window, the PASS rule, what to record) and correct any step that differed; add the exact `xcodebuild` and `simctl` commands used. Depends on T012
- [ ] T015 [P] [US3] Add a one-line pointer "Method: `specs/011-draw-allocation-counter/quickstart.md`, The method (Debug builds; Profiling carries no instrumentation, 011 R1)" beside each check that cites "the method of SKY-3" — 002 #15, 003 #13, 004 #8, 006 #11, 008 #12, 010 #10 — in their quickstarts' results notes, without changing their status (they stay "Not run" until their own runs). Depends on T014
- [ ] T016 [US3] Run check 9: read "The method" as a SKY-4 reader and confirm every step is executable on macOS without Instruments; record the answer in quickstart.md's Results. Depends on T014

**Checkpoint**: US3 complete.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T017 [P] Change `CLAUDE.md`: add spec 011 to the "Built so far" list (the draw-path allocation counter in Debug builds, and check 25 PASS on iOS); add a Key-locations entry for `Sources/SwiftSkyAllocationCounter/` (the `malloc_logger` hook, stack-walk attribution, self-test line, the four summary fields, breakpoint `sky_alloc_app_allocation`) and for `FrameAllocationCounts.swift`; note that the Profiling configuration builds the package with Release settings, so it carries no instrumentation (011 R1)
- [ ] T018 Run check 1 (`./Scripts/verify.sh`) and check 2 (`swift test --filter AllocationCounter` 10 times in a row); record both in quickstart.md's Results. Depends on all earlier tasks
- [ ] T019 Fill quickstart.md's Results table for checks 1–9 (PASS / result per check, date 2026-10-01 or the run date) and set spec.md's **Status** to `Implemented`. Depends on T018

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: T001 → T002.
- **Foundational (Phase 2)**: T003 after T002; T004 independent of T001–T003.
- **US1 (Phase 3)**: T005 after T003 and T004; T006 after T004; T007 after T003 and T006; T008, T009 after T007.
- **US2 (Phase 4)**: T010 → T011 → T012 → T013, after T008.
- **US3 (Phase 5)**: T014 after T012; T015, T016 after T014.
- **Polish (Phase 6)**: T017 any time after T007; T018 after everything; T019 last.

### User Story Dependencies

- **US1**: needs Phases 1–2.
- **US2**: needs US1's counter in the app (T007, T008).
- **US3**: needs US2's real run to write down (T012).

### Parallel Opportunities

- T004 alongside T001–T003.
- T005 alongside T006 (different files).
- T015 alongside T016.
- T017 alongside any of Phases 4–5.

## Parallel Example: User Story 1

```text
Task: "T005 [US1] AllocationCounterTests.swift"
Task: "T006 [US1] Instrumentation.swift: buckets, self-test result, summary fields"
```

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Phases 1–2: the target, the counter, the buckets.
2. Phase 3: tests, instrumentation, frame loop, live checks 3–5.
3. **Stop and validate**: the self-test says ready and the summaries carry the fields on both platforms.

### Incremental Delivery

1. US1 → the counter is usable by anyone (SKY-4 could start here).
2. US2 → check 25 PASS on iOS (the ticket's "done when").
3. US3 → the method is written for the later checks.

## Notes

- Commit after each phase (`/speckit-implement` "commit on every phase done"), with the ticket key
  (SKY-3) and the phase in the subject, as earlier features did.
- A FAIL in T010 is not a blocker for the tasks before it; it routes through T011.
