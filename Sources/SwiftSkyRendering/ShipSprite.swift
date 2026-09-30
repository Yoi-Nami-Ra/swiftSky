import Metal

/// The ship's pipeline state and texture, built once and reused for the life of the renderer
/// (007 FR-003, FR-011, research R4).
///
/// Nothing here depends on the surface: the per-frame input is the four clip-space corners from
/// `ShipSpritePlacement`, passed inline with `setVertexBytes`. There is no vertex buffer to create,
/// refill or share with the GPU (research R5).
struct ShipSprite {
    /// Four corners, drawn as a triangle strip.
    static let vertexCount = 4

    let pipelineState: any MTLRenderPipelineState

    /// 80 × 80 `rgba8Unorm_srgb` with its full mip chain (80, 40, 20, 10, 5, 2, 1).
    let texture: any MTLTexture

    /// Every failure mode is here. Afterwards drawing the ship allocates nothing.
    ///
    /// Uses one command buffer to generate the mip chain on the GPU, and waits for it. This is
    /// initialisation-time only, before the frame loop starts.
    init(
        device: any MTLDevice,
        library: any MTLLibrary,
        pixelFormat: MTLPixelFormat,
        commandQueue: any MTLCommandQueue,
        image: ShipImageBitmap
    ) throws(RendererError) {
        let vertexName = "swiftsky_sprite_vertex"
        let fragmentName = "swiftsky_sprite_fragment"

        guard let vertexFunction = library.makeFunction(name: vertexName) else {
            throw .shaderFunctionMissing(name: vertexName)
        }
        guard let fragmentFunction = library.makeFunction(name: fragmentName) else {
            throw .shaderFunctionMissing(name: fragmentName)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "swiftSky.shipSprite"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        // Premultiplied "over" (research R3).
        attachment.isBlendingEnabled = true
        attachment.sourceRGBBlendFactor = .one
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw .pipelineStateCreationFailed(underlying: error.localizedDescription)
        }

        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: image.widthPixels,
            height: image.heightPixels,
            mipmapped: true
        )
        textureDescriptor.usage = .shaderRead
        // Default storage mode: managed on macOS, shared on iOS. `replace(region:)` works with both, as
        // for the glyph atlas.
        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw .shipImageUnavailable(reason: "its texture could not be created")
        }
        texture.label = "swiftSky.shipImage"
        image.bytes.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, image.widthPixels, image.heightPixels),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: image.widthPixels * 4
            )
        }

        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            throw .shipImageUnavailable(reason: "its mipmaps could not be generated")
        }
        commandBuffer.label = "swiftSky.shipMipmaps"
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw .shipImageUnavailable(reason: "its mipmaps could not be generated")
        }

        self.texture = texture
    }
}
