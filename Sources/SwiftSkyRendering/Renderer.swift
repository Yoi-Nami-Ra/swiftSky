import CoreText
import Metal
import QuartzCore
import SwiftSkySimulation
import os

/// Draws the visible surface: the black background, the order overlay (014), the ship at its pose
/// (007), and any text. Owns
/// Metal, the shaders, the black colour and the ship image.
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

    /// The ship's pipeline and texture, built once (007 FR-011). The ship is part of the game, not an
    /// optional extra, so a failure here is a `RendererError` (007 FR-005), unlike text.
    private let ship: ShipSprite

    /// The order overlay's pipelines, built once (014 FR-013). Gameplay UI, so a failure here is a
    /// `RendererError`, as for the ship.
    private let orderOverlay: OrderOverlayPipelines

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

    /// The live debug overlay, drawn when no test string is (003 FR-001, FR-012). Set once, before the
    /// loop starts, by the platform layer; `nil` — `--no-debug-overlay` — draws nothing.
    public var debugOverlay: DebugOverlay?

    /// Hands the overlay the frame loop's latest snapshot. Loop thread only, like `render`; called four
    /// times a second, and the overlay redraws it every frame until the next one (003 FR-006, FR-015).
    public func updateDebugOverlay(_ statistics: DebugOverlayStatistics) {
        debugOverlay?.statistics = statistics
    }

    /// Whether to draw the ship. Set once, before the loop starts, by the platform layer: `false` for
    /// `--no-ship`, so that with `--no-debug-overlay` the surface is uniformly black again and the
    /// 001–003 checks that expect it still apply (007 FR-014). The simulation is unaffected.
    public var drawsShip = true
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
        self.ship = try ShipSprite(
            device: device,
            library: library,
            pixelFormat: pixelFormat,
            commandQueue: queue,
            image: Self.loadShipImage()
        )
        self.orderOverlay = try OrderOverlayPipelines(device: device, library: library, pixelFormat: pixelFormat)

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
    /// - Parameter shipPose: where to draw the ship: the frame loop's blend of its last two ticks
    ///   (013 FR-006, FR-007). Everything else drawn from the ship's pose must use this one too, so it
    ///   never drifts from the sprite. Read only, never written back.
    /// - Parameter poseTick: the latest tick at or behind `shipPose`: the tick before the latest when the
    ///   pose is blended, the latest under `--no-interpolation` (014 contract C4). The order overlay draws
    ///   only the planned-path points after it, so the line never runs behind the ship (014 FR-007).
    @discardableResult
    public func render(
        state: SimulationState,
        shipPose: ShipPose,
        poseTick: UInt64,
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

        // The order overlay over the background and under the ship, in every build (014 FR-003, FR-009).
        encodeOrderOverlay(state: state, shipPose: shipPose, poseTick: poseTick, surface: surface, encoder: encoder)

        // The ship over the background, at this frame's drawn pose (007 FR-001, FR-009; 013 FR-006).
        // Nothing here writes back to the logic layer.
        encodeShip(at: shipPose, surface: surface, encoder: encoder)

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

    /// Draws the ship at its pose, or nothing when the surface has no camera (007 FR-012) or, in Debug,
    /// when `--no-ship` hid it.
    ///
    /// Allocation-free (007 FR-011): the placement is a value, and its four corners go to the GPU as 32
    /// bytes through `setVertexBytes`, which copies them into the command stream.
    private func encodeShip(at pose: ShipPose, surface: RenderSurface, encoder: any MTLRenderCommandEncoder) {
        #if SWIFTSKY_INSTRUMENTATION
        guard drawsShip else { return }
        #endif
        guard let placement = ShipSpritePlacement(position: pose.position, heading: pose.heading, surface: surface)
        else { return }

        let (a, b, c, d) = placement.clipCorners
        var corners = (
            SIMD2<Float>(Float(a.x), Float(a.y)),
            SIMD2<Float>(Float(b.x), Float(b.y)),
            SIMD2<Float>(Float(c.x), Float(c.y)),
            SIMD2<Float>(Float(d.x), Float(d.y))
        )
        encoder.setRenderPipelineState(self.ship.pipelineState)
        withUnsafeBytes(of: &corners) { bytes in
            encoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        encoder.setFragmentTexture(self.ship.texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: ShipSprite.vertexCount)
    }

    /// Draws the current order's marker, highlight and remaining path, or nothing when `OrderOverlay`
    /// gives none (014 FR-001, FR-015).
    ///
    /// Allocation-free (014 FR-013): the overlay and the copies below are stack values, and all of it
    /// goes to the GPU through `setVertexBytes` — at most 2,064 bytes of points, 32 of rings and 32 of
    /// uniforms, each under the 4 KB limit (research R6).
    private func encodeOrderOverlay(
        state: SimulationState,
        shipPose: ShipPose,
        poseTick: UInt64,
        surface: RenderSurface,
        encoder: any MTLRenderCommandEncoder
    ) {
        guard let overlay = OrderOverlay(state: state, shipPose: shipPose, poseTick: poseTick, surface: surface)
        else { return }

        let scale = overlay.scale
        var uniforms = OrderOverlayUniforms(
            surfacePixels: SIMD2(Float(overlay.surfaceWidthPixels), Float(overlay.surfaceHeightPixels)),
            lineHalfWidth: Float(OrderOverlayStyle.lineWidth / 2 * scale),
            colour: OrderOverlayStyle.colour
        )

        var points = InlineArray<258, SIMD2<Float>>(repeating: .zero)
        var index = 0
        while index < overlay.lineCount {
            let point = overlay.linePoints[index]
            points[index] = SIMD2(Float(point.x), Float(point.y))
            index += 1
        }

        let marker = overlay.markerCentre
        let highlight = overlay.highlightCentre
        var rings = (
            OrderOverlayRing(
                centre: SIMD2(Float(marker.x), Float(marker.y)),
                radius: Float(OrderOverlayStyle.markerRadius * scale),
                halfWidth: Float(OrderOverlayStyle.markerStroke / 2 * scale)
            ),
            OrderOverlayRing(
                centre: SIMD2(Float(highlight.x), Float(highlight.y)),
                radius: Float(OrderOverlayStyle.highlightRadius * scale),
                halfWidth: Float(OrderOverlayStyle.highlightStroke / 2 * scale)
            )
        )

        withUnsafeBytes(of: &uniforms) { bytes in
            encoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 1)
            encoder.setFragmentBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }

        encoder.setRenderPipelineState(orderOverlay.line)
        withUnsafeBytes(of: &points) { bytes in
            encoder.setVertexBytes(
                bytes.baseAddress!, length: overlay.lineCount * MemoryLayout<SIMD2<Float>>.stride, index: 0
            )
        }
        encoder.drawPrimitives(
            type: .triangleStrip, vertexStart: 0, vertexCount: OrderOverlayPipelines.vertexCount,
            instanceCount: overlay.lineCount - 1
        )

        encoder.setRenderPipelineState(orderOverlay.ring)
        withUnsafeBytes(of: &rings) { bytes in
            encoder.setVertexBytes(bytes.baseAddress!, length: bytes.count, index: 0)
        }
        encoder.drawPrimitives(
            type: .triangleStrip, vertexStart: 0, vertexCount: OrderOverlayPipelines.vertexCount, instanceCount: 2
        )
    }

    /// Decodes the bundled ship image, turning each way it can fail into the one renderer error
    /// (007 FR-005, research R7).
    private static func loadShipImage() throws(RendererError) -> ShipImageBitmap {
        guard let url = ShipImageBitmap.bundledURL else {
            throw .shipImageUnavailable(reason: "ship.png is missing from the app")
        }
        do {
            return try ShipImageBitmap(contentsOf: url)
        } catch {
            switch error {
            case .missing:
                throw .shipImageUnavailable(reason: "ship.png is missing from the app")
            case .undecodable:
                throw .shipImageUnavailable(reason: "ship.png is not a readable image")
            case .wrongSize(let width, let height):
                throw .shipImageUnavailable(reason: "ship.png is \(width)×\(height) pixels, and 80×80 is expected")
            }
        }
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
        // At most one of the two is set (the platform layer's launch-argument parsing), and the test
        // string wins if both ever were, so its checks are never disturbed (003 FR-012).
        if let debugTextPattern {
            textBuffer.clear()
            debugTextPattern.write(into: textBuffer, surface: surface, timestamp: timestamp)
        } else if let debugOverlay {
            textBuffer.clear()
            debugOverlay.write(into: textBuffer, surface: surface)
        }
        #endif

        if textBuffer.didOverflow, !hasReportedOverflow {
            hasReportedOverflow = true
            Self.textLog.notice("text exceeded the 1,024-character capacity; the excess was dropped")
        }

        return textBuffer
    }
}
