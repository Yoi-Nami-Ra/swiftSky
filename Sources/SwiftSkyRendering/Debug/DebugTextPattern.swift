#if SWIFTSKY_INSTRUMENTATION

/// The text that proves the text path works: Debug and instrumented Release builds only, and only when
/// the developer opts in at launch (FR-014, FR-015, FR-015a).
///
/// Compiled out of plain Release entirely, like 001's instrumentation, so Release cannot show it
/// whatever arguments it is launched with (FR-016, SC-006). The text capability itself — `TextBuffer`, the
/// atlas, the pipeline — is not behind this condition; only this pattern and the opt-in that picks
/// it are.
public final class DebugTextPattern {
    public enum Mode: Sendable {
        /// The four-line test string (FR-014).
        case testString
        /// Copies of the test string filling exactly the 1,024-character capacity (FR-015a).
        case fill
    }

    public let mode: Mode

    /// The frame rate on the fourth line: whole frames drawn in the past second, or `nil` until the
    /// first full second has been measured (FR-014).
    ///
    /// Measured here, in the rendering layer, from the frame loop's own per-frame timestamp — never from
    /// `SimulationState` (001 FR-012b), and never by reading the clock a second time (001 FR-033).
    public private(set) var framesPerSecond: UInt64?

    private var windowStart: Double?
    private var framesInWindow: UInt64 = 0
    private var lastTimestamp: Double?

    /// How long each FPS measurement runs before the value is updated.
    static let measurementWindow = 1.0

    /// A gap longer than this between frames means the loop was paused — the app was hidden, say. The
    /// measurement restarts, so the pause does not drag the next value down.
    static let pauseThreshold = 0.25

    /// Distance from the safe area's top-left corner, in points (FR-006b).
    static let insetPoints = 8.0

    /// Every printable ASCII character in code order, split so no line exceeds 33 characters — narrow
    /// enough for iPad Slide Over, the narrowest surface this landscape-only app gets (research.md R13).
    static let line1: StaticString = " !\"#$%&'()*+,-./0123456789:;<=>?@"
    static let line2: StaticString = "ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`"
    static let line3: StaticString = "abcdefghijklmnopqrstuvwxyz{|}~"
    static let fpsLabel: StaticString = "fps "
    static let fpsUnknown: StaticString = "--"

    public init(mode: Mode) {
        self.mode = mode
    }

    /// Counts this frame, then writes the frame's text into `buffer`, 8 points in from the safe area's
    /// top-left. Allocates nothing.
    ///
    /// The whole text is rewritten every frame even when the FPS value has not changed, so the per-frame
    /// write path SC-003 measures runs on every frame.
    ///
    /// Every write is capped at the buffer's remaining capacity, so this never overflows it — `.fill`
    /// stops at exactly 1,024 characters with `didOverflow` still false (FR-015a).
    ///
    /// - Parameter timestamp: the frame's timestamp in seconds, as read once per frame by the loop.
    public func write(into buffer: TextBuffer, surface: RenderSurface, timestamp: Double) {
        recordFrame(at: timestamp)

        buffer.begin(at: (
            x: surface.safeAreaInsets.left + Self.insetPoints,
            y: surface.safeAreaInsets.top + Self.insetPoints
        ))

        switch mode {
        case .testString:
            writeCopy(into: buffer)
        case .fill:
            writeCopy(into: buffer)
            while buffer.remainingCapacity > 0 {
                // A blank line between copies. Line feeds are free, so this cannot overflow either.
                buffer.newline()
                buffer.newline()
                writeCopy(into: buffer)
            }
        }
    }

    /// Advances the FPS measurement by one frame. Once a full window has elapsed, the value becomes the
    /// frames drawn in it divided by its length, rounded, and a new window starts.
    func recordFrame(at timestamp: Double) {
        if let lastTimestamp, timestamp - lastTimestamp > Self.pauseThreshold {
            windowStart = nil
        }
        lastTimestamp = timestamp

        guard let windowStart else {
            windowStart = timestamp
            framesInWindow = 0
            return
        }

        framesInWindow += 1
        let elapsed = timestamp - windowStart
        if elapsed >= Self.measurementWindow {
            framesPerSecond = UInt64((Double(framesInWindow) / elapsed).rounded())
            self.windowStart = timestamp
            framesInWindow = 0
        }
    }

    /// One copy of the four lines, each write limited to what still fits.
    private func writeCopy(into buffer: TextBuffer) {
        buffer.write(Self.line1, limit: buffer.remainingCapacity)
        buffer.newline()
        buffer.write(Self.line2, limit: buffer.remainingCapacity)
        buffer.newline()
        buffer.write(Self.line3, limit: buffer.remainingCapacity)
        buffer.newline()
        buffer.write(Self.fpsLabel, limit: buffer.remainingCapacity)
        if let framesPerSecond {
            buffer.write(framesPerSecond, limit: buffer.remainingCapacity)
        } else {
            buffer.write(Self.fpsUnknown, limit: buffer.remainingCapacity)
        }
    }
}

#endif
