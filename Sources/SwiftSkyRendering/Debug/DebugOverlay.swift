#if SWIFTSKY_INSTRUMENTATION

import SwiftSkySimulation

/// The frame statistics the debug overlay shows, as of its last refresh (003 FR-004).
///
/// Defined here, by its consumer, and filled in by the platform layer's instrumentation — the same
/// arrangement as `RenderSurface`. The rendering layer never reads the frame loop or the
/// instrumentation; it is handed this value (FR-015). The budget, dropped, skipped and tick values are
/// the very fields the instrumentation's log line prints, so the screen and the log cannot disagree
/// (FR-013).
///
/// Seconds throughout, as the instrumentation stores them. The overlay converts when it writes.
public struct DebugOverlayStatistics: Sendable, Equatable {
    /// Mean frame time over the last second, or `nil` until a full second has been measured.
    public var meanFrameSeconds: Double?

    /// Worst frame time over the last second, or `nil` until a full second has been measured.
    public var worstFrameSeconds: Double?

    /// The budget each frame is judged against.
    public var budgetSeconds: Double

    /// Frames that overran the budget, since the instrumentation last started counting.
    public var droppedFrames: UInt64

    /// Frames not drawn for want of a drawable, over the same span.
    public var skippedFrames: UInt64

    /// The simulation's tick count.
    public var tickCount: UInt64

    public init(
        meanFrameSeconds: Double?,
        worstFrameSeconds: Double?,
        budgetSeconds: Double,
        droppedFrames: UInt64,
        skippedFrames: UInt64,
        tickCount: UInt64
    ) {
        self.meanFrameSeconds = meanFrameSeconds
        self.worstFrameSeconds = worstFrameSeconds
        self.budgetSeconds = budgetSeconds
        self.droppedFrames = droppedFrames
        self.skippedFrames = skippedFrames
        self.tickCount = tickCount
    }
}

/// What the ship and its order were at the overlay's last refresh (015 FR-005).
///
/// Taken by the frame loop from the simulation state at the refresh, before that frame advances it: the
/// latest completed tick, never the interpolated pose the ship is drawn at (013). Plain values only, so
/// the overlay never holds the state's planned path (015 FR-011).
public struct DebugOverlayShip: Sendable, Equatable {
    /// The order being flown, with the autopilot's phase and the distance still to go.
    public struct Order: Sendable, Equatable {
        public var phase: AutopilotPhase
        public var destination: Vector2
        public var distance: Double

        public init(phase: AutopilotPhase, destination: Vector2, distance: Double) {
            self.phase = phase
            self.destination = destination
            self.distance = distance
        }
    }

    /// World units.
    public var position: Vector2

    /// World units per second.
    public var velocity: Vector2

    /// Radians, in (−π, π].
    public var heading: Double

    /// Radians per second, counter-clockwise positive.
    public var angularVelocity: Double

    /// `nil` without an order.
    public var order: Order?

    public init(position: Vector2, velocity: Vector2, heading: Double, angularVelocity: Double, order: Order?) {
        self.position = position
        self.velocity = velocity
        self.heading = heading
        self.angularVelocity = angularVelocity
        self.order = order
    }

    /// The ship and order as `state` holds them. An order without a phase, which the autopilot never
    /// produces, is treated as no order. Allocates nothing.
    public init(_ state: SimulationState) {
        let ship = state.ship
        position = ship.position
        velocity = ship.velocity
        heading = ship.heading
        angularVelocity = ship.angularVelocity
        if let destination = state.autopilot.order?.destination,
           let phase = state.autopilot.phase,
           let distance = state.distanceRemaining {
            order = Order(phase: phase, destination: destination, distance: distance)
        } else {
            order = nil
        }
    }
}

/// The live debug overlay: six labelled lines of frame statistics in the safe area's top-left corner
/// (003 FR-001–FR-005).
///
/// Debug and Profiling builds only, and compiled out of Release entirely, labels and all, so no build
/// setting or launch argument can put it on screen there (FR-009, SC-005).
///
/// The values change only when the frame loop hands over a new snapshot, four times a second, but the
/// text is rewritten every frame from the last one — as 002's test string is, and as it must be: a
/// backing-scale change replaces the buffer's metrics without re-laying-out what was already written
/// (002 research.md R8).
public final class DebugOverlay {
    /// The last snapshot, or `nil` before the first one arrives, in which case nothing is drawn.
    public var statistics: DebugOverlayStatistics?

    /// The ship and order at the last snapshot, written under the frame statistics (015). `nil` writes
    /// the six frame-statistic lines only.
    public var ship: DebugOverlayShip?

    /// Each label is exactly eight columns, so every value starts in the same column.
    static let meanLabel: StaticString = "mean    "
    static let worstLabel: StaticString = "worst   "
    static let budgetLabel: StaticString = "budget  "
    static let droppedLabel: StaticString = "dropped "
    static let skippedLabel: StaticString = "skipped "
    static let ticksLabel: StaticString = "ticks   "
    static let unit: StaticString = " ms"
    static let unknown: StaticString = "--"

    /// Frame times are right-aligned in six columns, which holds `999.99`.
    static let millisecondsWidth = 6

    public init() {}

    /// Writes this frame's overlay into `buffer`, 8 points in from the safe area's top-left. Allocates
    /// nothing.
    ///
    /// The renderer clears the buffer before calling this, as it does for `DebugTextPattern`. Every
    /// write is capped at the remaining capacity, so this never overflows.
    public func write(into buffer: TextBuffer, surface: RenderSurface) {
        guard let statistics else { return }

        buffer.begin(at: (
            x: surface.safeAreaInsets.left + DebugTextPattern.insetPoints,
            y: surface.safeAreaInsets.top + DebugTextPattern.insetPoints
        ))

        writeMilliseconds(Self.meanLabel, statistics.meanFrameSeconds, into: buffer)
        buffer.newline()
        writeMilliseconds(Self.worstLabel, statistics.worstFrameSeconds, into: buffer)
        buffer.newline()
        writeMilliseconds(Self.budgetLabel, statistics.budgetSeconds, into: buffer)
        buffer.newline()
        writeCount(Self.droppedLabel, statistics.droppedFrames, into: buffer)
        buffer.newline()
        writeCount(Self.skippedLabel, statistics.skippedFrames, into: buffer)
        buffer.newline()
        writeCount(Self.ticksLabel, statistics.tickCount, into: buffer)
    }

    private func writeMilliseconds(_ label: StaticString, _ seconds: Double?, into buffer: TextBuffer) {
        buffer.write(label, limit: buffer.remainingCapacity)
        if let seconds {
            buffer.writeHundredths(seconds * 1000, width: Self.millisecondsWidth, limit: buffer.remainingCapacity)
        } else {
            buffer.writePadded(Self.unknown, width: Self.millisecondsWidth, limit: buffer.remainingCapacity)
        }
        buffer.write(Self.unit, limit: buffer.remainingCapacity)
    }

    private func writeCount(_ label: StaticString, _ value: UInt64, into buffer: TextBuffer) {
        buffer.write(label, limit: buffer.remainingCapacity)
        buffer.write(value, limit: buffer.remainingCapacity)
    }
}

#endif
