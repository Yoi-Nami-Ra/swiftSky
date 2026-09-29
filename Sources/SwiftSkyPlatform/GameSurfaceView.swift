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
    @State private var host = LoopHost()

    public init() {}

    public var body: some View {
        content
            .onDisappear {
                // Explicit teardown: stop and drain before graphics resources are released (FR-032).
                host.stopAndDrain()
            }
    }

    @ViewBuilder
    private var content: some View {
        // Resolved on first body evaluation, which SwiftUI runs on the main actor — so renderer
        // construction still happens on the main thread before the loop starts (contracts/frame-loop.md).
        //
        // There is deliberately no third "not built yet" branch. An earlier version had one and filled
        // it with `Color.black`, which is a platform-UI view painting a user-visible pixel — exactly
        // what FR-001/FR-007 forbid and what SC-002's audit looks for. The pre-first-frame appearance
        // is the OS's job instead (FR-004a): the iOS launch screen and the black macOS window
        // background set in `MetalSurfaceView`.
        switch host.setup {
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
    ///
    /// It also owns the one-time renderer construction, so that `body` has a resolved result to switch
    /// on from its very first evaluation and never needs a placeholder branch to draw.
    final class LoopHost {
        /// Built once, on first access from `body`. Discarded `LoopHost` instances from view-struct
        /// recreation never touch it, so laziness keeps them free.
        ///
        /// `@MainActor` on the property alone — not the whole class — is what keeps
        /// contracts/frame-loop.md's "renderer constructed on the main thread before the loop starts"
        /// a compiler-checked fact rather than a comment, while leaving `post(_:)` callable from the
        /// nonisolated surface-event closure.
        @MainActor
        lazy var setup: Result<Setup, RendererError> = GameSurfaceView.buildSetup()

        private var loop: FrameLoop?

        /// Explicit and `nonisolated` because the synthesised initialiser would otherwise inherit
        /// `setup`'s main-actor isolation, which `@State`'s nonisolated initial value cannot satisfy.
        /// Only the lazy *access* needs the main actor; allocating an empty host does not.
        nonisolated init() {}

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
