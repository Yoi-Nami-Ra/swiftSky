import QuartzCore
import os
import SwiftSkyRendering
import SwiftSkySimulation

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
    /// Called whenever the drawable's size or scale changes, and whenever the player taps the surface on
    /// iOS (008) or clicks it on macOS (009). The receiver marshals it to the frame loop's isolation domain; this view never
    /// touches loop state itself (FR-029).
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
        registerForTaps()
        #endif

        #if os(macOS)
        registerForClicks()
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
        // Direct interaction: with VoiceOver on, a tap on the surface reaches the game and orders the
        // ship, rather than only selecting the element (008 FR-014, research R5).
        accessibilityTraits = [.image, .allowsDirectInteraction]
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
            backingScale: scale,
            safeAreaInsets: currentSafeAreaInsets
        )
    }

    /// The safe-area insets the renderer places text inside, in points (002 FR-006a).
    ///
    /// On iOS these are the **window's** insets, not this view's: the SwiftUI host ignores the safe
    /// area so the surface can fill the screen edge to edge (FR-003), which can leave the view's own
    /// insets at zero while the window's stay correct (002 research.md R8). The view fills the window,
    /// so the two describe the same edges.
    ///
    /// On macOS they are normally zero, and non-zero only in full screen on a display with a camera
    /// housing.
    private var currentSafeAreaInsets: SurfaceInsets {
        #if os(macOS)
        let insets = safeAreaInsets
        #else
        let insets = window?.safeAreaInsets ?? safeAreaInsets
        #endif
        return SurfaceInsets(
            top: Double(insets.top),
            left: Double(insets.left),
            bottom: Double(insets.bottom),
            right: Double(insets.right)
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

        // Later sizes are set by the frame loop when it applies this event, not here: setting the size
        // frees the old drawables' textures synchronously, and on the main thread that was the app's
        // share of the stalls 012's continuous-resize check measured (012 T016). The first size is set
        // here, because the display link delivers no frame — so the loop applies no event — until the
        // layer has one.
        if surface.isRenderable, metalLayer.drawableSize.width == 0 || metalLayer.drawableSize.height == 0 {
            metalLayer.drawableSize = CGSize(
                width: Double(surface.widthPixels),
                height: Double(surface.heightPixels)
            )
        }

        reportDisplayRate()
        onSurfaceChange?(scaleChanged ? .backingScaleChanged(surface) : .resized(surface))
    }

    /// The last maximum frame rate posted, so the event goes out only when the screen's changes (016).
    private var postedMaximumFramesPerSecond: Int?

    /// The maximum frame rate of the screen the surface is on; 0 when there is no screen yet.
    private var maximumFramesPerSecond: Int {
        #if os(macOS)
        window?.screen?.maximumFramesPerSecond ?? 0
        #else
        window?.screen.maximumFramesPerSecond ?? 0
        #endif
    }

    /// Posts the screen's maximum frame rate before a geometry event, when it differs from the last one
    /// posted, so the loop has the new display's floor before it relearns the budget (016 contract C2).
    private func reportDisplayRate() {
        guard let post = onSurfaceChange else { return }
        let framesPerSecond = maximumFramesPerSecond
        guard framesPerSecond != postedMaximumFramesPerSecond else { return }
        postedMaximumFramesPerSecond = framesPerSecond
        post(.displayRateChanged(maximumFramesPerSecond: framesPerSecond))
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

    // MARK: - Live resize markers (012)

    #if SWIFTSKY_INSTRUMENTATION
    /// Same subsystem and category as the frame summary, so one `log show` reads both.
    private static let frameLog = Logger(subsystem: "com.swiftsky.app", category: "frame")
    #endif

    /// Brackets a window drag in the log, so the summaries that cover it can be found from the log alone
    /// (012 FR-013, contract C4). Main thread, once per drag; instrumented builds only.
    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        #if SWIFTSKY_INSTRUMENTATION
        Self.frameLog.notice("live resize began")
        #endif
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        #if SWIFTSKY_INSTRUMENTATION
        Self.frameLog.notice("live resize ended")
        #endif
    }

    // MARK: - Clicks (009)

    /// A primary click anywhere on the surface orders the ship there (009 FR-001, research R1).
    ///
    /// The system recogniser is the platform's definition of a click: it fails on a drag and fires for a
    /// trackpad tap with tap to click on. `buttonMask = 0x1` leaves right, middle and other buttons out.
    /// Each click is its own recognition, so a double-click is two orders to the same point (FR-002). It
    /// does not touch size, scale or occlusion reporting (FR-005).
    private func registerForClicks() {
        let recognizer = NSClickGestureRecognizer(target: self, action: #selector(clicked(_:)))
        recognizer.buttonMask = 0x1
        recognizer.numberOfClicksRequired = 1
        addGestureRecognizer(recognizer)
    }

    /// Posts the click and returns; the main thread never waits for a frame (008 FR-004).
    ///
    /// A Control-click is a secondary click by Mac convention, but AppKit delivers it as a primary-button
    /// event, so it is filtered here; Command, Option and Shift do not stop the order (clarification).
    /// `location(in: self)` is from this unflipped view's bottom-left corner, so it is turned into view
    /// space against `bounds.height` before it is posted (FR-004, research R3).
    @objc private func clicked(_ recognizer: NSClickGestureRecognizer) {
        guard !NSEvent.modifierFlags.contains(.control) else { return }
        let location = recognizer.location(in: self)
        let viewPoint = ClickPosition.viewPoint(
            fromBottomLeft: Vector2(x: Double(location.x), y: Double(location.y)),
            heightPoints: Double(bounds.height)
        )
        onSurfaceChange?(.moveOrderRequested(MoveOrderRequest(viewPoint: viewPoint)))
    }

    /// `false`, explicitly: the first click on an inactive window only brings it to the front and never
    /// orders the ship, as Mac apps normally behave (009 FR-003, clarification, research R2). It is also
    /// `NSView`'s default; it is written out so the decision is visible.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        false
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

    /// Rotation, iPad multitasking and the status bar all move the safe area. The new insets travel in
    /// the surface, as a `.resized` event (002 FR-006a).
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
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

    // MARK: - Taps (008)

    /// A tap anywhere on the surface orders the ship there (008 FR-001, FR-002, research R4).
    ///
    /// The system recogniser is the platform's definition of a tap — movement and duration limits,
    /// failure on a second finger — and it leaves the system's own edge gestures alone (FR-003). It does
    /// not touch layout, the scale registration or visibility, so the surface's reporting is unchanged.
    private func registerForTaps() {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
        recognizer.numberOfTapsRequired = 1
        recognizer.numberOfTouchesRequired = 1
        addGestureRecognizer(recognizer)
    }

    /// Posts the tap and returns; the main thread never waits for a frame (008 FR-004).
    ///
    /// `location(in: self)` is in this view's points from its top-left corner, +y down — the camera's
    /// view space (005 FR-004). The view fills the window edge to edge, so the whole surface is
    /// tappable, including outside the safe area (008 FR-002). The loop converts the position against
    /// the surface it has applied (research R2).
    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: self)
        let request = MoveOrderRequest(viewPoint: Vector2(x: Double(location.x), y: Double(location.y)))
        onSurfaceChange?(.moveOrderRequested(request))
    }

    #endif
}
