import CoreText
import Dispatch
import Metal

/// The GPU side of text: the atlas texture, the text pipeline, and a ring of per-frame instance
/// buffers. Draws a `TextBuffer` with one instanced draw on top of whatever the frame already holds.
///
/// ## Why a ring of three buffers
///
/// The CPU rewrites the text every frame while the GPU may still be reading the previous frames'
/// instances. One buffer would race. Three buffers, handed out round-robin and guarded by a semaphore
/// that each frame's command buffer signals on completion, make "never overwrite what the GPU is
/// reading" the renderer's own invariant rather than a side effect of the layer's drawable count
/// (research.md R5).
///
/// The semaphore is only ever taken with a zero timeout. If no buffer is free the frame is skipped,
/// exactly like a missing drawable (001 FR-027a) — the loop never blocks. With the layer's three
/// drawables a free drawable already implies a free buffer, so this does not happen in practice; if it
/// ever does, it shows up in the skipped-frame count rather than hiding.
final class TextRenderer {
    /// Mirrors `swiftsky::TextUniforms` in `Shaders.metal`.
    struct Uniforms {
        var viewportPixels: SIMD2<Float>
        var cellPixels: SIMD2<Float>
        var atlasColumns: UInt32
        var padding: UInt32 = 0
    }

    static let ringSize = 3

    private let device: any MTLDevice
    private let font: CTFont
    private let pipelineState: any MTLRenderPipelineState
    private let instanceBuffers: [any MTLBuffer]
    private let inFlight: DispatchSemaphore
    private var nextSlot = 0

    /// Signals `inFlight` when a frame's command buffer completes. Created once and reused, so adding
    /// it to each frame's command buffer creates no closure per frame (research.md R5 — confirmed or
    /// refuted by quickstart check 15).
    private let releaseSlot: MTLCommandBufferHandler

    private var atlas: (any MTLTexture)?
    private(set) var metrics: TextMetrics?

    /// Builds everything that does not depend on the backing scale. The atlas waits for the first
    /// frame, where the scale is known (research.md R8).
    init(device: any MTLDevice, library: any MTLLibrary, pixelFormat: MTLPixelFormat, font: CTFont)
        throws(TextRenderingError)
    {
        self.device = device
        self.font = font

        guard
            let vertexFunction = library.makeFunction(name: "swiftsky_text_vertex"),
            let fragmentFunction = library.makeFunction(name: "swiftsky_text_fragment")
        else {
            throw .pipelineUnavailable(underlying: "text shader functions missing from the library")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "swiftSky.text"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        // Premultiplied white over whatever is below (research.md R4).
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .pipelineUnavailable(underlying: error.localizedDescription)
        }

        let length = TextBuffer.capacity * MemoryLayout<GlyphInstance>.stride
        var buffers: [any MTLBuffer] = []
        for index in 0..<Self.ringSize {
            guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
                throw .bufferUnavailable
            }
            buffer.label = "swiftSky.textInstances.\(index)"
            buffers.append(buffer)
        }
        instanceBuffers = buffers

        let semaphore = DispatchSemaphore(value: Self.ringSize)
        inFlight = semaphore
        releaseSlot = { _ in semaphore.signal() }
    }

    /// Rasterises the glyphs at `scale` and uploads them, replacing any previous atlas. Called on the
    /// first frame and on each backing-scale change — never on an ordinary frame (FR-004, FR-010).
    ///
    /// Allocates: this is the one-off event FR-010 permits. Frames still in flight keep the old texture
    /// alive through their command buffers.
    func prepareAtlas(scale: Double) throws(TextRenderingError) -> TextMetrics {
        let bitmap = try GlyphAtlasBitmap.make(font: font, scale: scale)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: bitmap.widthPixels,
            height: bitmap.heightPixels,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        // Default storage mode: managed on macOS, shared on iOS. `replace(region:)` works with both, so
        // no platform branch (research.md R2).
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw .atlasTextureUnavailable
        }
        texture.label = "swiftSky.textAtlas"
        bitmap.bytes.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, bitmap.widthPixels, bitmap.heightPixels),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: bitmap.widthPixels
            )
        }

        atlas = texture
        metrics = bitmap.metrics
        return bitmap.metrics
    }

    /// Takes an instance buffer for this frame, or `nil` if all three are still in use. Never blocks.
    ///
    /// Call only when there is text to draw: a frame with no text takes no slot, so text-free frames —
    /// every Release frame among them — never touch the semaphore.
    func acquireSlot() -> Int? {
        guard inFlight.wait(timeout: .now()) == .success else { return nil }
        let slot = nextSlot
        nextSlot = (nextSlot + 1) % Self.ringSize
        return slot
    }

    /// Returns a slot that was acquired but never submitted — the frame failed before its command buffer
    /// could be committed. Without this the slot would be lost for good.
    func releaseUnusedSlot() {
        inFlight.signal()
    }

    /// Copies `buffer`'s instances into `slot` and draws them. Allocates nothing.
    ///
    /// The command buffer is given the slot's release handler here, so the caller must commit it.
    func encode(
        _ buffer: TextBuffer,
        slot: Int,
        surface: RenderSurface,
        encoder: any MTLRenderCommandEncoder,
        commandBuffer: any MTLCommandBuffer
    ) {
        commandBuffer.addCompletedHandler(releaseSlot)

        guard let atlas, let metrics, let source = buffer.instances.baseAddress else { return }
        let instanceBuffer = instanceBuffers[slot]
        instanceBuffer.contents().copyMemory(
            from: source,
            byteCount: buffer.count * MemoryLayout<GlyphInstance>.stride
        )

        var uniforms = Uniforms(
            viewportPixels: SIMD2(Float(surface.widthPixels), Float(surface.heightPixels)),
            cellPixels: SIMD2(Float(metrics.cellWidthPixels), Float(metrics.cellHeightPixels)),
            atlasColumns: UInt32(GlyphAtlasBitmap.columns)
        )

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(instanceBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.setFragmentTexture(atlas, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: buffer.count)
    }
}
