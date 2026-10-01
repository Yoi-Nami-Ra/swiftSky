# Research: Count Draw-Path Allocations and Verify Zero on iOS

Decision record for [plan.md](./plan.md). Spikes were run on 2026-10-01 on the development Mac (Apple
silicon, macOS 26, Xcode 27.0 RC), from throwaway C files in the session scratchpad.

---

## R1. The Profiling configuration carries no instrumentation into the package

**Finding**: A Profiling build of `swiftSky (macOS)` compiles the package's layer targets with their
**Release** settings. `SWIFT_ACTIVE_COMPILATION_CONDITIONS = SWIFTSKY_INSTRUMENTATION` is set on the
Xcode project's Profiling configuration and reaches the app module (`-module-name swiftSky`) only; the
`SwiftSkyPlatform` compile has `-O -whole-module-optimization` and no `-DSWIFTSKY_INSTRUMENTATION`.
The package's PIF has only `Debug` (with the define, from `Package.swift`'s `.when(configuration:
.debug)`) and `Release` (without), and Xcode maps the unknown name `Profiling` to `Release`. The built
binary contains none of the summary's format strings (`strings -a … | grep dropped=` → 0).

**Decision**: The Debug build decides check 25's PASS and carries SC-005's before/after (spec
Clarifications, revised). Fixing the Profiling configuration is out of scope and is reported for a
ticket of its own. Evidence recorded elsewhere as coming from "Profiling builds" (008 #12, 009 #9, 001's
R12) should be re-read in that light.

**Rationale**: SwiftPM has no custom configurations; there is no package-side condition that tells
Profiling from Release. Any fix (a separate package configuration, a different mapping, or moving the
define elsewhere) changes how every layer is built and deserves its own review. An unoptimised build
allocates at least as often as an optimised one — the optimiser removes allocations (stack promotion,
specialisation, closure inlining), it does not add them — so a Debug zero is the stricter result.

**Alternatives considered**: deciding PASS on an optimised build — impossible without the fix;
`unsafeFlags(["-O"])` for Debug — would make every Debug build optimised and hurt debugging.

---

## R2. How allocations are counted: `malloc_logger`

