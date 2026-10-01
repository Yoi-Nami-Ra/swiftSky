import Foundation
import Synchronization
import Testing

@testable import SwiftSkyPlatform

#if SWIFTSKY_INSTRUMENTATION
import SwiftSkyAllocationCounter

/// Holds a value across a thread hand-off. The semaphore in `onDedicatedThread` orders the write before
/// the read, which is what makes the unchecked conformance sound.
private final class Handoff<Value>: @unchecked Sendable {
    var value: Value?
}

/// Runs `body` on a fresh thread and waits for it, so a counted stretch has a thread of its own: Swift
/// Testing runs other suites concurrently on its own threads, and those must not be counted (FR-002).
private func onDedicatedThread<Value: Sendable>(_ body: @escaping @Sendable () -> Value) -> Value {
    let handoff = Handoff<Value>()
    let done = DispatchSemaphore(value: 0)
    let thread = Thread {
        handoff.value = body()
        done.signal()
    }
    thread.start()
    done.wait()
    return handoff.value!
}

/// The flags the other-thread test shares between its threads. `Atomic` is non-copyable, so it cannot be
/// captured by an escaping closure directly.
private final class OtherThreadFlags: Sendable {
    let started = Atomic<Bool>(false)
    let stop = Atomic<Bool>(false)
    let allocations = Atomic<Int>(0)
}

/// Calls `body` `count` times without allocating. A `for _ in 0..<count` loop cannot be used inside a
/// counted stretch: in an unoptimised build its iterator is the standard library's unspecialised
/// `IndexingIterator.next`, which heap-allocates 40 bytes per step (found by this very counter).
private func repeatWithoutAllocating(_ count: Int, _ body: () -> Void) {
    var done = 0
    while done < count {
        body()
        done += 1
    }
}

/// A heap object of the app's own, for the Swift allocation test.
private final class Cell {
    var value = 0
}

/// libmalloc's `malloc_logger`, read through `dlsym` (contract C4): the address of whichever hook is
/// installed, or `nil`.
private func currentMallocLogger() -> UnsafeRawPointer? {
    let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
    guard let variable = dlsym(defaultHandle, "malloc_logger") else { return nil }
    return variable.load(as: UnsafeRawPointer?.self)
}

/// A C library function that allocates from inside its own image, standing in for Metal in the
/// attribution tests: `strdup` lives in libsystem_c, which no other allocation here passes through.
private let standInGraphicsImage = "/libsystem_c.dylib"

/// Installs the counter for `body` (the built-in graphics list unless `graphicsImage` is given), then
/// removes it.
private func withCounter<Result>(graphicsImage: String? = nil, _ body: () throws -> Result) rethrows -> Result {
    let installed: Bool
    if let graphicsImage {
        installed = graphicsImage.withCString { name in
            var names: [UnsafePointer<CChar>?] = [name]
            return names.withUnsafeMutableBufferPointer { sky_alloc_counter_install($0.baseAddress, 1) }
        }
    } else {
        installed = sky_alloc_counter_install(nil, 0)
    }
    precondition(installed, "the allocation counter was already installed")
    defer { sky_alloc_counter_uninstall() }
    return try body()
}

/// The hook is process-wide, so these tests run one at a time.
@Suite("Allocation counter", .serialized)
struct AllocationCounterTests {
    // MARK: - Counting (SC-001, contract C1)

    @Test("A stretch of N allocations reports exactly N, all the app's", arguments: [0, 1, 10, 1_000])
    func countsExactly(n: Int) {
        let counts = withCounter {
            onDedicatedThread {
                sky_alloc_frame_begin()
                repeatWithoutAllocating(n) { sky_alloc_probe() }
                return sky_alloc_frame_end()
            }
        }
        #expect(counts.app == UInt64(n))
        #expect(counts.graphics == 0)
    }

    @Test("Swift objects count one allocation each")
    func countsSwiftObjects() {
        let n = 100
        let counts = withCounter {
            onDedicatedThread {
                var kept = ContiguousArray<Cell>()
                kept.reserveCapacity(n)
                kept.append(Cell())  // warm-up: the type's metadata is set up outside the stretch
                kept.removeAll(keepingCapacity: true)
                sky_alloc_frame_begin()
                repeatWithoutAllocating(n) { kept.append(Cell()) }
                let counts = sky_alloc_frame_end()
                withExtendedLifetime(kept) {}
                return counts
            }
        }
        #expect(counts.app == UInt64(n))
        #expect(counts.graphics == 0)
    }

