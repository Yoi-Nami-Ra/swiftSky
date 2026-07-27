import QuartzCore
import SwiftSkyRendering

#if os(macOS)
import AppKit
typealias PlatformView = NSView
#else
import UIKit
typealias PlatformView = UIView
#endif

/// Hosts the `CAMetalLayer` the renderer presents into.
///
/// Draws nothing of its own: no background colour, no `draw(_:)` override, no subviews. Every visible
/// pixel comes from the render pipeline (FR-001), and this view's entire job is to own a correctly
/// sized, correctly configured drawable and report size changes (FR-007).
///
/// `MTLKit`'s `MTKView` was deliberately not used — it drives its own draw loop on the main thread and
/// owns the drawable lifecycle, which fights FR-028's off-main loop and FR-027a's skip-on-unavailable
/// behaviour (research.md R5, R6).
final class MetalSurfaceView: PlatformView {
    /// Called whenever the drawable's size or scale changes. The receiver marshals it to the frame
    /// loop's isolation domain; this view never touches loop state itself (FR-029).
    var onSurfaceChange: ((SurfaceEvent) -> Void)?

    let metalLayer = CAMetalLayer()

    init(device: any MTLDevice) {
        super.init(frame: .zero)
        configure(device: device)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MetalSurfaceView is created in code, never from a nib")
    }

    private func configure(device: any MTLDevice) {
        metalLayer.device = device
        // FR-002c: standard sRGB, 8 bits per channel, opaque.
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.isOpaque = true
        // Opaque plus no background means nothing behind the surface can influence a pixel, which is
        // what keeps FR-001 airtight rather than merely intended.
        metalLayer.backgroundColor = nil
        metalLayer.framebufferOnly = true
        metalLayer.allowsNextDrawableTimeout = true

        #if os(macOS)
        wantsLayer = true
        layer = metalLayer
        layerContentsRedrawPolicy = .duringViewResize
        #else
        layer.addSublayer(metalLayer)
        metalLayer.frame = bounds
        #endif

        configureAccessibility()
    }

    /// FR-009: the surface must not be an unlabelled dead zone for assistive technology.
    ///
    /// A pure Metal surface has no accessible children, so without this a screen reader would find an
    /// unnamed region and move on. English-only — localisation is out of scope for this feature.
    private func configureAccessibility() {
        #if os(macOS)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("swiftSky game surface")
        #else
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityLabel = "swiftSky game surface"
        #endif
    }

    // MARK: - Size and scale tracking

    /// Current drawable geometry in device pixels.
    private var currentSurface: RenderSurface {
        let scale = backingScale
        let size = bounds.size
        return RenderSurface(
            widthPixels: UInt32(max(0, (size.width * scale).rounded())),
            heightPixels: UInt32(max(0, (size.height * scale).rounded())),
            backingScale: scale
        )
    }

    private var backingScale: Double {
        #if os(macOS)
        Double(window?.backingScaleFactor ?? 2.0)
        #else
        Double(window?.screen.scale ?? traitCollection.displayScale)
        #endif
    }

    /// Applies a new size to the layer and reports it.
    ///
    /// A zero-area surface is a real, routine state — mid-resize, collapsed windows, teardown — so it
    /// is reported rather than suppressed. The loop skips drawing on it.
    private func surfaceGeometryChanged(scaleChanged: Bool) {
        let surface = currentSurface

        metalLayer.contentsScale = surface.backingScale
        #if os(iOS)
        metalLayer.frame = bounds
        #endif

        if surface.isRenderable {
            metalLayer.drawableSize = CGSize(
                width: Double(surface.widthPixels),
                height: Double(surface.heightPixels)
            )
        }

        onSurfaceChange?(scaleChanged ? .backingScaleChanged(surface) : .resized(surface))
    }

    #if os(macOS)

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        surfaceGeometryChanged(scaleChanged: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Moving to a display of different density, or a resolution change (FR-031).
        surfaceGeometryChanged(scaleChanged: true)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Occlusion drives loop start/stop (FR-008). Reported as a visibility change; the loop
        // decides what to do with it.
        onSurfaceChange?(.visibilityChanged(isVisible: window?.occlusionState.contains(.visible) ?? false))
        surfaceGeometryChanged(scaleChanged: true)
    }

    #else

    override func layoutSubviews() {
        super.layoutSubviews()
        surfaceGeometryChanged(scaleChanged: false)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onSurfaceChange?(.visibilityChanged(isVisible: window != nil))
        surfaceGeometryChanged(scaleChanged: true)
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        if previous?.displayScale != traitCollection.displayScale {
            surfaceGeometryChanged(scaleChanged: true)
        }
    }

    #endif
}
