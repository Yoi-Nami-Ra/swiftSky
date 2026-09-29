import Metal

/// The full-screen quad's geometry and pipeline state, built once and reused for the life of the
/// renderer (FR-002b).
///
/// Vertices are in clip space, so this owns nothing that a surface resize invalidates: a resize
/// changes the viewport, not the geometry. That removes an entire class of resize bug rather than
/// leaving it to be handled correctly every time (research.md R11).
struct FullscreenQuad {
    /// Must match `swiftsky::Vertex` in `Shaders.metal`.
    struct Vertex {
        var x: Float
        var y: Float
    }

    /// Triangle-strip order: bottom-left, bottom-right, top-left, top-right.
    private static let vertices: [Vertex] = [
        Vertex(x: -1, y: -1),
        Vertex(x: 1, y: -1),
        Vertex(x: -1, y: 1),
        Vertex(x: 1, y: 1),
    ]

    static let vertexCount = vertices.count

    let vertexBuffer: any MTLBuffer
    let pipelineState: any MTLRenderPipelineState

    /// Compiles nothing and allocates nothing after this returns — every failure mode is here.
    init(device: any MTLDevice, library: any MTLLibrary, pixelFormat: MTLPixelFormat) throws {
        let vertexName = "swiftsky_quad_vertex"
        let fragmentName = "swiftsky_quad_fragment"

        guard let vertexFunction = library.makeFunction(name: vertexName) else {
            throw RendererError.shaderFunctionMissing(name: vertexName)
        }
        guard let fragmentFunction = library.makeFunction(name: fragmentName) else {
            throw RendererError.shaderFunctionMissing(name: fragmentName)
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "swiftSky.fullscreenQuad"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw RendererError.pipelineStateCreationFailed(underlying: error.localizedDescription)
        }

        let byteCount = Self.vertices.count * MemoryLayout<Vertex>.stride
        guard
            let buffer = Self.vertices.withUnsafeBytes({ bytes in
                device.makeBuffer(bytes: bytes.baseAddress!, length: byteCount, options: .storageModeShared)
            })
        else {
            throw RendererError.geometryBufferCreationFailed
        }
        buffer.label = "swiftSky.quadVertices"
        vertexBuffer = buffer
    }
}
