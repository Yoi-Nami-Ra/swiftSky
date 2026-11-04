import Foundation
import Testing

@testable import SwiftSkySimulation

/// Holes the 022 review's mutation probe found: behaviour no earlier test could catch breaking.
@Suite("Cargo hold contract gaps")
struct CargoHoldContractTests {
    private final class TestBundleMarker {}

    @Test func bundleWithoutTheFileThrowsFileMissing() {
        #expect(throws: CommodityListError.fileMissing) {
            try CommodityList.load(from: Bundle(for: TestBundleMarker.self))
        }
    }
}
