# Contract: The Allocation Counter and the Frame Summary

## C API — `Sources/SwiftSkyAllocationCounter/include/AllocationCounter.h`

Every function is defined only under `SWIFTSKY_INSTRUMENTATION`; Swift calls them only under the same
condition. None of them allocates, takes a lock or may be called from inside the hook.

```c
typedef struct { uint64_t app; uint64_t graphics; } SkyFrameAllocations;

/// Captures the graphics image ranges, then installs the hook (chaining any existing logger).
/// `imageSubstrings` names the graphics images by path substring; NULL selects the built-in list
/// (research R4). Returns false if already installed or no image could be read. Not per frame.
bool sky_alloc_counter_install(const char *const *imageSubstrings, size_t count);

/// Restores the previous logger if ours is still installed. Not per frame.
void sky_alloc_counter_uninstall(void);

/// Opens a counted stretch on the calling thread: zeroes the counts, records the thread and the
/// caller's frame as the walk's limit. Must not be inlined into its caller.
void sky_alloc_frame_begin(void);

/// Closes the stretch and returns its counts.
SkyFrameAllocations sky_alloc_frame_end(void);

/// Allocates exactly once and frees, in a way the optimiser cannot remove. For the self-test and tests.
void sky_alloc_probe(void);

/// Called by the hook, on the counted thread, for every app-side allocation it counts. Does nothing;
/// exists so a debugger breakpoint on it shows the allocating backtrace (quickstart, method step 6).
/// Not inlined.
void sky_alloc_app_allocation(void);
```

**Guarantees**
- C1: Between `begin` and `end` on thread T, every allocation made on T increments exactly one of `app`
  or `graphics`; allocations on other threads, and on T outside a stretch, increment neither.
- C2: An allocation is `graphics` if and only if a return address between the hook and the caller of
  `begin` lies in a captured graphics image; otherwise `app` (fails safe, research R4).
- C3: Frees are never counted. A `realloc` counts once.
- C4: With an earlier logger installed, that logger still receives every event, and uninstalling puts it
  back. The restore is tested (the `malloc_logger` value, read through `dlsym`, is the same after install
  and uninstall as before); the call-through is one line, checked by review.
- C5: In a Release build none of these symbols exists.

## Frame loop (`FrameLoop.swift`)

```text
runLoopMain:   install → self-test (begin, probe, end; ready iff app == 1 and graphics == 0) → log once
               → add display link … invalidate link → summary → uninstall
each frame:    begin → [001 steps 1–5] → end → record counts (appliedEvent) → step 6 (record frame,
               summary every 120 frames)
```

The order of 001's steps 1–6 is unchanged.

## Summary line (log subsystem `com.swiftsky.app`, category `frame`, level notice)

Existing fields unchanged, then the counts:

```text
frames=118 skipped=0 dropped=0 mean=0.21ms worst=0.90ms budget=16.67ms ticks=5040 allocs=0 allocframes=0 eventallocs=0 gfxallocs=472
```

With a failed self-test:

```text
frames=118 skipped=0 dropped=0 mean=0.21ms worst=0.90ms budget=16.67ms ticks=5040 allocs=unavailable
```

Once at start, one of:

```text
allocation counter ready
allocation counter unavailable
```

## PASS rule for check 25 (and the later checks that cite it)

A run passes when, after `allocation counter ready`, every summary line except the first of the run (and
the first after a `budget=` change) shows `allocs=0` and `allocframes=0`. `eventallocs=` is reported, not
judged, by this rule; `gfxallocs=` is recorded as a per-frame reference (`gfxallocs ÷ frames`).
