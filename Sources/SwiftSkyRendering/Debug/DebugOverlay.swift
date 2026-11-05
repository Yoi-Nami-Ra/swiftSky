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

    /// The cargo hold as of the same tick (022): plain values, so the overlay never holds the ship.
    public struct Cargo: Sendable, Equatable {
        public var capacity: Int
        public var used: Int
        public var free: Int
        public var count: Int
        /// Tons per commodity index; slots from `count` on are 0.
        public var amounts: InlineArray<16, Int>

        public init(capacity: Int, used: Int, free: Int, count: Int, amounts: InlineArray<16, Int>) {
            self.capacity = capacity
            self.used = used
            self.free = free
            self.count = count
            self.amounts = amounts
        }

        public init(_ hold: CargoHold) {
            capacity = hold.capacity
            used = hold.used
            free = hold.free
            count = hold.commodityCount
            var amounts = InlineArray<16, Int>(repeating: 0)
            var index = 0
            while index < CargoHold.maxCommodities {
                amounts[index] = hold.tons(of: index)
                index += 1
            }
            self.amounts = amounts
        }

        public static func == (lhs: Cargo, rhs: Cargo) -> Bool {
            guard lhs.capacity == rhs.capacity, lhs.used == rhs.used, lhs.free == rhs.free,
                  lhs.count == rhs.count else { return false }
            var index = 0
            while index < 16 {
                if lhs.amounts[index] != rhs.amounts[index] { return false }
                index += 1
            }
            return true
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

    /// The hold, or `nil` to write no cargo lines (the memberwise default).
    public var cargo: Cargo?

    public init(
        position: Vector2,
        velocity: Vector2,
        heading: Double,
        angularVelocity: Double,
        order: Order?,
        cargo: Cargo? = nil
    ) {
        self.cargo = cargo
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
        cargo = Cargo(ship.hold)
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
/// (003 FR-001–FR-005), followed by the ship and its order (015).
///
/// Debug and instrumented Release builds only (`Scripts/build-instrumented.sh`), and compiled out of
/// plain Release entirely, labels and all, so no launch argument can put it on screen there (FR-009,
/// SC-005).
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

    /// `false` for `--no-debug-cargo`: every cargo line is left out (022).
    public var showsCargo = true

    /// Commodity names as ASCII, encoded once at construction: slot `i` is
    /// `nameBytes[i * nameColumns ..< i * nameColumns + nameLengths[i]]`. A slot with no name holds `?`.
    private let nameBytes: ContiguousArray<UInt8>
    private let nameLengths: ContiguousArray<Int>

    /// The most columns of a commodity name the overlay shows.
    static let nameColumns = 10

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

    /// The ship and order lines' labels (015 FR-002–FR-004): eight columns, like the frame statistics'.
    /// The vector lines carry their `x` straight after the label.
    static let positionLabel: StaticString = "pos     x"
    static let velocityLabel: StaticString = "vel     x"
    static let speedLabel: StaticString = "speed   "
    static let headingLabel: StaticString = "heading "
    static let turnLabel: StaticString = "turn    "
    static let ySeparator: StaticString = " y"
    static let speedUnit: StaticString = " u/s"
    static let degreesUnit: StaticString = " deg"
    static let degreesPerSecondUnit: StaticString = " deg/s"
    static let orderLabel: StaticString = "order   "
    static let noOrder: StaticString = "none"
    static let destinationLabel: StaticString = "dest    x"
    static let distanceLabel: StaticString = "dist    "
    static let distanceUnit: StaticString = " u"

    /// The phase as the order line writes it: lower case, as named (015 FR-003).
    static func phaseText(_ phase: AutopilotPhase) -> StaticString {
        switch phase {
        case .aligning: "aligning"
        case .burning: "burning"
        case .flipping: "flipping"
        case .braking: "braking"
        case .arrived: "arrived"
        }
    }

    /// Ship and order values are signed and right-aligned in nine columns, which holds `-99999.99`.
    static let valueWidth = 9

    /// The heading in degrees for the heading line: radians × 180/π, except that a value that rounds to
    /// −180.00 is 180, so the seam always reads `180.00` (015 FR-002).
    static func headingDegrees(_ radians: Double) -> Double {
        let degrees = radians * 180 / .pi
        return (degrees * 100).rounded(.toNearestOrAwayFromZero) <= -18_000 ? 180 : degrees
    }

    /// - Parameter commodityNames: the list's names in index order (022). Non-ASCII becomes `?` and a
    ///   name is cut to ten columns. Empty, or shorter than a hold's slots, leaves `?` for the rest.
    public init(commodityNames: [String] = []) {
        var bytes = ContiguousArray<UInt8>(repeating: UInt8(ascii: "?"), count: CargoHold.maxCommodities * Self.nameColumns)
        var lengths = ContiguousArray<Int>(repeating: 1, count: CargoHold.maxCommodities)
        for (slot, name) in commodityNames.prefix(CargoHold.maxCommodities).enumerated() {
            var length = 0
            for character in name {
                guard length < Self.nameColumns else { break }
                let ascii = character.unicodeScalars.count == 1 ? character.asciiValue : nil
                bytes[slot * Self.nameColumns + length] =
                    ascii.flatMap { $0 >= 0x20 && $0 <= 0x7E ? $0 : nil } ?? UInt8(ascii: "?")
                length += 1
            }
            lengths[slot] = max(length, 1)
        }
        nameBytes = bytes
        nameLengths = lengths
    }

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

        if let ship {
            writeShip(ship, into: buffer)
        }
    }

    /// The ship lines, each on a new line after the frame statistics, then the order (015 FR-002–FR-004).
    private func writeShip(_ ship: DebugOverlayShip, into buffer: TextBuffer) {
        buffer.newline()
        writeVector(Self.positionLabel, ship.position, into: buffer)
        buffer.newline()
        writeVector(Self.velocityLabel, ship.velocity, into: buffer)
        buffer.newline()
        let speed = (ship.velocity.x * ship.velocity.x + ship.velocity.y * ship.velocity.y).squareRoot()
        writeValue(Self.speedLabel, speed, unit: Self.speedUnit, into: buffer)
        buffer.newline()
        writeValue(Self.headingLabel, Self.headingDegrees(ship.heading), unit: Self.degreesUnit, into: buffer)
        buffer.newline()
        writeValue(Self.turnLabel, ship.angularVelocity * 180 / .pi, unit: Self.degreesPerSecondUnit, into: buffer)
        buffer.newline()
        writeOrder(ship.order, into: buffer)
        if showsCargo, let cargo = ship.cargo {
            writeCargo(cargo, into: buffer)
        }
    }

    static let holdLabel: StaticString = "hold    "
    static let holdSeparator: StaticString = " / "
    static let holdUnit: StaticString = " t  free "
    static let cargoIndent: StaticString = "  "

    /// `hold    <used> / <capacity> t  free <free>`, then `  <name> <tons>` per non-zero commodity (022).
    /// Allocates nothing: numbers go through `write(UInt64)`, names from the pre-encoded table.
    private func writeCargo(_ cargo: DebugOverlayShip.Cargo, into buffer: TextBuffer) {
        buffer.newline()
        buffer.write(Self.holdLabel, limit: buffer.remainingCapacity)
        buffer.write(UInt64(max(0, cargo.used)), limit: buffer.remainingCapacity)
        buffer.write(Self.holdSeparator, limit: buffer.remainingCapacity)
        buffer.write(UInt64(max(0, cargo.capacity)), limit: buffer.remainingCapacity)
        buffer.write(Self.holdUnit, limit: buffer.remainingCapacity)
        buffer.write(UInt64(max(0, cargo.free)), limit: buffer.remainingCapacity)
        var slot = 0
        while slot < min(cargo.count, CargoHold.maxCommodities) {
            let tons = cargo.amounts[slot]
            if tons > 0 {
                buffer.newline()
                buffer.write(Self.cargoIndent, limit: buffer.remainingCapacity)
                nameBytes.withUnsafeBufferPointer { all in
                    let name = UnsafeBufferPointer(
                        rebasing: all[(slot * Self.nameColumns)..<(slot * Self.nameColumns + nameLengths[slot])])
                    buffer.write(asciiBytes: name, limit: buffer.remainingCapacity)
                }
                buffer.write(" ", limit: buffer.remainingCapacity)
                buffer.write(UInt64(tons), limit: buffer.remainingCapacity)
            }
            slot += 1
        }
    }

    /// `order   none`, or the phase followed by the destination and distance lines (015 FR-003, FR-004).
    private func writeOrder(_ order: DebugOverlayShip.Order?, into buffer: TextBuffer) {
        buffer.write(Self.orderLabel, limit: buffer.remainingCapacity)
        guard let order else {
            buffer.write(Self.noOrder, limit: buffer.remainingCapacity)
            return
        }
        buffer.write(Self.phaseText(order.phase), limit: buffer.remainingCapacity)
        buffer.newline()
        writeVector(Self.destinationLabel, order.destination, into: buffer)
        buffer.newline()
        writeValue(Self.distanceLabel, order.distance, unit: Self.distanceUnit, into: buffer)
    }

    private func writeVector(_ label: StaticString, _ vector: Vector2, into buffer: TextBuffer) {
        buffer.write(label, limit: buffer.remainingCapacity)
        buffer.writeSignedHundredths(vector.x, width: Self.valueWidth, limit: buffer.remainingCapacity)
        buffer.write(Self.ySeparator, limit: buffer.remainingCapacity)
        buffer.writeSignedHundredths(vector.y, width: Self.valueWidth, limit: buffer.remainingCapacity)
    }

    private func writeValue(_ label: StaticString, _ value: Double, unit: StaticString, into buffer: TextBuffer) {
        buffer.write(label, limit: buffer.remainingCapacity)
        buffer.writeSignedHundredths(value, width: Self.valueWidth, limit: buffer.remainingCapacity)
        buffer.write(unit, limit: buffer.remainingCapacity)
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
