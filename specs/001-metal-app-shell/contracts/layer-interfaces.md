# Contract: Inter-layer Interfaces

**Feature**: `001-metal-app-shell` | **Date**: 2026-07-26

This application exposes no network or CLI surface. Its meaningful contracts are the three seams
between the layers — the interfaces FR-010 through FR-015 govern, and the ones FR-013 enforces at
compile time. Shapes are given as signatures; bodies belong to implementation.

---

## Dependency direction (FR-010)

```text
SwiftSkyPlatform  ──imports──▶  SwiftSkyRendering  ──imports──▶  SwiftSkySimulation
        │                                                                  ▲
        └──────────────────────────imports─────────────────────────────────┘

SwiftSkySimulation imports NOTHING.
```

Forbidden and compile-time impossible, because the target declares no such dependency:

| Forbidden direction | Enforced by |
|---------------------|-------------|
| Simulation → Rendering | `SwiftSkySimulation` has no dependencies |
| Simulation → Platform | `SwiftSkySimulation` has no dependencies |
| Rendering → Platform | `SwiftSkyRendering` depends only on `SwiftSkySimulation` |

Each direction is proven once by deliberately introducing a violating import and observing the build
fail (SC-009); evidence goes in [quickstart.md](../quickstart.md).

---

## Seam 1 — Simulation (logic layer public surface)

The innermost layer. Pure, synchronous, no concurrency constructs, no clock access (FR-012c, FR-033).

```swift
// SimulationState.swift
public struct SimulationState: Sendable, Equatable {
    public var tickCount: UInt64
    public init()
}

// FixedTimestep.swift
public enum FixedTimestep {
    public static let tickRate: Int          // 60
    public static let tickDuration: Double   // 1.0 / 60.0
    public static let catchUpClamp: Int      // 4
}

// TimeAccumulator.swift
public struct TimeAccumulator: Sendable {
    public init()
    /// Adds elapsed seconds and returns whole ticks to advance, clamped per FR-021b.
    /// Excess beyond the clamp is discarded.
    public mutating func consume(elapsed seconds: Double) -> Int
}

// Simulation.swift
public enum Simulation {
    /// Pure. Same inputs always produce the same output (SC-013).
    public static func advance(_ state: SimulationState, ticks: Int) -> SimulationState
}
```

**Contract guarantees**

- `advance` is referentially transparent — no clock, no randomness, no I/O, no global state (FR-015,
  FR-033).
- Every type is a value type and trivially `Sendable`, which is how FR-030's transfer safety is met
  without added annotations (FR-012d).
- Callable synchronously from a test with no isolation context and no graphics device (FR-011, FR-017).
- `ticks == 0` is legal and returns the state unchanged.

**Forbidden in this module**: any `import` at all; actors, global actors, locks (FR-012c); any colour,
size, or view concept (FR-012b).

---

## Seam 2 — Rendering (render layer public surface)

Depends on Simulation only. Owns Metal, shaders, and the black colour. Knows nothing about windows,
views, scenes, or app lifecycle.

```swift
// RenderSurface.swift
public struct RenderSurface: Sendable, Equatable {
    public var widthPixels: UInt32
    public var heightPixels: UInt32
    public var backingScale: Double
    public var isRenderable: Bool { get }   // false when either dimension is 0
}

// RendererError.swift
public enum RendererError: Error {
    case noGraphicsDevice
    case shaderLibraryUnavailable
    case shaderFunctionMissing(name: String)
    case pipelineStateCreationFailed(underlying: String)
    case geometryBufferCreationFailed
    /// Human-readable text for the FR-024 notice. English-only in this feature.
    public var userFacingDescription: String { get }
}

// Renderer.swift
public final class Renderer {
    /// Compiles shaders, creates the pipeline state and quad geometry ONCE (FR-002b).
    /// Throws RendererError on any initialisation failure (FR-024, FR-026).
    public init(device: MTLDevice, pixelFormat: MTLPixelFormat) throws

    /// Draws one frame: full-screen black quad via a real draw call (FR-002a).
    /// Reads state.tickCount every frame (FR-012a) without letting it affect output (FR-012b).
    /// Returns false if no drawable was available — caller skips (FR-027a).
    public func render(state: SimulationState, surface: RenderSurface,
                       into layer: CAMetalLayer) -> Bool
}
```

**Contract guarantees**

- No heap allocation per call to `render` (FR-020, SC-004). Geometry and pipeline state are built in
  `init` and reused.
- `render` returns `false` rather than throwing or blocking when a drawable is unavailable — this is
  routine backpressure, not an error (FR-027a).
- `render` never presents a partially drawn frame; either the full quad is drawn and presented or the
  frame is skipped.
- Never falls back to a non-pipeline black surface (FR-027).
- All failure modes are surfaced at `init`, so a running renderer is a working renderer.

**Forbidden in this module**: any reference to `NSWindow`, `UIWindow`, `NSView`, `UIView`, SwiftUI
types, or app-lifecycle types (FR-010, proven by SC-009).

---

## Seam 3 — Platform (outermost layer)

Depends on both. Supplies the surface, marshals events, owns the loop, and is the only layer permitted
to draw user-visible platform-UI content — restricted to the FR-024 failure notice (FR-007).

```swift
// SurfaceEvent.swift
public enum SurfaceEvent: Sendable {
    case resized(RenderSurface)
    case backingScaleChanged(RenderSurface)
    case visibilityChanged(isVisible: Bool)
    case willTerminate
}

// FrameLoop.swift — see frame-loop.md for lifecycle detail
public final class FrameLoop {
    public init(renderer: Renderer, layer: CAMetalLayer)
    /// Non-blocking from the caller's (main thread's) perspective (FR-029).
    public func post(_ event: SurfaceEvent)
    /// Blocks the caller only until the loop has stopped and drained (FR-032).
    public func stopAndDrain()
}
```

**Contract guarantees**

- `post` enqueues and returns; the main thread never waits for a frame (FR-029, SC-016).
- Events take effect at frame boundaries only, never mid-draw (FR-031).
- `stopAndDrain` guarantees no frame is in flight on return, so graphics resources may then be released
  safely (FR-032).
- The hosted view draws nothing of its own and sets no background colour (FR-001, FR-007).

**Forbidden in this module**: drawing any user-visible content other than the FR-024 notice; blocking
the main thread on the loop; adding menus, controls, or chrome (FR-007).
