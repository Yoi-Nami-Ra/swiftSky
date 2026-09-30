import CoreText
import Metal
import QuartzCore
import SwiftSkySimulation
import os

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

    /// The GPU side of text, or `nil` if it could not be set up. Text is not essential: a failure is
    /// logged and the renderer carries on without it — it never becomes a `RendererError` (FR-018).
    private let text: TextRenderer?

    /// The one text store for the whole run. Created on the first frame, once the backing scale is
    /// known, and kept; a scale change only replaces its metrics (research.md R8).
    private var textBuffer: TextBuffer?

    /// Set when building or rebuilding the atlas failed. Text stays off for the rest of the run rather
    /// than being retried every frame, and is never shown at the wrong density (FR-018).
    private var textDisabled = false

    /// FR-011 asks for the first overflow in a run to be logged — once, not every frame.
    private var hasReportedOverflow = false

    private static let textLog = Logger(subsystem: "com.swiftsky.app", category: "text")

    /// Whether text can be drawn: set-up succeeded and no atlas build has failed since.
    public var isTextAvailable: Bool { text != nil && !textDisabled }

    #if SWIFTSKY_INSTRUMENTATION
    /// The debug text to draw, chosen by the platform layer from the launch arguments. Set once, before
    /// the loop starts; `nil` — the default — draws no text, so the surface stays black (FR-015).
    public var debugTextPattern: DebugTextPattern?
    #endif

    /// Reused every frame so the draw path does not build one (FR-020).
    private let passDescriptor: MTLRenderPassDescriptor

    /// The most recent tick count handed across the layer boundary.
    ///
    /// Read every frame purely to prove the hand-off carries live state (FR-012a, SC-020). It must
    /// never influence what is drawn — FR-012b — which is why nothing below consults it.
    public private(set) var lastObservedTickCount: UInt64 = 0

    /// Compiles shaders, creates the pipeline states, and allocates the quad geometry and text buffers —
    /// all exactly once (FR-002b, 002 FR-004). The glyph atlas waits for the first frame, where the
    /// backing scale is known.
    ///
    /// - Parameter textFont: the 13-point system monospaced font. Resolved by the platform layer,
    ///   because the system's monospaced design is only reachable through AppKit/UIKit, which this
    ///   layer does not import (002 research.md R1).
    /// - Throws: `RendererError` for every failure of the quad path, each carrying a human-readable
    ///   description for the FR-024 notice and a stable code for the FR-026 diagnostic. Text failures
    ///   never throw (002 FR-018).
    public init(device: any MTLDevice, pixelFormat: MTLPixelFormat, textFont: CTFont) throws {
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

        do {
            self.text = try TextRenderer(device: device, library: library, pixelFormat: pixelFormat, font: textFont)
        } catch {
            Self.textLog.error("text disabled: \(String(describing: error), privacy: .public)")
            self.text = nil
        }

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
    ///
    /// - Parameter timestamp: the frame's timestamp, read once per frame by the loop (FR-033). Used only
    ///   to measure the debug text's FPS; nothing else here reads the clock (002 FR-014).
    @discardableResult
    public func render(
        state: SimulationState,
        surface: RenderSurface,
        drawable: any CAMetalDrawable,
        timestamp: Double
    ) -> Bool {
        // Prove the hand-off is live (FR-012a) without letting it affect output (FR-012b).
        lastObservedTickCount = state.tickCount

        guard surface.isRenderable else { return false }

        let textToDraw = prepareText(for: surface, timestamp: timestamp)

        // A slot is taken only when there is text, and before any GPU work, so running out of slots
        // skips the frame cleanly (002 research.md R5).
        var textSlot: Int?
        if let textToDraw, textToDraw.count > 0 {
            guard let slot = text?.acquireSlot() else { return false }
            textSlot = slot
        }

        passDescriptor.colorAttachments[0].texture = drawable.texture

        guard
            let commandBuffer = commandQueue.makeCommandBuffer(),
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor)
        else {
            // Detach the texture so a failed frame cannot leave the descriptor holding a drawable.
            passDescriptor.colorAttachments[0].texture = nil
            if textSlot != nil { text?.releaseUnusedSlot() }
            return false
        }

        encoder.setRenderPipelineState(quad.pipelineState)
        encoder.setVertexBuffer(quad.vertexBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: FullscreenQuad.vertexCount)

        // Text on top of the quad, in the same pass (002 FR-001).
        if let textSlot, let textToDraw, let text {
            text.encode(textToDraw, slot: textSlot, surface: surface, encoder: encoder, commandBuffer: commandBuffer)
        }
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        passDescriptor.colorAttachments[0].texture = nil
        return true
    }

    /// Makes sure the atlas matches this frame's backing scale, writes this frame's text, and returns the
    /// buffer to draw — or `nil` when text is unavailable.
    ///
    /// On an ordinary frame this is one `Double` comparison plus the pattern write, and allocates
    /// nothing. The first frame, and a frame after a scale change, rebuild the atlas: the one-off
    /// allocation FR-010 permits.
    private func prepareText(for surface: RenderSurface, timestamp: Double) -> TextBuffer? {
        guard let text, !textDisabled else { return nil }

        if textBuffer?.metrics.scale != surface.backingScale {
            do {
                let metrics = try text.prepareAtlas(scale: surface.backingScale)
                if let textBuffer {
                    textBuffer.metrics = metrics
                } else {
                    textBuffer = TextBuffer(metrics: metrics)
                }
                #if SWIFTSKY_INSTRUMENTATION
                Self.textLog.notice(
                    """
                    text atlas scale=\(metrics.scale, privacy: .public) \
                    cell=\(metrics.cellWidthPixels, privacy: .public)×\(metrics.cellHeightPixels, privacy: .public)px \
                    capHeight=\(metrics.capHeightPoints, privacy: .public)pt
                    """
                )
                #endif
            } catch {
                // Never show text at the wrong density: turn it off and say why (FR-018).
                textDisabled = true
                textBuffer = nil
                Self.textLog.error("text disabled: \(String(describing: error), privacy: .public)")
                return nil
            }
        }

        guard let textBuffer else { return nil }

        #if SWIFTSKY_INSTRUMENTATION
        if let debugTextPattern {
            textBuffer.clear()
            debugTextPattern.write(into: textBuffer, surface: surface, timestamp: timestamp)
        }
        #endif

        if textBuffer.didOverflow, !hasReportedOverflow {
            hasReportedOverflow = true
            Self.textLog.notice("text exceeded the 1,024-character capacity; the excess was dropped")
        }

        return textBuffer
    }
}
