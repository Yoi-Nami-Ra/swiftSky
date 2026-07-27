import Metal
import QuartzCore
import SwiftSkySimulation

/// Draws the visible surface. Owns Metal, the shaders, and the black colour.
///
/// Knows nothing about windows, views, scenes, or app lifecycle — only a `CAMetalLayer` to present
/// into and a `RenderSurface` describing its size (FR-010, FR-014). That is what lets the same code
/// serve a resizable Mac window and a full-screen iOS surface with no branching.
///
/// Every failure mode lives in `init`. Once a `Renderer` exists it is a working renderer, so the
/// per-frame path has no initialisation errors to handle — only the transient drawable-unavailable
/// case, which is not an error (FR-027a).
public final class Renderer {
    private let device: any MTLDevice
    private let commandQueue: any MTLCommandQueue
    private let quad: FullscreenQuad

    /// Reused every frame so the draw path does not build one (FR-020).
    private let passDescriptor: MTLRenderPassDescriptor

    /// The most recent tick count handed across the layer boundary.
    ///
    /// Read every frame purely to prove the hand-off carries live state (FR-012a, SC-020). It must
    /// never influence what is drawn — FR-012b — which is why nothing below consults it.
    public private(set) var lastObservedTickCount: UInt64 = 0

    /// Compiles shaders, creates the pipeline state, and allocates the quad geometry — all exactly
    /// once (FR-002b).
    ///
    /// - Throws: `RendererError` for every failure, each carrying a human-readable description for the
    ///   FR-024 notice and a stable code for the FR-026 diagnostic.
    public init(device: any MTLDevice, pixelFormat: MTLPixelFormat) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.noGraphicsDevice
        }
        queue.label = "swiftSky.commandQueue"
        self.commandQueue = queue

        // SwiftPM compiles Shaders.metal into default.metallib inside this target's resource bundle.
        guard let library = try? device.makeDefaultLibrary(bundle: Bundle.module) else {
            throw RendererError.shaderLibraryUnavailable
        }

        self.quad = try FullscreenQuad(device: device, library: library, pixelFormat: pixelFormat)

        let descriptor = MTLRenderPassDescriptor()
        // Black clear colour as belt-and-braces only. The quad covers every pixel, so this is never
        // what the user sees — FR-002a requires the draw call, and FR-027 forbids a non-pipeline
        // surface from standing in for one.
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        self.passDescriptor = descriptor
    }

    /// Draws and presents one frame into an already-acquired drawable.
    ///
    /// The drawable is supplied by the caller rather than acquired here. `CAMetalDisplayLink` hands one
    /// to its delegate with each update and owns acquisition itself, so calling `nextDrawable()` here
    /// would conflict with it. FR-027a's skip-on-unavailable behaviour is therefore satisfied partly by
    /// the display link — it simply does not deliver an update when no drawable is ready — and partly
    /// by the `false` returns below.
    ///
    /// - Returns: `false` when the frame was skipped: a zero-area surface, or command buffer/encoder
    ///   creation failing. Both are transient and neither is an error (FR-027a, FR-027b). Never blocks.
    ///
    /// On allocation (FR-020, SC-004): this method allocates nothing itself — no arrays, no strings,
    /// no closures, and the pass descriptor and geometry are reused. Metal's own
    /// `makeCommandBuffer`/`makeRenderCommandEncoder` do allocate internally, which is inherent to the
    /// API and cannot be avoided while still submitting work. See the note on SC-004 in quickstart.md.
    @discardableResult
    public func render(
        state: SimulationState,
        surface: RenderSurface,
        drawable: any CAMetalDrawable
    ) -> Bool {
        // Prove the hand-off is live (FR-012a) without letting it affect output (FR-012b).
        lastObservedTickCount = state.tickCount

        guard surface.isRenderable else { return false }

        passDescriptor.colorAttachments[0].texture = drawable.texture

        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            // Detach the texture so a failed frame cannot leave the descriptor holding a drawable.
            passDescriptor.colorAttachments[0].texture = nil
            return false
        }

        encoder.setRenderPipelineState(quad.pipelineState)
        encoder.setVertexBuffer(quad.vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: FullscreenQuad.vertexCount)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        passDescriptor.colorAttachments[0].texture = nil
        return true
    }
}
