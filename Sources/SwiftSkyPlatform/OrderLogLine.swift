import SwiftSkySimulation

/// What one applied move order request's log line reports (008 FR-015, 010 FR-014), taken when the order
/// is applied and written after the frame's counted stretch has closed: writing a log line allocates, and
/// inside the stretch it was counted against the frame (011 FR-006).
///
/// Scalars only, so the frame loop can hold a few of these without copying the 4 KB planned path, and
/// holding one allocates nothing. Compiled in every build, like the other measurement structs, so it is
/// tested headlessly; only the frame loop holds them, and only in instrumented builds.
struct OrderLogLine: Equatable {
    /// What applying the request did.
    let outcome: MoveOrderOutcome

    /// Where the request was given, in view points.
    let viewPoint: Vector2

    /// The planned path's last point: the predicted end, or `nil` for an empty path.
    let predictedEnd: Vector2?

    /// The planned path's end tick.
    let predictedTicks: UInt64

    /// The planned path's number of points.
    let points: Int

    /// Whether the prediction arrives.
    let arrives: Bool

    /// The line for `outcome`, given at `viewPoint`, with the state's planned path after it was applied.
    /// The path fields describe the new order only when `outcome` is `.ordered`; the dropped lines do not
    /// print them.
    init(_ outcome: MoveOrderOutcome, viewPoint: Vector2, path: PlannedPath) {
        self.outcome = outcome
        self.viewPoint = viewPoint
        predictedEnd = path.last
        predictedTicks = path.endTick
        points = path.count
        arrives = path.reachesArrival
    }
}
