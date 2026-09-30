#if SWIFTSKY_INSTRUMENTATION
import Testing

@testable import SwiftSkyPlatform

/// The Debug-only ship switches (007 FR-013, FR-014, contract C15). Parsing only — no view, layer or
/// loop.
@Suite("DebugShipOptions")
struct DebugShipOptionsTests {
    @Test(
        "--debug-ship-spin and --no-ship are independent of each other and of the text arguments",
        arguments: [
            ([String](), false, false),
            (["--debug-ship-spin"], true, false),
            (["--no-ship"], false, true),
            (["--debug-ship-spin", "--no-ship"], true, true),
            (["--no-debug-overlay"], false, false),
            (["--debug-text", "--debug-ship-spin"], true, false),
            (["--no-ship", "--no-debug-overlay"], false, true),
            (["--debug-text-fill", "--no-ship", "--debug-ship-spin"], true, true),
        ]
    )
    func launchArguments(arguments: [String], spins: Bool, hidesShip: Bool) {
        let options = DebugShipOptions(arguments: ["swiftSky"] + arguments)
        #expect(options.spins == spins)
        #expect(options.hidesShip == hidesShip)
    }
}
#endif
