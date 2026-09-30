import CoreText
import Metal
import QuartzCore
import SwiftUI
import SwiftSkyRendering

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The app's entire visible content: a Metal surface, or the failure notice if the renderer could not
/// be built (FR-024).
///
/// Construction order matters and is deliberate (contracts/frame-loop.md): the graphics device and
/// renderer are created on the main thread *before* the loop starts, so every initialisation failure
/// mode is resolved up front. A running loop therefore always has a working renderer, and the per-frame
/// path has no initialisation errors to handle.
///
/// There is no fallback to a plain black view when rendering is unavailable (FR-027) — a total rendering
/// failure must not be able to masquerade as a correct black screen. Note how easily it could: this
/// feature's correct output and its total-failure output are both "a black screen". SC-019's frame
/// capture is what distinguishes them, which is why that check exists.
public struct GameSurfaceView: View {
    @State private var host = LoopHost()

    public init() {}

    public var body: some View {
        content
            .onDisappear {
                // Explicit teardown: stop and drain before graphics resources are released (FR-032).
                host.stopAndDrain()
            }
    }

    @ViewBuilder
    private var content: some View {
        // Resolved on first body evaluation, which SwiftUI runs on the main actor — so renderer
        // construction still happens on the main thread before the loop starts (contracts/frame-loop.md).
        //
        // There is deliberately no third "not built yet" branch. An earlier version had one and filled
        // it with `Color.black`, which is a platform-UI view painting a user-visible pixel — exactly
        // what FR-001/FR-007 forbid and what SC-002's audit looks for. The pre-first-frame appearance
        // is the OS's job instead (FR-004a): the iOS launch screen and the black macOS window
        // background set in `MetalSurfaceView`.
        switch host.setup {
        case .success(let ready):
            MetalSurface(device: ready.device) { layer in
                // The loop is created HERE, with the layer that is actually on screen. Creating it
                // earlier against a placeholder layer would leave the display link driving an
                // offscreen surface — a bug indistinguishable from success, since both render black.
                host.start(ready, layer: layer)
                return { [host] event in host.post(event) }
            }
            // Fill the screen edge to edge, including under the safe-area insets, on iOS (FR-003).
            .ignoresSafeArea()

        case .failure(let error):
            RendererFailureNotice(error: error) {
                Self.quit()
            }
        }
    }

    /// Device and renderer — everything that can fail, resolved before the loop exists.
    struct Setup {
        let device: any MTLDevice
        let renderer: Renderer

        #if SWIFTSKY_INSTRUMENTATION
        /// `--debug-ship-spin`, handed to the loop when it is created (007 FR-013).
        var debugShipSpin = false
        #endif
    }

    /// Owns the loop's lifetime across SwiftUI view-struct recreations.
    ///
    /// A `View` is a value recreated on every state change, so the loop cannot live in it directly.
    /// This reference type is held in `@State` and outlives those recreations, which is what makes the
    /// `onDisappear` drain reliable rather than racy.
    ///
    /// It also owns the one-time renderer construction, so that `body` has a resolved result to switch
    /// on from its very first evaluation and never needs a placeholder branch to draw.
    final class LoopHost {
        /// Built once, on first access from `body`. Discarded `LoopHost` instances from view-struct
        /// recreation never touch it, so laziness keeps them free.
        ///
        /// `@MainActor` on the property alone — not the whole class — is what keeps
        /// contracts/frame-loop.md's "renderer constructed on the main thread before the loop starts"
        /// a compiler-checked fact rather than a comment, while leaving `post(_:)` callable from the
        /// nonisolated surface-event closure.
        @MainActor
        lazy var setup: Result<Setup, RendererError> = GameSurfaceView.buildSetup()

        private var loop: FrameLoop?

        /// Explicit and `nonisolated` because the synthesised initialiser would otherwise inherit
        /// `setup`'s main-actor isolation, which `@State`'s nonisolated initial value cannot satisfy.
        /// Only the lazy *access* needs the main actor; allocating an empty host does not.
        nonisolated init() {}

        func start(_ setup: Setup, layer: CAMetalLayer) {
            guard loop == nil else { return }
            let created = FrameLoop(renderer: setup.renderer, layer: layer)
            #if SWIFTSKY_INSTRUMENTATION
            created.debugShipSpin = setup.debugShipSpin
            #endif
            loop = created
            created.start()
        }

        func post(_ event: SurfaceEvent) {
            loop?.post(event)
        }

        func stopAndDrain() {
            loop?.stopAndDrain()
            loop = nil
        }
    }

