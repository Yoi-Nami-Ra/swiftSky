// Commodity.swift — a tradeable good and the validated list loaded from the bundled data file (022, SKY-52).
//
// This is the only logic-layer file that imports Foundation (for `Bundle.module` and `JSONDecoder`).
// Nothing here runs per frame; the hold itself works on plain indices (research R3).

import Foundation

/// One commodity: a stable id, a display name and a base price in whole credits.
public struct Commodity: Sendable, Equatable {
    public let id: String
    public let name: String
    public let basePrice: Int

    public init(id: String, name: String, basePrice: Int) {
        self.id = id
        self.name = name
        self.basePrice = basePrice
    }
}

/// Why a commodity list could not be built. No partial list is ever returned.
public enum CommodityListError: Error, Equatable, Sendable {
    case fileMissing
    case malformed(reason: String)
    case empty
    case tooMany(max: Int)
    case duplicateID(String)
    case emptyName(id: String)
    case emptyID
    case nonPositivePrice(id: String)
}

/// The ordered, validated commodity list (1...16 entries, unique non-empty ids and names, positive prices).
public struct CommodityList: Sendable, Equatable {
    /// The most commodities a list (and a hold) can have.
    public static let maxCommodities = 16

    public let commodities: [Commodity]

    public var count: Int { commodities.count }

    public subscript(index: Int) -> Commodity { commodities[index] }

    /// The index of the commodity with this id, or `nil` when the list has none.
    public func index(ofID id: String) -> Int? {
        commodities.firstIndex { $0.id == id }
    }

    private struct FileShape: Decodable {
        struct Entry: Decodable {
            let id: String
            let name: String
            let basePrice: Int
        }
        let commodities: [Entry]
    }

    /// Decodes and validates `{ "commodities": [ { "id", "name", "basePrice" } ] }`.
    public init(decoding data: Data) throws(CommodityListError) {
        let file: FileShape
        do {
            file = try JSONDecoder().decode(FileShape.self, from: data)
        } catch {
            throw .malformed(reason: String(describing: error))
        }
        if file.commodities.isEmpty { throw .empty }
        if file.commodities.count > Self.maxCommodities { throw .tooMany(max: Self.maxCommodities) }
        var seen = Set<String>()
        var list: [Commodity] = []
        list.reserveCapacity(file.commodities.count)
        for entry in file.commodities {
            if entry.id.isEmpty { throw .emptyID }
            if !seen.insert(entry.id).inserted { throw .duplicateID(entry.id) }
            if entry.name.isEmpty { throw .emptyName(id: entry.id) }
            if entry.basePrice <= 0 { throw .nonPositivePrice(id: entry.id) }
            list.append(Commodity(id: entry.id, name: entry.name, basePrice: entry.basePrice))
        }
        commodities = list
    }

    /// Loads the list from the bundled `commodities.json`.
    public static func load() throws(CommodityListError) -> CommodityList {
        guard let url = Bundle.module.url(forResource: "commodities", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { throw .fileMissing }
        return try CommodityList(decoding: data)
    }
}
