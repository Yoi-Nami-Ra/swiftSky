// Draw-path allocation counter (011, completing 001 FR-021d). See AllocationCounter.h for the API and
// specs/011-draw-allocation-counter/research.md (R2–R8) for why it is built this way.
//
// Everything below runs, or may run, inside the allocator: the hook is called by libmalloc for every
// allocation and free in the process, on every thread. So nothing here allocates, takes a lock, or
// touches thread-local storage, and every piece of state is a plain static.

#include "AllocationCounter.h"

#if defined(SWIFTSKY_INSTRUMENTATION)

#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// libmalloc's logging hook (R2). Exported by libsystem_malloc but declared only in a private header, so
// it is declared here. It is the hook Apple's allocation tools use: called for every allocation and free
// in every zone — `malloc`, `calloc`, `realloc`, `malloc_type_malloc` (the Swift runtime's entry point),
// and the Objective-C and CoreFoundation allocators. The type mask carries 0x2 for an allocation and 0x4
// for a free; a `realloc` carries both and counts once.
typedef void(sky_malloc_logger_t)(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3,
                                  uintptr_t result, uint32_t framesToSkip);
extern sky_malloc_logger_t *malloc_logger;

enum { SkyLogTypeAllocate = 0x2 };

/// At most this many graphics image ranges are kept (R4). The built-in list matches about ten images.
enum { SkyMaxRanges = 32 };

/// The frame walk gives up after this many frames; an allocation still unattributed is the app's.
enum { SkyMaxWalkFrames = 64 };

/// Return addresses in system code may carry pointer-authentication bits above the virtual address.
/// Every user-space address on Apple platforms fits in 47 bits, so masking strips them harmlessly.
static const uintptr_t SkyAddressMask = ((uintptr_t)1 << 47) - 1;

/// The built-in graphics images, by path substring (R4). An allocation made from inside any of them
/// is the graphics framework's. `AGX` matches the GPU driver bundles; `MTLSimDriver` is the simulator's.
static const char *const SkyDefaultGraphicsImages[] = {
    "/Metal.framework/",       "/MetalTools.framework/", "/QuartzCore.framework/",
    "/IOGPU.framework/",       "/IOSurface.framework/",  "/MTLSimDriver.framework/",
    "AGX",
};

// MARK: - State

static atomic_bool installed;
static sky_malloc_logger_t *previousLogger;

/// `[start, end)` of each graphics image's __TEXT segment. Written by install before the hook is
/// published, read-only afterwards.
static uintptr_t rangeStart[SkyMaxRanges];
static uintptr_t rangeEnd[SkyMaxRanges];
static size_t rangeCount;

/// The thread whose allocations count, and whether a stretch is open (R3). Atomic so a hook call on
/// another thread always reads a whole value; `pthread_self()` reads a register and never allocates,
/// unlike `_Thread_local` storage, which dyld allocates lazily — inside the allocator.
static _Atomic(pthread_t) countedThread;
static atomic_bool counting;

/// The frame of `sky_alloc_frame_begin`'s caller. The walk stops there (R4).
static uintptr_t stackLimit;

/// This stretch's counts. Written only by the hook on `countedThread`, read by that thread at the end.
static uint64_t appCount;
static uint64_t graphicsCount;

// MARK: - Attribution

static bool isGraphicsAddress(uintptr_t address) {
    for (size_t i = 0; i < rangeCount; i++) {
        if (address >= rangeStart[i] && address < rangeEnd[i]) return true;
    }
    return false;
}

/// Walks the frame records from the hook up to the counted stretch's caller (R4). An allocation is the
/// graphics framework's if any return address on the way lies in a graphics image — Metal allocating
/// inside `makeCommandBuffer`, say. Otherwise it is the app's: an allocation that cannot be attributed
/// (an image loaded after install, a library not in the list, a broken chain) counts against the app, so
/// a wrong attribution can turn a PASS into a FAIL, never the reverse.
///
/// The walk must stop at the caller of `sky_alloc_frame_begin`: that is the frame callback, which is
/// itself called from QuartzCore, so walking past it would find a graphics frame above everything.
/// Apple's arm64 ABI requires frame records (`fp[0]` the caller's record, `fp[1]` the return address),
/// so the chain is there; each step still checks it moves up the stack and stays aligned.
static bool isGraphicsAllocation(void) {
    const uintptr_t *fp = (const uintptr_t *)__builtin_frame_address(0);
    for (int depth = 0; depth < SkyMaxWalkFrames; depth++) {
        uintptr_t address = (uintptr_t)fp;
        if (address == 0 || (address & 7) != 0 || address >= stackLimit) return false;
        if (isGraphicsAddress(fp[1] & SkyAddressMask)) return true;
        const uintptr_t *next = (const uintptr_t *)fp[0];
        if ((uintptr_t)next <= address) return false;
        fp = next;
    }
    return false;
}

