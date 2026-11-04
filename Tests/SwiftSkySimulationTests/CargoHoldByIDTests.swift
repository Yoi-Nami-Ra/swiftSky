import Foundation
import Testing

@testable import SwiftSkySimulation

/// The id-checked hold operations (022 FR-004, FR-005, US2 scenario 2): an id that is not in the list is
/// rejected even on the 16-slot launch hold, whose index API accepts any slot.
@Suite("CargoHold by id")
struct CargoHoldByIDTests {
    private let list = try! CommodityList(decoding: Data("""
        { "commodities": [
          { "id": "water", "name": "Water", "basePrice": 10 },
          { "id": "ore", "name": "Ore", "basePrice": 40 }
        ] }
        """.utf8))

    @Test func unknownIDIsRejectedOnTheLaunchHold() {
        var hold = Ship().hold
        let before = hold
        #expect(hold.add(1, of: "no-such-commodity", in: list) == .unknownCommodity)
        #expect(hold.remove(0, of: "no-such-commodity", in: list) == .unknownCommodity)
        #expect(hold == before)
    }

    @Test func knownIDAddsAndRemovesAtItsIndex() {
        var hold = CargoHold.launch
        #expect(hold.add(5, of: "ore", in: list) == nil)
        #expect(hold.tons(of: 1) == 5)
        #expect(hold.remove(2, of: "ore", in: list) == nil)
        #expect(hold.tons(of: 1) == 3)
        #expect(hold.used == 3)
    }

    @Test func knownIDKeepsTheIndexRules() {
        var hold = CargoHold.launch
        #expect(hold.add(21, of: "water", in: list) == .overCapacity)
        #expect(hold.remove(1, of: "water", in: list) == .notEnoughStock)
        #expect(hold == CargoHold.launch)
    }

    @Test func negativeWinsOverUnknownID() {
        var hold = CargoHold.launch
        #expect(hold.add(-1, of: "no-such-commodity", in: list) == .negativeAmount)
        #expect(hold.remove(-1, of: "no-such-commodity", in: list) == .negativeAmount)
    }
}

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
