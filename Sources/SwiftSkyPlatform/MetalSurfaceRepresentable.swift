import Metal
import QuartzCore
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Bridges the `CAMetalLayer`-backed view into SwiftUI.
///
/// This is the whole of SwiftUI's involvement in what the user sees: create a scene, host a surface.
/// It draws nothing (FR-007). A representable is the thinnest available bridge — SwiftUI has no native
/// way to host a Metal layer, and `MTKView` was rejected because it would take over the draw loop on the
/// main thread (research.md R5, R6).
///
/// One file serves both platforms, differing only in the protocol conformance and the `make…View`
/// signature. That is FR-014's "thinnest possible boundary" in practice.
struct MetalSurface {
    let device: any MTLDevice

    /// Called once with the layer the frame loop's display link should attach to. Returns the sink the
    /// view pushes surface events into, which the loop drains at a frame boundary (FR-029, FR-031).
    let attach: (CAMetalLayer) -> (SurfaceEvent) -> Void

    fileprivate func makeSurfaceView() -> MetalSurfaceView {
        let view = MetalSurfaceView(device: device)
        view.onSurfaceChange = attach(view.metalLayer)
        return view
    }
}

#if os(macOS)

extension MetalSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> MetalSurfaceView { makeSurfaceView() }

    func updateNSView(_ view: MetalSurfaceView, context: Context) {
        // Nothing to update. The view owns its own geometry tracking, and SwiftUI state never drives
        // what is drawn (FR-001, FR-012b).
    }
}

#else

extension MetalSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> MetalSurfaceView { makeSurfaceView() }

    func updateUIView(_ view: MetalSurfaceView, context: Context) {
        // See the macOS note above.
    }
}

#endif
