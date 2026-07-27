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

        #if os(iOS)
        registerForScaleChanges()
        #endif
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
        configureWindowBackground()
        observeOcclusion()
        reportVisibility()
        scheduleVisibilityRecheck()
        surfaceGeometryChanged(scaleChanged: true)
    }

    /// FR-004a: the *window's* initial background, which the OS shows in the gap between the window
    /// appearing and the first frame being presented.
    ///
    /// This is the one exception FR-004a carves out of FR-001, and it is deliberately taken here rather
    /// than by putting a coloured view in the hierarchy: a black `NSWindow` background is the platform's
    /// pre-first-frame appearance, whereas a black SwiftUI view would be the platform-UI layer drawing a
    /// user-visible pixel — the thing SC-002's audit exists to catch.
    ///
    /// The Info.plist's `NSRequiresAquaSystemAppearance = false` alone is not enough: it forces dark
    /// appearance, whose window background is dark grey, not black. Grey is a non-black frame (FR-004).
    private func configureWindowBackground() {
        window?.backgroundColor = .black
    }

    /// Occlusion drives loop start/stop (FR-008), and it *must* be observed rather than sampled once.
    ///
    /// `viewDidMoveToWindow` runs before the window is on screen, so a single reading there reports
    /// not-visible, pauses the loop, and nothing ever resumes it — the app then renders zero frames
    /// while looking perfectly correct, because a stalled black surface and a working black surface are
    /// indistinguishable. This was a real bug, found by the absence of instrumentation output.
    private func observeOcclusion() {
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didChangeOcclusionStateNotification, object: nil
        )
        // Registered for ANY window rather than a specific one, then re-evaluating our own window's
        // state. Binding to a particular window object made the observer miss the transition that
        // matters, because the window is not yet on screen when this view is created.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil
        )
    }

    @objc private func occlusionChanged() {
        reportVisibility()
    }

    private func reportVisibility() {
        let visible = (window?.occlusionState.contains(.visible) ?? false) || (window?.isVisible ?? false)
        onSurfaceChange?(.visibilityChanged(isVisible: visible))
    }

    /// Re-evaluates visibility on the next main-loop turn.
    ///
    /// `viewDidMoveToWindow` runs *before* the window is ordered on screen, so a reading taken there is
    /// always "not visible". That single reading paused the display link permanently and the app rendered
    /// exactly one frame — while looking completely correct, because a stalled black surface and a
    /// working black surface are the same picture. Re-checking after the window has been shown is what
    /// makes FR-008's resume actually happen.
    private func scheduleVisibilityRecheck() {
        DispatchQueue.main.async { [weak self] in
            self?.reportVisibility()
        }
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

    /// Display-scale changes via the trait registration API. `traitCollectionDidChange` was deprecated
    /// in iOS 17, and warnings-as-errors turned using it into a build failure — which is the setting
    /// earning its keep.
    private func registerForScaleChanges() {
        registerForTraitChanges([UITraitDisplayScale.self]) { (view: MetalSurfaceView, _) in
            view.surfaceGeometryChanged(scaleChanged: true)
        }
    }

    #endif
}
