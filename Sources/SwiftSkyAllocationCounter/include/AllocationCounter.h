// Draw-path allocation counter (011, completing 001 FR-021d).
//
// Counts the heap allocations one thread makes inside a "counted stretch" — for the frame loop, one
// frame — and splits them into the app's own and the graphics framework's. Debug builds only: the
// definitions exist only under SWIFTSKY_INSTRUMENTATION, and Swift calls them only under the same
// condition, so a release build contains none of it (001 FR-021e).
//
// None of these functions allocates, and none may be called from inside the hook itself.
// The API and its guarantees are in specs/011-draw-allocation-counter/contracts/allocation-counter.md.

#ifndef SWIFTSKY_ALLOCATION_COUNTER_H
#define SWIFTSKY_ALLOCATION_COUNTER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// The counts of one counted stretch.
typedef struct {
    /// Allocations made by the app's own code.
    uint64_t app;
    /// Allocations made from inside a call into the graphics framework (Metal, QuartzCore, the driver).
    uint64_t graphics;
} SkyFrameAllocations;

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

#endif
