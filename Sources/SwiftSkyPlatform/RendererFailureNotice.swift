import SwiftUI
import SwiftSkyRendering
import os

/// The one piece of user-visible content the platform-UI layer is permitted to draw (FR-024).
///
/// Everything else the user sees comes from the render pipeline (FR-001, FR-007). This exists because
/// the pipeline cannot draw the message about its own failure to initialise, and because leaving the
/// user with a blank window and no explanation would be worse.
///
/// Text-only by requirement: no graphics, no branding, no recovery controls beyond dismissal. Respects
/// Dynamic Type and is readable by assistive technology, so the one path where the user must read
/// something is not the one path that is inaccessible (FR-025).
public struct RendererFailureNotice: View {
    private let error: RendererError
    private let onDismiss: () -> Void

    public init(error: RendererError, onDismiss: @escaping () -> Void) {
        self.error = error
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 16) {
            // The text scrolls, so at the largest Dynamic Type sizes in landscape (SKY-38) the whole
            // message can still be read; Quit sits outside the scroll view and stays reachable.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("swiftSky cannot start")
                        .font(.headline)

                    Text(error.userFacingDescription)
                        .font(.body)
                        // No line limit, so large Dynamic Type sizes wrap rather than truncate: a
                        // truncated error message is no message at all.
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Quit", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        #if os(macOS)
        // A window has no natural width; keep it wide enough to read. iOS fills the screen instead,
        // and a fixed minimum there is what clipped the text in landscape (SKY-38).
        .frame(minWidth: 320)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityLabel("swiftSky cannot start")
        .accessibilityValue(error.userFacingDescription)
    }
}

/// Emits the FR-026 diagnostic and traps in debug builds.
///
/// The diagnostic exists so the cause survives dismissal of the notice — a user who clicks Quit should
/// still leave a trace behind for whoever investigates. The debug trap exists so a developer meets the
/// failure at the point it happened rather than reading about it afterwards.
public enum RendererFailureReporter {
    private static let log = Logger(subsystem: "com.swiftsky.app", category: "renderer")

    public static func report(_ error: RendererError) {
        log.error(
            "renderer initialisation failed code=\(error.diagnosticCode, privacy: .public) detail=\(error.userFacingDescription, privacy: .public)"
        )
        #if DEBUG
        assertionFailure("Renderer initialisation failed: \(error.diagnosticCode) — \(error.userFacingDescription)")
        #endif
    }
}
