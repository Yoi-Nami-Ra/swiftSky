#if SWIFTSKY_INSTRUMENTATION

/// One refresh period's worth of frame times (003 data-model.md).
struct FrameTimeBucket: Equatable {
    var frames: UInt32 = 0
    var totalSeconds: Double = 0
    var worstSeconds: Double = 0

    static let empty = FrameTimeBucket()
}

/// Mean and worst frame time over the last second, for the debug overlay (003 FR-004, research.md R2).
///
/// Debug and Profiling builds only, like the rest of the instrumentation (001 FR-021e).
///
/// The second is kept as four closed buckets — one per overlay refresh — plus the one being recorded.
/// A bucket closes at each refresh, so the four closed ones always cover exactly the last second the
/// overlay can show. That precision is all a display refreshed four times a second can use, and it
/// costs a fixed, inline store: no heap allocation, O(1) per frame, O(4) per refresh (FR-014).
///
/// ## What does *not* restart it
///
/// A long gap between frames. 002's FPS measurement restarts after one, which is right for FPS because
/// FPS measures gaps. Frame time measures the work *inside* a frame, and a 300 ms frame is followed by
/// a 300 ms gap — so that rule would erase exactly the frame the worst line exists to show (FR-008).
/// The window restarts only when the surface is shown again after being hidden, and when the frame
/// budget changes, both via `restart()`.
struct FrameTimeWindow {
    /// Closed buckets that make up the window. Derived from the refresh rate so the window is one
    /// second; a test pins `bucketCount × OverlayRefreshSchedule.interval == windowSeconds`.
    static let bucketCount = 4
    static let windowSeconds = 1.0

    private var open = FrameTimeBucket.empty
    private var closed = InlineArray<4, FrameTimeBucket>(repeating: .empty)
    private var next = 0

    /// Closed buckets since the last restart, capped at `bucketCount`.
    private(set) var closedCount = 0

    /// Adds one drawn frame's time to the period being recorded.
    mutating func record(frameSeconds: Double) {
        open.frames += 1
        open.totalSeconds += frameSeconds
        if frameSeconds > open.worstSeconds { open.worstSeconds = frameSeconds }
    }

    /// Ends the current period, pushing out the oldest once four are held.
    mutating func closeBucket() {
        closed[next] = open
        next = (next + 1) % Self.bucketCount
        closedCount = min(closedCount + 1, Self.bucketCount)
        open = .empty
    }

    /// Forgets everything, so `mean` and `worst` are `nil` until a full second has been measured again.
    mutating func restart() {
        open = .empty
        for index in closed.indices { closed[index] = .empty }
        next = 0
        closedCount = 0
    }

    /// Mean frame time over the last second, or `nil` until a full second has been measured — or when
    /// no frame was drawn in it.
    var mean: Double? {
        guard closedCount == Self.bucketCount else { return nil }
        var frames: UInt32 = 0
        var total = 0.0
        for index in closed.indices {
            frames += closed[index].frames
            total += closed[index].totalSeconds
        }
        guard frames > 0 else { return nil }
        return total / Double(frames)
    }

    /// Worst frame time over the last second, or `nil` until a full second has been measured.
    var worst: Double? {
        guard closedCount == Self.bucketCount else { return nil }
        var worst = 0.0
        for index in closed.indices where closed[index].worstSeconds > worst {
            worst = closed[index].worstSeconds
        }
        return worst
    }
}

#endif
