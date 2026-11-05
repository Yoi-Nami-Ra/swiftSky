#if SWIFTSKY_INSTRUMENTATION
import Testing

@testable import SwiftSkyPlatform

/// `--no-debug-cargo` (022 contract C4). Parsing only.
@Suite("DebugCargoOption")
struct DebugCargoOptionTests {
    @Test(
        "Cargo lines are on unless --no-debug-cargo is present, with any other arguments",
        arguments: [
            ([String](), true),
            (["--no-debug-cargo"], false),
            (["--no-ship", "--no-debug-cargo"], false),
            (["--no-debug-overlay"], true),
            (["--no-debug-overlay", "--no-debug-cargo"], false),
            (["--debug-ship-spin", "--no-interpolation"], true),
        ]
    )
    func launchArguments(arguments: [String], showsCargo: Bool) {
        #expect(DebugCargoOption(arguments: ["swiftSky"] + arguments).showsCargo == showsCargo)
    }
}
#endif
