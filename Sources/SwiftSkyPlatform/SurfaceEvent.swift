import SwiftSkyRendering

/// Something the frame loop must react to, originating on the main thread: a change to the surface,
/// or the player's input (008).
///
/// Surface changes and input travel through this one channel, so the loop applies them in the order
/// they happened — a tap posted after a resize is read against the new size (008 FR-005, research R1).
///
/// The main thread never touches the loop's state directly. It posts one of these and returns
/// immediately, so UI responsiveness is never coupled to the frame budget (FR-029). The loop applies
/// them at a frame boundary and nowhere else, which is what makes FR-031's "never mid-draw" guarantee
/// hold rather than being a hope.
///
/// Every payload is a value type, so the transfer across isolation domains is safe by construction
/// rather than by annotation (FR-030, FR-012d).
public enum SurfaceEvent: Sendable, Equatable {
    /// The drawable's dimensions changed — a window resize, an orientation change, or an iPad
    /// multitasking size change.
    case resized(RenderSurface)

    /// The backing scale changed, typically because the surface moved to a display of different
    /// pixel density. The drawable dimensions must be updated to stay sharp.
    case backingScaleChanged(RenderSurface)

    /// The maximum frame rate of the screen the surface is on, posted before the geometry event of the
    /// same change whenever it differs from the last one posted; 0 when unknown (016).
    ///
    /// The frame budget never goes below this display's fastest interval, so gaps the display cannot
    /// produce — a live resize's half intervals, a faster display's gaps after a move — are not learned
    /// (016 FR-005, research R3).
    case displayRateChanged(maximumFramesPerSecond: Int)

    /// Content became visible or stopped being visible — backgrounded, minimised, occluded, or the
    /// scene disconnected. Drives loop start/stop (FR-008, FR-021).
    case visibilityChanged(isVisible: Bool)

    /// The player asked for the ship to fly to a point on the surface: a tap on iOS (008), a click on
    /// macOS (SKY-11).
    ///
    /// Carried as a view position and converted in the loop, against the surface as it stands after
    /// every earlier event in the queue, so it is never read against stale geometry (008 FR-004 to
    /// FR-006, research R2).
    case moveOrderRequested(MoveOrderRequest)

    /// The app is about to terminate. The only case the main thread waits on, and it waits for the
    /// loop to drain rather than for a frame to be presented (FR-032).
    case willTerminate
}
