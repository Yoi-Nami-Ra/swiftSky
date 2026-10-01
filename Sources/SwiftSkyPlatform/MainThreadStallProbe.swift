#if SWIFTSKY_INSTRUMENTATION

import CoreFoundation
import Darwin
import Synchronization

/// Measures how long the main thread stays busy between two waits of its run loop, and hands the figures
/// to the frame loop for the summary line (012 FR-001–FR-007, contracts C1–C3).
///
/// The frame statistics are measured on the frame loop's own thread, which keeps drawing while the main
/// thread is busy, so they cannot show a main-thread stall. This can: two run-loop observers, one when the
/// main run loop wakes and one when it is about to wait again, in the common modes, so a live resize, a
/// menu or a modal panel is measured too (research R1, R2). If a mode were ever missed, the drag would read
/// as one stretch as long as the drag — a loud failure, never a silent pass.
///
/// ## Threads
///
/// - `tracker` is touched only on the main thread, by the observers. Hence `nonisolated(unsafe)`.
/// - `figures` and `intervalNanoseconds` are atomics: the main thread folds each ended stretch into
///   `figures`; the frame loop takes it in one `exchange` at each summary and publishes the frame interval
///   at each restart. One packed word means a summary's worst stretch and count always belong together
///   (research R4). No lock, no allocation after `install()`, and nothing the Thread Sanitizer can report.
///
/// This is the frame loop's second cross-thread channel, after `pendingEvents`, and the only lock-free one.
/// Instrumented builds only: Release contains none of it (012 FR-008).
final class MainThreadStallProbe: Sendable {
    /// `MainThreadStallFigures`, packed. Written by the main thread, taken by the frame loop.
    private let figures = Atomic<UInt64>(0)

    /// The frame interval a stretch is judged against, in nanoseconds. Written by the frame loop.
    private let intervalNanoseconds = Atomic<UInt64>(16_666_667)

    /// Main thread only.
    nonisolated(unsafe) private var tracker = BusyStretchTracker()

    /// Main thread only: set by `install()`, cleared by `uninstall()`.
    nonisolated(unsafe) private var wakeObserver: CFRunLoopObserver?
    nonisolated(unsafe) private var sleepObserver: CFRunLoopObserver?

    /// Adds the observers to the main run loop's common modes. Main thread; idempotent.
    ///
    /// The wake observer runs first in its pass and the sleep observer last, so all of the pass's work
    /// falls between them.
    func install() {
        guard wakeObserver == nil else { return }
        let wake = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.afterWaiting.rawValue, true, CFIndex.min
        ) { [unowned self] _, _ in
            tracker.afterWaiting(at: Self.now())
        }
        let sleep = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max
        ) { [unowned self] _, _ in
            if let stretch = tracker.beforeWaiting(at: Self.now()) {
                record(stretchNanoseconds: stretch)
            }
        }
        let main = CFRunLoopGetMain()
        CFRunLoopAddObserver(main, wake, .commonModes)
        CFRunLoopAddObserver(main, sleep, .commonModes)
        wakeObserver = wake
        sleepObserver = sleep
    }

    /// Removes the observers. Main thread.
    func uninstall() {
        if let wake = wakeObserver { CFRunLoopObserverInvalidate(wake) }
        if let sleep = sleepObserver { CFRunLoopObserverInvalidate(sleep) }
        wakeObserver = nil
        sleepObserver = nil
        tracker = BusyStretchTracker()
    }

    /// Folds one ended stretch into the figures, against the interval in force now. Called by the sleep
    /// observer; internal so the tests can drive it without a run loop.
    func record(stretchNanoseconds: UInt64) {
        let interval = intervalNanoseconds.load(ordering: .relaxed)
        var current = figures.load(ordering: .relaxed)
        while true {
            let next = MainThreadStallFigures(packed: current)
                .recording(stretchNanoseconds: stretchNanoseconds, intervalNanoseconds: interval)
                .packed
            let (exchanged, original) = figures.compareExchange(
                expected: current, desired: next, ordering: .relaxed
            )
            if exchanged { return }
            current = original
        }
    }

    /// The figures since the last take, and a fresh interval. Frame loop thread, at each summary.
    func take() -> MainThreadStallFigures {
        MainThreadStallFigures(packed: figures.exchange(0, ordering: .relaxed))
    }

    /// Publishes a new frame interval and discards the figures, so the next summary belongs to one
    /// interval (012 FR-006, research R6). Frame loop thread, whenever the budget is relearned.
    func restart(intervalSeconds: Double) {
        intervalNanoseconds.store(UInt64((intervalSeconds * 1e9).rounded()), ordering: .relaxed)
        _ = take()
    }

    /// Monotonic, does not allocate, and is not affected by clock changes.
    private static func now() -> UInt64 {
        clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
    }
}

#endif
