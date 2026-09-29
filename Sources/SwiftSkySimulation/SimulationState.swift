/// What the renderer should currently draw — the single typed hand-off across the layer boundary
/// (FR-012, FR-012a).
///
/// In this feature it holds only a tick count. That is deliberate: it is the minimum that makes the
/// hand-off real rather than an unused type, while remaining something the logic layer legitimately
/// owns. It carries no presentation concept — the quad's colour belongs to the rendering layer, not
/// here (FR-012b), and the tick count must never affect what is visible.
///
/// A value type, so handing it to the renderer is a copy. That is also what makes it safe to move
/// between isolation domains without any concurrency annotation (FR-012c, FR-012d, FR-030).
public struct SimulationState: Sendable, Equatable {
    /// Total fixed-timestep ticks advanced since launch. Monotonically non-decreasing (SC-020).
    public var tickCount: UInt64

    /// The state at launch, before any tick has been advanced.
    public init() {
        self.tickCount = 0
    }

    /// Creates a state with an explicit tick count. Useful for tests that start mid-run.
    public init(tickCount: UInt64) {
        self.tickCount = tickCount
    }
}
