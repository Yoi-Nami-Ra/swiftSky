import Metal
import QuartzCore
import SwiftUI
import SwiftSkyRendering

/// The app's entire visible content: a Metal surface, or the failure notice if the renderer could not
/// be built (FR-024).
///
/// Construction order matters and is deliberate (contracts/frame-loop.md): the graphics device and
/// renderer are created on the main thread *before* the loop starts, so every initialisation failure
/// mode is resolved up front. A running loop therefore always has a working renderer, and the per-frame
/// path has no initialisation errors to handle.
///
/// There is no fallback to a plain black view when rendering is unavailable (FR-027) — a total rendering
/// failure must not be able to masquerade as a correct black screen. Note how easily it could: this
/// feature's correct output and its total-failure output are both "a black screen". SC-019's frame
/// capture is what distinguishes them, which is why that check exists.
public struct GameSurfaceView: View {
    @State private var setup: Result<Setup, RendererError>?
    @State private var host = LoopHost()

    public init() {}

    public var body: some View {
        content
            .onAppear {
                if setup == nil { setup = Self.buildSetup() }
            }
            .onDisappear {
                // Explicit teardown: stop and drain before graphics resources are released (FR-032).
                host.stopAndDrain()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch setup {
        case .success(let ready):
            MetalSurface(device: ready.device) { layer in
                // The loop is created HERE, with the layer that is actually on screen. Creating it
                // earlier against a placeholder layer would leave the display link driving an
                // offscreen surface — a bug indistinguishable from success, since both render black.
                host.start(renderer: ready.renderer, layer: layer)
                return { [host] event in host.post(event) }
            }
            // Fill the screen edge to edge, including under the safe-area insets, on iOS (FR-003).
            .ignoresSafeArea()

        case .failure(let error):
            RendererFailureNotice(error: error) {
                Self.quit()
            }

        case nil:
            // Pre-first-frame. Black, so the user never sees a non-black frame (FR-004, FR-004a).
            // This is launch appearance, not rendered content.
            Color.black.ignoresSafeArea()
        }
    }

    /// Device and renderer — everything that can fail, resolved before the loop exists.
    struct Setup {
        let device: any MTLDevice
        let renderer: Renderer
    }

    /// Owns the loop's lifetime across SwiftUI view-struct recreations.
    ///
    /// A `View` is a value recreated on every state change, so the loop cannot live in it directly.
    /// This reference type is held in `@State` and outlives those recreations, which is what makes the
    /// `onDisappear` drain reliable rather than racy.
    @Observable
    final class LoopHost {
        private var loop: FrameLoop?

        func start(renderer: Renderer, layer: CAMetalLayer) {
            guard loop == nil else { return }
            let created = FrameLoop(renderer: renderer, layer: layer)
            loop = created
            created.start()
        }

        func post(_ event: SurfaceEvent) {
            loop?.post(event)
        }

        func stopAndDrain() {
            loop?.stopAndDrain()
            loop = nil
        }
    }

    private static func buildSetup() -> Result<Setup, RendererError> {
        guard let device = MTLCreateSystemDefaultDevice() else {
            let error = RendererError.noGraphicsDevice
            RendererFailureReporter.report(error)
            return .failure(error)
        }

        do {
            let renderer = try Renderer(device: device, pixelFormat: .bgra8Unorm_srgb)
            return .success(Setup(device: device, renderer: renderer))
        } catch let error as RendererError {
            RendererFailureReporter.report(error)
            return .failure(error)
        } catch {
            let wrapped = RendererError.pipelineStateCreationFailed(underlying: error.localizedDescription)
            RendererFailureReporter.report(wrapped)
            return .failure(wrapped)
        }
    }

    private static func quit() {
        #if os(macOS)
        NSApplication.shared.terminate(nil)
        #else
        // iOS has no sanctioned programmatic quit. The notice is the terminal state; the user dismisses
        // the app themselves.
        exit(0)
        #endif
    }
}
