import SwiftUI
import SwiftSkyPlatform

/// iOS entry point.
///
/// The same `GameSurfaceView` the Mac uses, reached through a different platform entry point — which is
/// exactly what User Story 2 exists to validate about the shared/platform split (FR-005).
///
/// Single-scene by configuration rather than by code: `UIApplicationSupportsMultipleScenes` is `false`
/// in Info.plist, so iPadOS offers no multi-window option (FR-006c). Landscape-only is likewise a plist
/// declaration (FR-006b) — the surface still tolerates any size it is handed, because iPad multitasking
/// can present shapes that match no device orientation.
@main
struct SwiftSkyApp: App {
    var body: some Scene {
        WindowGroup {
            GameSurfaceView()
                .background(.black)
                // Edge to edge, including under the safe-area insets (FR-003).
                .ignoresSafeArea()
                // No status bar over a game surface.
                .statusBarHidden()
        }
    }
}
