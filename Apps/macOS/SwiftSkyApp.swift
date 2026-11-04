import SwiftUI
import SwiftSkyPlatform

/// macOS entry point.
///
/// Everything here is scene declaration; no behaviour lives in this file (FR-014). The interesting
/// choice is `Window` rather than `WindowGroup`, and it is doing three jobs at once:
///
///   * exactly one window can exist (FR-006c)
///   * no New Window command, and no Window menu entry that opens or lists a window (FR-006c)
///   * closing the window terminates the app (FR-006d)
///
/// All three are `Window`'s documented behaviour, so none of them needs custom code. `WindowGroup` with
/// `.commandsRemoved()` would have suppressed the menu item but left the app running with no window and
/// no way to get one back — a dead end that would then have needed explicit termination logic
/// (research.md R7).
@main
struct SwiftSkyApp: App {
    var body: some Scene {
        Window("swiftSky", id: "main") {
            GameSurfaceView()
                // FR-006a: minimum 640×360, enforced through content minimums by
                // `.windowResizability(.contentMinSize)` below. Aspect ratio is deliberately NOT
                // locked — the surface must fill any legal size, and full screen imposes the display's
                // own aspect anyway.
                .frame(minWidth: 640, minHeight: 360)
                .background(.black)
        }
        // FR-006a: opens at 1280×720.
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentMinSize)
    }
}
