/// The frame path's heap allocations over one summary interval: the four fields the frame summary adds
/// after `ticks=` (011 research R9).
///
/// Frames that applied a queued event (a resize, a tap) are kept apart, because 008 and 009 require only
/// the frames *without* an event to be free of allocations (011 FR-004): draining an event may allocate,
/// and an idle frame must not. Allocations made inside the graphics framework are kept apart too, as a
/// reference rather than a gate (011 FR-003, SC-004).
///
/// Plain integers, so recording a frame allocates nothing (001 FR-021f). Compiled in every build, like
/// the other measurement structs, so its arithmetic is tested headlessly; only `Instrumentation` holds
/// one, and only in instrumented builds.
struct FrameAllocationCounts: Equatable {
    /// App-side allocations on frames that applied no event (`allocs=`).
    private(set) var appAllocations: UInt64 = 0

    /// App-side allocations on frames that applied an event (`eventallocs=`).
    private(set) var eventAppAllocations: UInt64 = 0

    /// Frames that applied no event and made at least one app-side allocation (`allocframes=`): whether
    /// allocations are spread over every frame or come from one.
    private(set) var allocatingFrames: UInt64 = 0

    /// Graphics framework allocations, on every frame (`gfxallocs=`).
    private(set) var graphicsAllocations: UInt64 = 0

    /// Adds one frame's counts.
    mutating func record(app: UInt64, graphics: UInt64, appliedEvent: Bool) {
        if appliedEvent {
            eventAppAllocations += app
        } else {
            appAllocations += app
            if app > 0 { allocatingFrames += 1 }
        }
        graphicsAllocations += graphics
    }

    /// Starts a new interval: after each summary, and when the frame budget is relearned (011 FR-007).
    mutating func reset() {
        self = FrameAllocationCounts()
    }
}