// MARK: - The hook

static void skyHook(uint32_t type, uintptr_t arg1, uintptr_t arg2, uintptr_t arg3, uintptr_t result,
                    uint32_t framesToSkip) {
    // Chained first, so tools that were already logging (Instruments, MallocStackLogging) keep every
    // event (R7).
    if (previousLogger != NULL) previousLogger(type, arg1, arg2, arg3, result, framesToSkip + 1);

    if ((type & SkyLogTypeAllocate) == 0) return;
    if (!atomic_load_explicit(&counting, memory_order_acquire)) return;
    if (!pthread_equal(pthread_self(), atomic_load_explicit(&countedThread, memory_order_relaxed))) return;

    if (isGraphicsAllocation()) {
        graphicsCount += 1;
    } else {
        appCount += 1;
        sky_alloc_app_allocation();
    }
}

// MARK: - Install and remove

static void captureRanges(const char *const *substrings, size_t substringCount) {
    rangeCount = 0;
    uint32_t imageCount = _dyld_image_count();
    for (uint32_t image = 0; image < imageCount && rangeCount < SkyMaxRanges; image++) {
        const char *name = _dyld_get_image_name(image);
        if (name == NULL) continue;
        bool matches = false;
        for (size_t s = 0; s < substringCount && !matches; s++) {
            matches = strstr(name, substrings[s]) != NULL;
        }
        if (!matches) continue;

        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(image);
        if (header == NULL || header->magic != MH_MAGIC_64) continue;
        intptr_t slide = _dyld_get_image_vmaddr_slide(image);
        const struct load_command *command = (const struct load_command *)(header + 1);
        for (uint32_t c = 0; c < header->ncmds; c++) {
            if (command->cmd == LC_SEGMENT_64) {
                const struct segment_command_64 *segment = (const struct segment_command_64 *)command;
                if (strcmp(segment->segname, SEG_TEXT) == 0) {
                    rangeStart[rangeCount] = (uintptr_t)(segment->vmaddr + slide);
                    rangeEnd[rangeCount] = rangeStart[rangeCount] + (uintptr_t)segment->vmsize;
                    rangeCount += 1;
                    break;
                }
            }
            command = (const struct load_command *)((const char *)command + command->cmdsize);
        }
    }
}

bool sky_alloc_counter_install(const char *const *imageSubstrings, size_t count) {
    if (atomic_load(&installed)) return false;
    if (imageSubstrings == NULL) {
        imageSubstrings = SkyDefaultGraphicsImages;
        count = sizeof(SkyDefaultGraphicsImages) / sizeof(SkyDefaultGraphicsImages[0]);
    }
    captureRanges(imageSubstrings, count);
    if (_dyld_image_count() == 0) return false;

    // Everything the hook reads is in place before it is published.
    previousLogger = malloc_logger;
    atomic_store(&counting, false);
    __atomic_store_n(&malloc_logger, &skyHook, __ATOMIC_RELEASE);
    atomic_store(&installed, true);
    return true;
}

void sky_alloc_counter_uninstall(void) {
    if (!atomic_load(&installed)) return;
    atomic_store(&counting, false);
    // Only put the previous logger back if nobody replaced ours in the meantime.
    sky_malloc_logger_t *expected = &skyHook;
    __atomic_compare_exchange_n(&malloc_logger, &expected, previousLogger, false, __ATOMIC_ACQ_REL,
                                __ATOMIC_ACQUIRE);
    atomic_store(&installed, false);
}

// MARK: - Counted stretches

__attribute__((noinline)) void sky_alloc_frame_begin(void) {
    appCount = 0;
    graphicsCount = 0;
    // This function's frame record holds the caller's frame pointer: the walk's limit.
    stackLimit = *(const uintptr_t *)__builtin_frame_address(0);
    atomic_store_explicit(&countedThread, pthread_self(), memory_order_relaxed);
    atomic_store_explicit(&counting, true, memory_order_release);
}

__attribute__((noinline)) SkyFrameAllocations sky_alloc_frame_end(void) {
    atomic_store_explicit(&counting, false, memory_order_release);
    SkyFrameAllocations counts = {.app = appCount, .graphics = graphicsCount};
    return counts;
}

// MARK: - Probe and breakpoint target

__attribute__((noinline)) void sky_alloc_probe(void) {
    // Through a volatile pointer, so the compiler cannot pair the two calls and remove both (R2's spike
    // lost exactly these to clang at -O2).
    void *volatile block = malloc(16);
    free(block);
}

__attribute__((noinline)) void sky_alloc_app_allocation(void) {
    __asm__ volatile("");
}

#endif
