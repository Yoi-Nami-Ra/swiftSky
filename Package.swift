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

/// Swift 6 language mode with strict concurrency checking, required by FR-030 and SC-015.
let strictConcurrency: [SwiftSetting] = [.swiftLanguageMode(.v6)]

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
            swiftSettings: strictConcurrency
        ),

        // RENDER LAYER — depends on the logic layer only. Owns Metal, shaders, and the black colour.
        .target(
            name: "SwiftSkyRendering",
            dependencies: ["SwiftSkySimulation"],
            swiftSettings: strictConcurrency
        ),

        // PLATFORM LAYER — depends on both. Owns the frame loop, surface hosting, and lifecycle.
        .target(
            name: "SwiftSkyPlatform",
            dependencies: ["SwiftSkyRendering", "SwiftSkySimulation"],
            swiftSettings: strictConcurrency
        ),

        // Headless, GPU-free test target for the logic layer (FR-017, SC-007).
        // Depends on SwiftSkySimulation ONLY — adding another dependency here would defeat the point.
        .testTarget(
            name: "SwiftSkySimulationTests",
            dependencies: ["SwiftSkySimulation"],
            swiftSettings: strictConcurrency
        ),
    ]
)
