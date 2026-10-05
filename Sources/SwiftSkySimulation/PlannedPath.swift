/// The path the ship is predicted to fly for its current order (010 FR-001): up to 256 world positions in
/// flight order, the tick each belongs to, and whether the flight arrives. The order overlay (SKY-30)
/// draws it; nothing reads it before then.
///
/// Every point but the last is the position at `startTick + i × spacing`; the last is the position at
/// `endTick`, the predicted arrival or the cap (FR-004). So a reader can tell which part of the path the
/// ship has already flown from the state's tick count alone.
///
/// The points live in an inline array, not a heap buffer: building a path allocates nothing, and copying
/// the state copies the bytes, so the frame loop's state and the renderer's copy never share a buffer
/// that a later order would have to copy on write (FR-011, research R2). That makes the path about 4 KB,
/// carried by every copy of `SimulationState`.
///
/// ## Thinning
///
/// A flight is recorded one position per tick (`append(_:)`). While the flight fits — at most 256
/// positions, so at most 255 ticks — every tick is kept. After that, each time the buffer is full and the
/// flight goes on, every other point is dropped and `spacing` doubles, so a long flight still holds at
/// least 128 evenly spaced points. The flight's final position is always the last point (FR-005,
/// research R5).
public struct PlannedPath: Sendable, Equatable {
    /// The fixed storage. Its size is the only place the capacity is written (FR-005).
    typealias Points = InlineArray<256, Vector2>

    /// The most points a path holds.
    public static let capacity = Points.count

    /// The longest flight that is predicted: 60 simulated seconds, derived from the tick rate so it stays
    /// 60 seconds if the rate changes (FR-006, research R6).
    public static let maxFlightTicks = 60 * FixedTimestep.tickRate

    /// No order, no path (FR-001).
    public static let empty = PlannedPath()

    /// Slots `0..<count` are the path. While a flight is being recorded, slot `count` may also hold the
    /// latest position, staged until it is either due as a point or kept by `finish(reachesArrival:)`.
    private var points: Points

    /// How many points the path holds: 0 when empty, otherwise 1…`capacity`.
    public private(set) var count: Int

    /// The tick count at which the order was given: the tick of point 0.
    public private(set) var startTick: UInt64

    /// Ticks between consecutive points: 1 while every tick fits, then 2, 4, 8 or 16 (at the cap).
    public private(set) var spacing: Int

    /// The tick count of the last point: the predicted arrival, or the cap. While a flight is being
    /// recorded, the tick of the latest position appended.
    public private(set) var endTick: UInt64

    /// Whether the prediction stopped on an arrived state; `false` at the cap and when empty.
    public private(set) var reachesArrival: Bool

    private init() {
        points = Points(repeating: .zero)
        count = 0
        startTick = 0
        spacing = 1
        endTick = 0
        reachesArrival = false
    }

    /// Whether there is no path, which is exactly when there is no order.
    public var isEmpty: Bool { count == 0 }

    /// Point `index`, in flight order.
    public subscript(index: Int) -> Vector2 {
        precondition(index >= 0 && index < count, "point \(index) is outside the path's \(count) points")
        return points[index]
    }

    /// The tick of point `index`: `startTick + index × spacing`, except the last point, which is at
    /// `endTick` — a flight can end between two due points, and `finish` keeps its final position anyway
    /// (014 contract C1). Strictly increasing along the path.
    public func tick(ofPoint index: Int) -> UInt64 {
        precondition(index >= 0 && index < count, "point \(index) is outside the path's \(count) points")
        return index == count - 1 ? endTick : startTick + UInt64(index * spacing)
    }

    /// The final predicted position, or `nil` when the path is empty.
    public var last: Vector2? {
        count > 0 ? points[count - 1] : nil
    }

    /// Two paths are equal when their points `0..<count` and their ticks and arrival flag are. Slots past
    /// `count` are leftovers of thinning and are ignored (research R7).
    public static func == (lhs: PlannedPath, rhs: PlannedPath) -> Bool {
        guard lhs.count == rhs.count, lhs.startTick == rhs.startTick, lhs.spacing == rhs.spacing,
              lhs.endTick == rhs.endTick, lhs.reachesArrival == rhs.reachesArrival
        else { return false }
        for index in 0..<lhs.count where lhs.points[index] != rhs.points[index] {
            return false
        }
        return true
    }

    // MARK: - Predicting

    /// The path of the order `autopilot` holds, flown from `ship` at `tickCount`, or `.empty` without an
    /// order (010 FR-002).
    ///
    /// Flies copies of the ship and autopilot with `Simulation.tick`, the same function the real
    /// `advance(_:ticks:)` uses, so the copy flies exactly the real flight (006 FR-014, research R3). It
    /// stops on the first state that *reports* arrived and ends on that state's position. The phase is
    /// evaluated at the start of a tick, so that state's ship is one step past the classified position;
    /// stopping there is what makes the end point and tick the ones a test reads from the real state,
    /// and the ones the frame loop logs on its arrival line, which tests the same predicate (FR-003,
    /// research R4). An order that is already arrived when given is a single point.
    ///
    /// Touches only its copies (FR-009). At most `maxFlightTicks` ticks of the autopilot law and no
    /// allocation, whatever the order (FR-006, FR-011).
    init(predictingFrom ship: Ship, autopilot: Autopilot, tickCount: UInt64) {
        guard autopilot.order != nil else {
            self = .empty
            return
        }
        self.init(start: ship.position, tick: tickCount)
        guard autopilot.phase != .arrived else {
            finish(reachesArrival: true)
            return
        }
        var ship = ship
        var autopilot = autopilot
        for _ in 0..<Self.maxFlightTicks {
            Simulation.tick(&ship, &autopilot)
            append(ship.position)
            if autopilot.phase == .arrived {
                finish(reachesArrival: true)
                return
            }
        }
        finish(reachesArrival: false)
    }

    // MARK: - Recording a flight

    /// A path holding `start` at `tick`, ready to record the flight that follows.
    init(start: Vector2, tick: UInt64) {
        self.init()
        points[0] = start
        count = 1
        startTick = tick
        endTick = tick
    }

    /// Records the position after one more tick of the flight.
    ///
    /// A full buffer is thinned as soon as the flight goes on, before the new position is staged: every
    /// other point is kept and `spacing` doubles. The position is then staged in the next free slot, and
    /// becomes a point at once if its tick is a multiple of `spacing`. Constant work except for the
    /// thinning itself, which happens at most four times in a capped flight.
    mutating func append(_ position: Vector2) {
        endTick += 1
        if count == Self.capacity {
            thin()
        }
        points[count] = position
        if Int(endTick - startTick) % spacing == 0 {
            count += 1
        }
    }

    /// Ends the flight on the position appended last, keeping it as the final point if it was not
    /// already due as one, so the last point is always the final position (FR-005).
    mutating func finish(reachesArrival: Bool) {
        self.reachesArrival = reachesArrival
        if Int(endTick - startTick) % spacing != 0 {
            count += 1
        }
    }

    /// Keeps points 0, 2, 4, … of a full buffer, which halves `count` and doubles `spacing`. Point `i`
    /// stays at tick `startTick + i × spacing`.
    private mutating func thin() {
        let half = Self.capacity / 2
        for index in 0..<half {
            points[index] = points[2 * index]
        }
        count = half
        spacing *= 2
    }
}