    private static func buildSetup() -> Result<Setup, RendererError> {
        guard let device = MTLCreateSystemDefaultDevice() else {
            let error = RendererError.noGraphicsDevice
            RendererFailureReporter.report(error)
            return .failure(error)
        }

        do {
            let renderer = try Renderer(device: device, pixelFormat: .bgra8Unorm_srgb, textFont: textFont())
            #if SWIFTSKY_INSTRUMENTATION
            let arguments = ProcessInfo.processInfo.arguments
            let debugMode = DebugTextMode(arguments: arguments)
            renderer.debugTextPattern = debugMode.pattern
            renderer.debugOverlay = debugMode.overlay
            let shipOptions = DebugShipOptions(arguments: arguments)
            renderer.drawsShip = !shipOptions.hidesShip
            var setup = Setup(device: device, renderer: renderer)
            setup.debugShipSpin = shipOptions.spins
            return .success(setup)
            #else
            return .success(Setup(device: device, renderer: renderer))
            #endif
        } catch let error as RendererError {
            RendererFailureReporter.report(error)
            return .failure(error)
        } catch {
            let wrapped = RendererError.pipelineStateCreationFailed(underlying: error.localizedDescription)
            RendererFailureReporter.report(wrapped)
            return .failure(wrapped)
        }
    }

    /// The 13-point system monospaced font, for the renderer's text (002 FR-002, FR-007).
    ///
    /// Resolved here because the system's monospaced *design* is only reachable through AppKit and
    /// UIKit — Core Text alone offers the user's fixed-pitch font, which is user-configurable and not
    /// the same face (002 research.md R1). Both font classes are toll-free bridged to `CTFont`, so the
    /// rendering layer receives it without importing either framework.
    private static func textFont() -> CTFont {
        #if os(macOS)
        NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) as CTFont
        #else
        UIFont.monospacedSystemFont(ofSize: 13, weight: .regular) as CTFont
        #endif
    }

    private static func quit() {
        #if os(macOS)
        NSApplication.shared.terminate(nil)
        #else
        // iOS has no sanctioned programmatic quit. The notice is the terminal state; the user dismisses
        // the app themselves.
        exit(0)
        #endif
    }
}

#if SWIFTSKY_INSTRUMENTATION

/// Which debug text to draw, from the launch arguments (002 FR-015, FR-015a, research.md R9; 003
/// FR-001, FR-011, FR-012, research.md R7).
///
/// Debug and Profiling builds only. In Release this type and the parsing do not exist, so no launch
/// argument can put text on screen (002 SC-006, 003 SC-005). Double-dash arguments, so AppKit's
/// `-Key value` argument domain never reads them and nothing persists between launches.
///
/// The live overlay is the default. `--no-debug-overlay` turns it off, leaving the black surface with
/// the ship on it. Add `--no-ship` (`DebugShipOptions`) for the uniformly black surface that 001's and
/// 002's visible-output checks expect. Either test-string argument replaces the
/// overlay, because both draw in the same corner and the fill needs the whole text capacity.
enum DebugTextMode: Equatable {
    case overlay
    case none
    case testString
    case fill

    static let testStringArgument = "--debug-text"
    static let fillArgument = "--debug-text-fill"
    static let noOverlayArgument = "--no-debug-overlay"

    /// Precedence: `--debug-text-fill` > `--debug-text` > `--no-debug-overlay` > the overlay.
    init(arguments: [String]) {
        if arguments.contains(Self.fillArgument) {
            self = .fill
        } else if arguments.contains(Self.testStringArgument) {
            self = .testString
        } else if arguments.contains(Self.noOverlayArgument) {
            self = .none
        } else {
            self = .overlay
        }
    }

    var pattern: DebugTextPattern? {
        switch self {
        case .overlay, .none: nil
        case .testString: DebugTextPattern(mode: .testString)
        case .fill: DebugTextPattern(mode: .fill)
        }
    }

    var overlay: DebugOverlay? {
        self == .overlay ? DebugOverlay() : nil
    }
}

/// The ship switches, from the launch arguments (007 FR-013–FR-015, research R9).
///
/// Debug and Profiling builds only, like `DebugTextMode`: in Release this type, its parsing and both
/// strings do not exist, so a Release build always draws the ship and never spins it. The two switches
/// are independent of each other and of the text arguments.
struct DebugShipOptions: Equatable {
    /// `--debug-ship-spin`: every tick gets a full counter-clockwise turn and no thrust, so the ship turns
    /// in place at its top rate — the only way to see it rotate before orders exist.
    var spins: Bool

    /// `--no-ship`: the ship is not drawn. With `--no-debug-overlay` the surface is uniformly black again,
    /// so the earlier black-surface checks still apply. The simulation is untouched.
    var hidesShip: Bool

    static let spinArgument = "--debug-ship-spin"
    static let noShipArgument = "--no-ship"

    init(arguments: [String]) {
        spins = arguments.contains(Self.spinArgument)
        hidesShip = arguments.contains(Self.noShipArgument)
    }
}

#endif
