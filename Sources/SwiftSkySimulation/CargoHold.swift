/// Why a hold refused an add or a remove (022 FR-005). A refusal never changes the hold.
public enum CargoRejection: Sendable, Equatable {
    /// The amount was below zero.
    case negativeAmount
    /// The commodity index is not one this hold knows.
    case unknownCommodity
    /// An add would take the load past the capacity.
    case overCapacity
    /// A remove asked for more than the hold has of that commodity.
    case notEnoughStock
}

/// A ship's cargo hold: whole tons of each commodity, up to a total capacity (022).
///
/// A plain value with inline storage, so it costs no heap and copies with the ship. The hold takes a
/// commodity *index* and knows nothing of the commodity list: mapping an id to an index is
/// `CommodityList.index(ofID:)` (022 data-model).
public struct CargoHold: Sendable, Equatable {
    /// The most commodities a hold can track, equal to `CommodityList.maxCommodities`.
    public static let maxCommodities = 16

    /// The capacity of the launch ship's hold, in tons.
    public static let defaultCapacity = 20

    /// The launch hold: capacity 20, empty, accepting any slot index. The index API cannot see the
    /// commodity list, so a caller with an id uses `add(_:of:in:)` / `remove(_:of:in:)`, which reject an
    /// id that is not in the list (022 FR-004, FR-005).
    public static let launch = CargoHold(capacity: defaultCapacity, commodityCount: maxCommodities)

    /// The total tons the hold can carry (never below zero).
    public let capacity: Int

    /// How many commodity slots are valid, 0...16.
    public let commodityCount: Int

    private var amounts: InlineArray<16, Int>

    /// Creates an empty hold. A negative capacity becomes 0 and the count is clamped to 0...16.
    public init(capacity: Int, commodityCount: Int = CargoHold.maxCommodities) {
        self.capacity = max(0, capacity)
        self.commodityCount = min(max(0, commodityCount), Self.maxCommodities)
        self.amounts = InlineArray(repeating: 0)
    }

    /// Total tons held.
    public var used: Int {
        var total = 0
        var i = 0
        while i < commodityCount {
            total += amounts[i]
            i += 1
        }
        return total
    }

    /// Tons of space left.
    public var free: Int { capacity - used }

    /// Tons of the commodity at `index`; 0 for an unknown index.
    public func tons(of index: Int) -> Int {
        isKnown(index) ? amounts[index] : 0
    }

    /// Adds `tons` of the commodity at `index`. Returns `nil` when accepted, else the reason; a
    /// rejection leaves the hold unchanged. Checks run in the order negative, unknown, capacity.
    public mutating func add(_ tons: Int, of index: Int) -> CargoRejection? {
        if tons < 0 { return .negativeAmount }
        if !isKnown(index) { return .unknownCommodity }
        if tons > free { return .overCapacity }
        amounts[index] += tons
        return nil
    }

    /// Removes `tons` of the commodity at `index`. Returns `nil` when accepted, else the reason; a
    /// rejection leaves the hold unchanged.
    public mutating func remove(_ tons: Int, of index: Int) -> CargoRejection? {
        if tons < 0 { return .negativeAmount }
        if !isKnown(index) { return .unknownCommodity }
        if tons > amounts[index] { return .notEnoughStock }
        amounts[index] -= tons
        return nil
    }

    /// Equal when capacity, count and every slot are (`InlineArray` is not `Equatable`).
    public static func == (lhs: CargoHold, rhs: CargoHold) -> Bool {
        guard lhs.capacity == rhs.capacity, lhs.commodityCount == rhs.commodityCount else { return false }
        var i = 0
        while i < maxCommodities {
            if lhs.amounts[i] != rhs.amounts[i] { return false }
            i += 1
        }
        return true
    }

    private func isKnown(_ index: Int) -> Bool {
        index >= 0 && index < commodityCount
    }
}
