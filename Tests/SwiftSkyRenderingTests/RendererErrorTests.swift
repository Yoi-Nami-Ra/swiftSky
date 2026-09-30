import Testing

@testable import SwiftSkyRendering

/// The renderer's initialisation failures as the FR-024 notice and FR-026 diagnostic see them
/// (007 FR-005, contract C14).
@Suite("RendererError")
struct RendererErrorTests {
    @Test(
        "Every ship-image failure has the one stable code, and a description naming the ship image",
        arguments: ["ship.png is missing from the app", "its texture could not be created"]
    )
    func shipImageUnavailable(reason: String) {
        let error = RendererError.shipImageUnavailable(reason: reason)
        #expect(error.diagnosticCode == "ship_image_unavailable")
        #expect(error.userFacingDescription.contains("ship image"))
        #expect(error.userFacingDescription.contains(reason))
    }

    @Test("Every case has its own diagnostic code")
    func codesAreDistinct() {
        let all: [RendererError] = [
            .noGraphicsDevice,
            .shaderLibraryUnavailable,
            .shaderFunctionMissing(name: "f"),
            .pipelineStateCreationFailed(underlying: "u"),
            .geometryBufferCreationFailed,
            .shipImageUnavailable(reason: "r"),
        ]
        #expect(Set(all.map(\.diagnosticCode)).count == all.count)
    }
}
