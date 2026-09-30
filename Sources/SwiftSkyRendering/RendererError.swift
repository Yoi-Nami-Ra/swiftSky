/// Why the rendering pipeline could not be initialised.
///
/// Every one of these is a *construction* failure. Once a `Renderer` exists it is a working renderer,
/// so the per-frame path has no initialisation failure modes to handle — only the transient
/// drawable-unavailable case, which is not an error at all (FR-027a).
///
/// These are surfaced to the user through the text-only notice required by FR-024, and to the log
/// through the diagnostic required by FR-026.
public enum RendererError: Error, Equatable, Sendable {
    /// No Metal device could be obtained. Expected to be unreachable on the supported OS floor, since
    /// every iOS 26 / macOS 26 device has one (FR-022) — it exists so the reachable variants below
    /// surface through the same path.
    case noGraphicsDevice

    /// The compiled shader library could not be loaded from the bundle.
    case shaderLibraryUnavailable

    /// The shader library loaded, but a required function was absent from it.
    case shaderFunctionMissing(name: String)

    /// The render pipeline state could not be created from the compiled functions.
    case pipelineStateCreationFailed(underlying: String)

    /// The full-screen quad's vertex buffer could not be allocated.
    case geometryBufferCreationFailed

    /// The ship image could not be used: it is missing from the app, is not a readable image, is not
    /// 80 × 80 pixels, or could not be put into graphics memory with its mip chain (007 FR-005, research
    /// R7). One case and one diagnostic code for all of them; `reason` says which step failed.
    case shipImageUnavailable(reason: String)

    /// Human-readable explanation for the FR-024 notice.
    ///
    /// Written for a person who is not looking at a debugger: it says what failed and, where useful,
    /// what that implies. English-only in this feature — localisation is explicitly out of scope, and
    /// this is the only user-facing string that exists.
    public var userFacingDescription: String {
        switch self {
        case .noGraphicsDevice:
            return "swiftSky could not find a graphics device on this system, so it cannot draw."
        case .shaderLibraryUnavailable:
            return "swiftSky could not load its compiled graphics shaders. The installation may be incomplete."
        case .shaderFunctionMissing(let name):
            return "swiftSky's shader library is missing the function “\(name)”. The installation may be incomplete."
        case .pipelineStateCreationFailed(let underlying):
            return "swiftSky could not set up its graphics pipeline: \(underlying)"
        case .geometryBufferCreationFailed:
            return "swiftSky could not allocate the graphics memory it needs to draw."
        case .shipImageUnavailable(let reason):
            return "swiftSky could not load the ship image (\(reason)). The installation may be incomplete."
        }
    }

    /// Terse, stable identifier for the FR-026 log diagnostic, so failures can be grepped and
    /// compared without depending on user-facing wording.
    public var diagnosticCode: String {
        switch self {
        case .noGraphicsDevice: return "no_graphics_device"
        case .shaderLibraryUnavailable: return "shader_library_unavailable"
        case .shaderFunctionMissing: return "shader_function_missing"
        case .pipelineStateCreationFailed: return "pipeline_state_creation_failed"
        case .geometryBufferCreationFailed: return "geometry_buffer_creation_failed"
        case .shipImageUnavailable: return "ship_image_unavailable"
        }
    }
}
