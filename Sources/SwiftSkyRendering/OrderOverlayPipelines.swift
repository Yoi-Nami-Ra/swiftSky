import Metal

/// The order overlay's two pipeline states, built once and reused for the life of the renderer
/// (014 FR-013, research R4).
///
/// Nothing here depends on the surface or the order: the per-frame input is an `OrderOverlay`, passed
/// inline with `setVertexBytes`. There is no vertex buffer to create, refill or share with the GPU
/// (research R6).
struct OrderOverlayPipelines {
    /// Each segment and each ring is one quad, drawn as a triangle strip.
    static let vertexCount = 4

    /// One instance per segment of the line.
    let line: any MTLRenderPipelineState

    /// One instance per ring: the marker and the highlight.
    let ring: any MTLRenderPipelineState

    /// Every failure mode is here. Afterwards drawing the overlay allocates nothing.
    init(device: any MTLDevice, library: any MTLLibrary, pixelFormat: MTLPixelFormat) throws(RendererError) {
        let fragment = try Self.function("swiftsky_overlay_fragment", in: library)
        line = try Self.pipeline(
            "swiftSky.orderOverlay.line",
            vertex: Self.function("swiftsky_overlay_line_vertex", in: library),
            fragment: fragment, device: device, pixelFormat: pixelFormat
        )
        ring = try Self.pipeline(
            "swiftSky.orderOverlay.ring",
            vertex: Self.function("swiftsky_overlay_ring_vertex", in: library),
            fragment: fragment, device: device, pixelFormat: pixelFormat
        )
    }

    private static func function(_ name: String, in library: any MTLLibrary) throws(RendererError) -> any MTLFunction {
        guard let function = library.makeFunction(name: name) else {
            throw .shaderFunctionMissing(name: name)
        }
        return function
    }

    private static func pipeline(
        _ label: String,
        vertex: any MTLFunction,
        fragment: any MTLFunction,
        device: any MTLDevice,
        pixelFormat: MTLPixelFormat
    ) throws(RendererError) -> any MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        // `max`, not "over": overlapping capsules must not brighten their overlaps. Correct over the
        // black background, which is all the overlay is drawn on (research R5).
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .max
        attachment.alphaBlendOperation = .max
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .one
        attachment.destinationAlphaBlendFactor = .one
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .pipelineStateCreationFailed(underlying: error.localizedDescription)
        }
    }
}

/// Mirrors `swiftsky::OverlayUniforms` in Shaders.metal — 32 bytes.
struct OrderOverlayUniforms {
    var surfacePixels: SIMD2<Float>
    var lineHalfWidth: Float
    var unused: Float = 0
    var colour: SIMD4<Float>
}

/// Mirrors `swiftsky::OverlayRing` in Shaders.metal — 16 bytes.
struct OrderOverlayRing {
    var centre: SIMD2<Float>
    var radius: Float
    var halfWidth: Float
}
