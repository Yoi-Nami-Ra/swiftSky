// swift-tools-version: 6.2
// swiftSky — a cross-platform 2D game in Swift with a Metal rendering pipeline.
//
// The three layer targets below ARE the architecture boundary required by FR-010 and enforced by
// FR-013: a target can only import a module it declares as a dependency, so the three forbidden
// directions (logic→rendering, logic→platform, rendering→platform) cannot compile.
//
//   SwiftSkyPlatform  ──▶  SwiftSkyRendering  ──▶  SwiftSkySimulation
//          └────────────────────────────────────────────▶
//
// SwiftSkySimulation declares NO dependencies. Do not add any.

import PackageDescription

/// Swift 6 language mode with strict concurrency checking (FR-030).
///
/// NOTE ON SC-015 — why warnings-as-errors is NOT set here. `.treatAllWarnings(as: .error)` used to
/// sit in this list, justified as making "zero strict-concurrency warnings" mechanical rather than
/// inspected. It did the exact opposite, and the failure mode is worth recording so it is not
/// reintroduced:
///
/// Xcode passes `-suppress-warnings` when it builds package targets. Combined with this setting's
/// `-warnings-as-errors` that is a hard `error: conflicting options`, so **both app targets failed to
/// build before a single Swift file was compiled** — while the command-line `swift build` path failed
/// even earlier, in Renderer.swift. Neither path ever reached `SwiftSkyPlatform`, so the three
/// main-actor violations that were actually present in `MetalSurfaceRepresentable.swift` went
/// unreported for as long as the setting was here. A gate that breaks the build for an unrelated
/// reason enforces nothing; it only hides what it was meant to catch.
///
/// Enforcement now lives in `Scripts/verify.sh`, which fails on any `warning:` emitted by any build
/// stage. That covers the SwiftPM *and* xcodebuild paths, which this setting could not.
///
/// NOTE ON FR-013: these settings do *not* enforce the layer boundary. SwiftPM reports a forbidden
/// cross-layer import as a warning from its dependency scanner — not from the Swift compiler — so
/// compiler-level warnings-as-errors does not reach it, and a bare `swift build` exits 0 on a
/// violation. Enforcement comes from `--explicit-target-dependency-import-check=error`, which
/// `Scripts/verify.sh` always passes. Verified: with that flag all three forbidden directions fail
/// the build; without it, two of the three succeed with only a warning (SC-009).
let layerSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),

    // FR-021e: instrumentation is compiled into debug builds and must be provably absent from
    // release. SwiftPM has only debug and release configurations, so the third "Profiling"
    // configuration named in research.md R12 lives in the Xcode project and passes this define
    // through to the package (task T007).
    .define("SWIFTSKY_INSTRUMENTATION", .when(configuration: .debug)),
]

let package = Package(
    name: "swiftSky",
    platforms: [
        // FR-022: iOS 26 / macOS 26 floor. No availability fallbacks below this.
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SwiftSkyPlatform", targets: ["SwiftSkyPlatform"]),
    ],
    targets: [
        // LOGIC LAYER — declares no dependencies. Pure value types and pure functions (FR-011, FR-012c).
        // Its only import is the C library (Darwin), for cos/sin in ShipMotion.swift (004 research R3).
        .target(
            name: "SwiftSkySimulation",
            swiftSettings: layerSettings
        ),

        // RENDER LAYER — depends on the logic layer only. Owns Metal, shaders, and the black colour.
        .target(
            name: "SwiftSkyRendering",
            dependencies: ["SwiftSkySimulation"],
            // The ship image (007 FR-002, research R1): a byte-identical copy of design/sprites/ship.png,
            // which stays the source of truth — Scripts/verify.sh fails if the two ever differ.
            // `.copy`, not `.process`: processing may re-encode a PNG, and the shipped bytes would then
            // stop matching the design file.
            resources: [.copy("Resources/ship.png")],
            swiftSettings: layerSettings
        ),

        // PLATFORM LAYER — depends on both. Owns the frame loop, surface hosting, and lifecycle.
        .target(
            name: "SwiftSkyPlatform",
            dependencies: ["SwiftSkyRendering", "SwiftSkySimulation"],
            swiftSettings: layerSettings
        ),

        // Headless, GPU-free test target for the logic layer (FR-017, SC-007).
        // Depends on SwiftSkySimulation ONLY — adding another dependency here would defeat the point.
        .testTarget(
            name: "SwiftSkySimulationTests",
            dependencies: ["SwiftSkySimulation"],
            swiftSettings: layerSettings
        ),

        // Headless tests for the rendering layer's pure logic: text layout, metrics, the CPU glyph
        // atlas, the debug text pattern (002 FR-019), the camera (005 FR-014), and the ship sprite's placement
        // and image decoding (007 FR-017). Depends on the
        // rendering layer and the logic layer, never the platform layer. The logic layer is GPU-free;
        // it is declared so the camera tests can name `Vector2` under
        // `--explicit-target-dependency-import-check=error` (005 research R8). Linking Metal is fine;
        // creating a device is not — these tests must pass on a machine with no GPU, and
        // Scripts/verify.sh fails the run if any test reaches for one (002 research.md R7).
        .testTarget(
            name: "SwiftSkyRenderingTests",
            dependencies: ["SwiftSkyRendering", "SwiftSkySimulation"],
            swiftSettings: layerSettings
        ),

        // Headless tests for the platform layer's pure measurement structs: the debug overlay's
        // one-second frame-time window and its refresh schedule (003 FR-016). Depends on
        // SwiftSkyPlatform ONLY. These tests never create a view, a layer or a FrameLoop — only plain
        // structs — so linking AppKit/UIKit is harmless and no GPU or app host is needed
        // (003 research.md R9).
        .testTarget(
            name: "SwiftSkyPlatformTests",
            dependencies: ["SwiftSkyPlatform"],
            swiftSettings: layerSettings
        ),
    ]
)