**Decision**: Install a callback in libmalloc's exported `malloc_logger` hook while the frame loop runs.
libmalloc calls it for every allocation and free, in every zone, with a type mask (allocate = `0x2`,
deallocate = `0x4`; a `realloc` carries both). Every allocation the frame path can make goes through it:
`malloc`, `calloc`, `realloc`, large allocations, `malloc_type_malloc` (the typed entry point the Swift
runtime's `swift_slowAlloc` uses), and the Objective-C / CoreFoundation allocators.

**Spike**: a C program installed the hook at run time, counted on one thread, and made 10 `malloc`s, a
`calloc`, a `realloc`, a 1 MB `malloc`, a `strdup`, a `CFStringCreateWithCString` and a
`malloc_type_malloc`, while a second thread made 100,000 `malloc`/`free` pairs. Result: exactly **16**
allocations counted, **0** from the other thread. (A first run at `-O2` counted 2: clang had removed the
`malloc`/`free` pairs it could see. Tests and the self-test must allocate through a call the optimiser
cannot see through — R8, R10.)

**Rationale**: It is the hook Apple's own allocation tools use, so it sees what Instruments sees; it
needs no Instruments session, no environment variable and no relaunch; it works on macOS, iOS devices and
the simulator alike; and the counting code stays in one small file.

**Alternatives considered**:
- **Instruments / `xctrace`** — the recording failed to attach or never finished from a session (002
  check 15, 003 check 13), and the per-thread count cannot be exported without the UI (009 check 9).
- **`malloc_zone_statistics`** — process-wide (other threads' allocations land in it), net of frees (an
  allocation freed in the same frame vanishes), and takes zone locks. Fine for 004's isolated benchmark,
  wrong for a frame.
- **Replacing the default zone's function pointers** — zones are read-only after start-up on current
  systems, and the xzone allocator's fast paths bypass them. Kept as the fallback should `malloc_logger`
  ever stop being called; the headless tests (R10) would catch that at once.
- **dyld interposing of `malloc`** — applies only to images inserted at launch.
- **Swift runtime allocation hooks** — miss every C and Objective-C allocation, including Metal's.

---

## R3. Counting one thread without thread-local storage

**Decision**: The frame loop's thread is recorded (`pthread_self()`) when a frame begins; the callback's
first test is a flag plus `pthread_equal(pthread_self(), recorded)`, and every other thread returns at
once. The per-frame counts are plain globals written only by the callback on that thread and read by
that thread when the frame ends. The recorded thread and the counting flag are written with atomic
stores, so a callback on another thread reads a whole value.

**Rationale**: `pthread_self()` reads a register; it never allocates. A `_Thread_local` or `__thread`
variable is allocated lazily by dyld on first use in each thread — inside a malloc hook that means
re-entering the allocator from the hook itself.

---

## R4. Telling the app's allocations from the graphics framework's

**Decision**: On each counted allocation, walk the frame-pointer chain from the callback upward, stopping
at the frame that called `frame_begin` (recorded as a stack address when the frame begins), at 64 frames,
or at a malformed link. If any return address on the way lies in the `__TEXT` segment of a **graphics
image**, the allocation is the framework's; otherwise it is the app's. The graphics images are found by
path when the counter is installed: `/Metal.framework/`, `/MetalTools.framework/`, `/QuartzCore.framework/`,
`/IOGPU.framework/`, `/IOSurface.framework/`, `/MTLSimDriver.framework/` and any image whose name contains
`AGX` (the GPU driver bundles). Up to 32 ranges, captured once.

**Spike**: with `libsystem_c` standing in for a graphics image, 10 `malloc`s made directly were counted as
the app's, 5 `strdup`s (which allocate from inside `libsystem_c`) as the framework's, and a
CoreFoundation string as the app's: **11 / 5**, exactly.

**Rationale**:
- It needs no change to the rendering layer (spec FR-010): the renderer cannot import the platform layer,
  and bracketing each Metal call would spread instrumentation through every encode path.
- Stopping at the frame callback matters: the callback itself is called from QuartzCore, so a full walk
  would find a graphics frame above every allocation.
- **It fails safe.** An allocation that cannot be attributed — an image loaded after installation, a
  library not in the list, a broken frame chain — is counted as the app's. A wrong attribution can turn a
  PASS into a FAIL that is then investigated, never a FAIL into a PASS.
- Apple's arm64 ABI requires frame records, and macOS x86_64 system code keeps them, so the walk is
  reliable on every supported destination. Each step checks that the next frame is higher on the stack
  and 8-byte aligned.

**Alternatives considered**: `dladdr` per allocation (takes dyld's lock, may allocate); `backtrace()`
(cannot stop at the callback's frame); counting everything in `render(...)` as one bucket (would hide app
allocations among Metal's); marking stretches from the renderer (layer change, noisy).

---

## R5. Where the code lives, and keeping it out of Release

**Decision**: A new C target, `SwiftSkyAllocationCounter` (`Sources/SwiftSkyAllocationCounter/`), with no
dependencies, depended on by `SwiftSkyPlatform` only. Its C source is wrapped in `#if
SWIFTSKY_INSTRUMENTATION`, defined by a `cSettings` entry with the same `.when(configuration: .debug)`
condition the Swift targets use, so a Release build compiles it to an empty object. Every Swift reference
to it is inside `#if SWIFTSKY_INSTRUMENTATION`. Release absence is checked as 001 check 27 does, by
inspecting the built product (quickstart check 5).

**Rationale**: A malloc hook must not itself allocate, retain, take a lock or trigger lazy initialisation.
Plain C gives that guarantee by construction; Swift globals are lazily initialised through `swift_once`,
and Swift cannot declare the `malloc_logger` variable at all. The header declares the C functions only;
the `malloc_logger` declaration stays private to the `.c` file.

**Alternatives considered**: Swift with `dlsym` to reach the variable (lazy globals and retain/release in
the hook); putting the C file into an existing target (SwiftPM targets are single-language).

---

## R6. The counted stretch in the frame loop

**Decision**: The delegate method `metalDisplayLink(_:needsUpdate:)` begins counting on entry and ends it
after the draw. The body that is counted — 001's steps 1 to 5: events, renderability, the clock, the
overlay's snapshot, the advance, the arrival line, the draw — moves into one private method that returns
the frame's outcome (not renderable, skipped or presented) and whether it applied an event. Step 6 (record the frame, write the
summary) runs after counting has ended. `applyPendingEvents()` returns whether it applied any event.

**Rationale**: Ending the stretch explicitly, rather than in a `defer` at the top, keeps the summary's
formatting out of the count (spec FR-006), and the early return for a non-renderable surface is still
covered. Frame order is unchanged.

---

## R7. Installing, chaining and removing the hook

**Decision**: The loop thread installs the counter in `runLoopMain()` before it adds the display link, and
removes it after the link is invalidated. Installing captures the graphics image ranges first, then
publishes the callback with an atomic store. If another logger is already installed (Instruments,
`MallocStackLogging`), its pointer is kept and called first from ours, so the tools keep working;
removal restores it only if ours is still the installed one.

**Rationale**: The hook is process-wide. Installing it from the loop thread ties its lifetime to the loop,
and chaining honours the spec's "Instruments attached" edge case.

---

## R8. Proving the counter is live: a self-test at start

**Decision**: Right after installing, the loop thread runs one counted stretch that calls
`sky_alloc_probe()` — a C function that allocates once and frees, through a `volatile` pointer so the
compiler cannot remove the pair — and checks that it counted exactly one app-side allocation. It logs
`allocation counter ready` or `allocation counter unavailable` once. When unavailable, the summary
reports `allocs=unavailable` in place of the four counts.

**Rationale**: Check 25's PASS is a count of zero, and a counter that silently stopped counting also
reports zero. The self-test turns that false PASS into a visible failure, without a launch argument
(Principle V).

---

## R9. Report format and restart

**Decision**: The summary appends, after `ticks=`:

```text
allocs=<A> allocframes=<F> eventallocs=<E> gfxallocs=<G>
```

`A`: app-side allocations on frames without an event; `F`: frames without an event that made at least one
app-side allocation; `E`: app-side allocations on frames with an event; `G`: graphics framework allocations on
all frames. All four restart after each summary and on `updateBudget(seconds:)`, like the existing
counters. The buckets live in `Instrumentation`, filled by one call per frame; the C side only counts the
current frame.

**Rationale**: Lowercase `key=value`, appended, matches the existing fields so earlier readers of the line
keep working (spec FR-006).

---

## R10. Tests

**Decision**: `Tests/SwiftSkyPlatformTests/AllocationCounterTests.swift`, a `.serialized` suite (the hook
is process-wide). Each test runs its counted body on a dedicated `Thread` and waits for it:
- exactly N in {0, 1, 10, 1,000} `sky_alloc_probe()` calls → N app-side (SC-001);
- the same with Swift class instances, after one warm-up allocation so lazy metadata is excluded;
- 100,000 allocations on a second thread during the stretch → 0 added;
- with the test's graphics list naming `/libsystem_c.dylib`, `strdup` allocations → the framework count
  only, direct `malloc`s → the app count only;
- allocations outside a stretch on the counted thread → 0;
- install / uninstall restores the previous logger; a second install chains rather than replaces.
The bucket arithmetic of R9 (event versus non-event frames, allocating frames, restart) is tested on
`FrameAllocationCounts` as a plain struct. The tests create no Metal device (`verify.sh`'s guard).

**Rationale**: The hook's behaviour is the logic that must be right for check 25 to mean anything; it is
exercised headlessly through the same C functions the frame loop calls (Principle II). The test target
gains a dependency on `SwiftSkyAllocationCounter` so the explicit-import check passes.

---

## R11. Cost

**Decision**: No benchmark beyond SC-005's before/after. Per allocation on another thread the callback
does one flag load and returns; on the counted thread, one compare, a walk of at most 64 frames against
at most 32 ranges, and an increment. On a frame that allocates nothing it adds two function calls.

**Rationale**: The frame path is meant to make no allocations, so the walk runs only when there is
already a defect to find; the before/after run shows whether anything else changed.

---

## R12. An optimised build with the counter: Release plus a command-line condition

**Finding** (during T008): in a Debug build every `for` loop over a range or an `InlineArray` heap-allocates
40 bytes per step. Built `-Onone`, the loop calls the standard library's unspecialised
`IndexingIterator.next`, which boxes the element. The counter showed it on every frame: in
`Simulation.advance(_:ticks:)` (`for _ in 0..<ticks`), in `FrameTimeWindow.mean` and `.worst` (4 Hz), and
in this feature's own first tests. None of it exists in an optimised build, where the loop is specialised
and inlined. R1's "an unoptimised build allocates at least as often, so its zero is stricter" was true
and useless: a Debug run cannot pass, and its failures say nothing about the shipped code.

**Decision**: Check 25, SC-005 and "the method" use a **Release build with the instrumentation condition
added on the `xcodebuild` command line**:

```sh
xcodebuild build -project swiftSky.xcodeproj -scheme "swiftSky (iOS)" -configuration Release \
  -destination "platform=iOS Simulator,id=<udid>" -derivedDataPath <dir> \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION' \
  'GCC_PREPROCESSOR_DEFINITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION=1'
```

Command-line build settings apply to every target, package targets included, so the layers compile `-O`
with `-DSWIFTSKY_INSTRUMENTATION` and the counter's C file with the define (checked in the build log),
and the app carries the summary and the counter (`strings`, `nm`). The Debug build's figures are still
recorded, for information.

**Rationale**: It is the build Q1 asked for — optimised, with the counter — and needs no project change.
Making the Profiling configuration do the same stays out of scope (R1).

---

## R13. The text renderer's per-frame completion handler allocated

**Finding** (T010/T011, optimised build): exactly one app-side allocation per frame with text, from
`_Block_copy` called directly by `TextRenderer.encode`. `commandBuffer.addCompletedHandler(releaseSlot)`
bridges the stored Swift closure into a new Objective-C block on every call, and the block is copied to
the heap. This settles 002 R5's open question ("whether `addCompletedHandler` with a stored block is
allocation-free"): it is not. Storing the handler as a `@convention(block)` value made it worse, two
allocations per frame: Swift wraps the block in a Swift closure and re-bridges it.

**Decision**: No completion handler. Each ring slot remembers the command buffer that last read it, and
`acquireSlot()` takes the next slot only when that command buffer's `status` is `.completed` or `.error`;
`releaseUnusedSlot()` steps the ring back. Slots are used in order and command buffers complete in order,
so checking the next slot is enough. The invariant is the same — never overwrite instances the GPU may
still read — and the frame is still skipped, never blocked, when the slot is busy.

**Result**: the macOS optimised run went from `allocs=120 allocframes=120` per 120 frames to
`allocs=0 allocframes=0`.