    @Test("Another thread's allocations during the stretch are not counted (FR-002)")
    func ignoresOtherThreads() {
        let flags = OtherThreadFlags()
        let counts = withCounter {
            let other = Thread {
                flags.started.store(true, ordering: .releasing)
                var made = 0
                while !flags.stop.load(ordering: .acquiring) || made < 100_000 {
                    sky_alloc_probe()
                    made += 1
                }
                flags.allocations.store(made, ordering: .releasing)
            }
            other.start()
            while !flags.started.load(ordering: .acquiring) {}
            let counts = onDedicatedThread {
                sky_alloc_frame_begin()
                repeatWithoutAllocating(10) { sky_alloc_probe() }
                return sky_alloc_frame_end()
            }
            flags.stop.store(true, ordering: .releasing)
            while flags.allocations.load(ordering: .acquiring) == 0 {}
            return counts
        }
        #expect(flags.allocations.load(ordering: .acquiring) >= 100_000)
        #expect(counts.app == 10)
        #expect(counts.graphics == 0)
    }

    @Test("Nothing is counted outside a stretch")
    func ignoresOutsideStretch() {
        let counts = withCounter {
            onDedicatedThread {
                repeatWithoutAllocating(10) { sky_alloc_probe() }
                sky_alloc_frame_begin()
                let counts = sky_alloc_frame_end()
                repeatWithoutAllocating(10) { sky_alloc_probe() }
                return counts
            }
        }
        #expect(counts.app == 0)
        #expect(counts.graphics == 0)
    }

    // MARK: - Attribution (contract C2)

    @Test("Allocations made inside a graphics image count as the framework's only")
    func attributesGraphicsImages() {
        let counts = withCounter(graphicsImage: standInGraphicsImage) {
            onDedicatedThread {
                let source = strdup("x")!  // outside the stretch
                sky_alloc_frame_begin()
                repeatWithoutAllocating(5) { free(strdup(source)) }
                repeatWithoutAllocating(10) { sky_alloc_probe() }
                let counts = sky_alloc_frame_end()
                free(source)
                return counts
            }
        }
        #expect(counts.graphics == 5)
        #expect(counts.app == 10)
    }

    // MARK: - Install and remove (contract C4)

    @Test("Install chains and uninstall restores the previous logger")
    func installAndUninstall() {
        let before = currentMallocLogger()
        #expect(sky_alloc_counter_install(nil, 0))
        let during = currentMallocLogger()
        #expect(during != nil)
        #expect(during != before)
        #expect(!sky_alloc_counter_install(nil, 0))  // a second install is refused, not stacked
        sky_alloc_counter_uninstall()
        #expect(currentMallocLogger() == before)
        #expect(sky_alloc_counter_install(nil, 0))  // and can be installed again
        sky_alloc_counter_uninstall()
        #expect(currentMallocLogger() == before)
    }
}
#endif

// MARK: - Buckets (research R9)

@Suite("Frame allocation counts")
struct FrameAllocationCountsTests {
    @Test("Frames with and without an event go to their own fields")
    func separatesEventFrames() {
        var counts = FrameAllocationCounts()
        counts.record(app: 2, graphics: 5, appliedEvent: false)
        counts.record(app: 3, graphics: 5, appliedEvent: true)
        counts.record(app: 0, graphics: 5, appliedEvent: false)
        #expect(counts.appAllocations == 2)
        #expect(counts.eventAppAllocations == 3)
        #expect(counts.graphicsAllocations == 15)
    }

    @Test("Only frames without an event that allocated count as allocating frames")
    func countsAllocatingFrames() {
        var counts = FrameAllocationCounts()
        counts.record(app: 1, graphics: 0, appliedEvent: false)
        counts.record(app: 4, graphics: 0, appliedEvent: false)
        counts.record(app: 7, graphics: 0, appliedEvent: true)
        counts.record(app: 0, graphics: 9, appliedEvent: false)
        #expect(counts.allocatingFrames == 2)
    }

    @Test("Reset zeroes every field")
    func resets() {
        var counts = FrameAllocationCounts()
        counts.record(app: 1, graphics: 2, appliedEvent: false)
        counts.record(app: 3, graphics: 4, appliedEvent: true)
        counts.reset()
        #expect(counts == FrameAllocationCounts())
    }
}
