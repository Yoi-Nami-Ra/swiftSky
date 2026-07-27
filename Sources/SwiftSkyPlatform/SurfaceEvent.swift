import SwiftSkyRendering

/// Something the frame loop must react to, originating on the main thread.
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

    /// Content became visible or stopped being visible — backgrounded, minimised, occluded, or the
    /// scene disconnected. Drives loop start/stop (FR-008, FR-021).
    case visibilityChanged(isVisible: Bool)

    /// The app is about to terminate. The only case the main thread waits on, and it waits for the
    /// loop to drain rather than for a frame to be presented (FR-032).
    case willTerminate
}
