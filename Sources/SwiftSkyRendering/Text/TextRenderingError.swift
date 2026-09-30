/// Why text could not be set up or rebuilt.
///
/// Deliberately separate from `RendererError`, and none of these may ever be mapped to one. Text is not
/// essential: a text failure is logged and the app keeps rendering without it, whereas a
/// `RendererError` puts up the renderer-failure notice (002 FR-018, research.md R12). Keeping the types
/// apart makes that mistake a type error rather than a code-review catch.
public enum TextRenderingError: Error, Sendable, Equatable {
    /// Core Graphics would not create the bitmap the glyphs are drawn into.
    case bitmapContextUnavailable

    /// The GPU texture for the glyph atlas could not be created.
    case atlasTextureUnavailable

    /// The text shader functions are missing, or the pipeline state failed to build.
    case pipelineUnavailable(underlying: String)

    /// One of the per-frame instance buffers could not be created.
    case bufferUnavailable
}
