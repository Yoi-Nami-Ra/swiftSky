import Foundation
import Testing
@testable import SwiftSkySimulation

@Suite("CommodityList")
struct CommodityListTests {
    private func list(_ json: String) throws -> CommodityList {
        try CommodityList(decoding: Data(json.utf8))
    }

    private func entry(_ id: String, _ name: String, _ price: Int) -> String {
        "{ \"id\": \"\(id)\", \"name\": \"\(name)\", \"basePrice\": \(price) }"
    }

    private func file(_ entries: [String]) -> String {
        "{ \"commodities\": [\(entries.joined(separator: ","))] }"
    }

    @Test func bundledFileLoads() throws {
        let list = try CommodityList.load()
        #expect(list.count >= 1 && list.count <= 16)
        #expect(Set(list.commodities.map(\.id)).count == list.count)
        #expect(list.commodities.allSatisfy { $0.basePrice > 0 && !$0.name.isEmpty && !$0.id.isEmpty })
    }

    @Test func indexOfID() throws {
        let list = try CommodityList.load()
        #expect(list.index(ofID: list[0].id) == 0)
        #expect(list.index(ofID: list[list.count - 1].id) == list.count - 1)
        #expect(list.index(ofID: "no-such-commodity") == nil)
    }

    @Test func badJSON() {
        #expect {
            try self.list("not json")
        } throws: { error in
            if case .malformed = error as? CommodityListError { return true }
            return false
        }
    }

    @Test func emptyList() {
        #expect(throws: CommodityListError.empty) { try self.list(self.file([])) }
    }

    @Test func tooMany() {
        let entries = (0..<17).map { entry("c\($0)", "C\($0)", 1) }
        #expect(throws: CommodityListError.tooMany(max: 16)) { try self.list(self.file(entries)) }
    }

    @Test func sixteenIsAccepted() throws {
        let entries = (0..<16).map { entry("c\($0)", "C\($0)", 1) }
        #expect(try list(file(entries)).count == 16)
    }

    @Test func duplicateID() {
        #expect(throws: CommodityListError.duplicateID("a")) {
            try self.list(self.file([self.entry("a", "A", 1), self.entry("a", "B", 2)]))
        }
    }

    @Test func emptyID() {
        #expect(throws: CommodityListError.emptyID) { try self.list(self.file([self.entry("", "A", 1)])) }
    }

    @Test func emptyName() {
        #expect(throws: CommodityListError.emptyName(id: "a")) {
            try self.list(self.file([self.entry("a", "", 1)]))
        }
    }

    @Test func zeroPrice() {
        #expect(throws: CommodityListError.nonPositivePrice(id: "a")) {
            try self.list(self.file([self.entry("a", "A", 0)]))
        }
    }

    @Test func negativePrice() {
        #expect(throws: CommodityListError.nonPositivePrice(id: "a")) {
            try self.list(self.file([self.entry("a", "A", -5)]))
        }
    }
}
