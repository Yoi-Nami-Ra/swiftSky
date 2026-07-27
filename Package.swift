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

/// Swift 6 language mode with strict concurrency checking (FR-030), plus warnings-as-errors so that
/// SC-015's "zero strict-concurrency warnings" is enforced mechanically rather than by inspection.
///
/// NOTE ON FR-013: these settings do *not* enforce the layer boundary. SwiftPM reports a forbidden
/// cross-layer import as a warning from its dependency scanner — not from the Swift compiler — so
/// compiler-level warnings-as-errors does not reach it, and a bare `swift build` exits 0 on a
/// violation. Enforcement comes from `--explicit-target-dependency-import-check=error`, which
/// `Scripts/verify.sh` always passes. Verified: with that flag all three forbidden directions fail
/// the build; without it, two of the three succeed with only a warning (SC-009).
let layerSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .treatAllWarnings(as: .error),

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
        // LOGIC LAYER — imports nothing. Pure value types and pure functions (FR-011, FR-012c).
        .target(
            name: "SwiftSkySimulation",
            swiftSettings: layerSettings
        ),

        // RENDER LAYER — depends on the logic layer only. Owns Metal, shaders, and the black colour.
        .target(
            name: "SwiftSkyRendering",
            dependencies: ["SwiftSkySimulation"],
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
    ]
)
