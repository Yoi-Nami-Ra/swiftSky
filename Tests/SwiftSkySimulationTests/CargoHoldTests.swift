import Testing
@testable import SwiftSkySimulation

@Suite("CargoHold")
struct CargoHoldTests {
    // MARK: US1

    @Test func addThenReadBack() {
        var hold = CargoHold.launch
        #expect(hold.add(5, of: 0) == nil)
        #expect(hold.tons(of: 0) == 5)
        #expect(hold.used == 5)
        #expect(hold.free == 15)
    }

    @Test func removeReducesStock() {
        var hold = CargoHold.launch
        _ = hold.add(5, of: 1)
        #expect(hold.remove(2, of: 1) == nil)
        #expect(hold.tons(of: 1) == 3)
        #expect(hold.used == 3)
        #expect(hold.free == 17)
    }

    @Test func fillsToExactlyCapacityThenRejects() {
        var hold = CargoHold.launch
        #expect(hold.add(12, of: 0) == nil)
        #expect(hold.add(8, of: 3) == nil)
        #expect(hold.used == 20)
        #expect(hold.free == 0)
        let before = hold
        #expect(hold.add(1, of: 0) == .overCapacity)
        #expect(hold == before)
    }

    @Test func nineteenUsedRejectsTwo() {
        var hold = CargoHold.launch
        _ = hold.add(19, of: 0)
        let before = hold
        #expect(hold.add(2, of: 1) == .overCapacity)
        #expect(hold == before)
        #expect(hold.add(1, of: 1) == nil)
    }

    @Test func removeMoreThanHeldRejected() {
        var hold = CargoHold.launch
        _ = hold.add(3, of: 2)
        _ = hold.add(5, of: 4)
        let before = hold
        #expect(hold.remove(4, of: 2) == .notEnoughStock)
        #expect(hold == before)
    }

    @Test func zeroTonsOnKnownCommodityIsAcceptedAndChangesNothing() {
        var hold = CargoHold.launch
        _ = hold.add(4, of: 0)
        let before = hold
        #expect(hold.add(0, of: 0) == nil)
        #expect(hold.remove(0, of: 5) == nil)
        #expect(hold == before)
    }

    @Test func capacityZeroAcceptsNothing() {
        var hold = CargoHold(capacity: 0, commodityCount: 6)
        #expect(hold.add(1, of: 0) == .overCapacity)
        #expect(hold.add(0, of: 0) == nil)
        #expect(hold.used == 0)
        #expect(hold.free == 0)
    }

    @Test func launchHoldIsEmptyWithCapacityTwenty() {
        let hold = CargoHold.launch
        #expect(hold.capacity == 20)
        #expect(hold.used == 0)
        #expect(hold.free == 20)
        #expect(hold.commodityCount == 16)
    }

    @Test func negativeCapacityIsClampedAndCountIsClamped() {
        #expect(CargoHold(capacity: -5, commodityCount: 3).capacity == 0)
        #expect(CargoHold(capacity: 5, commodityCount: 99).commodityCount == 16)
        #expect(CargoHold(capacity: 5, commodityCount: -1).commodityCount == 0)
    }

    // MARK: US2

    @Test func negativeAmountsRejected() {
        var hold = CargoHold.launch
        _ = hold.add(3, of: 0)
        let before = hold
        #expect(hold.add(-1, of: 0) == .negativeAmount)
        #expect(hold.remove(-1, of: 0) == .negativeAmount)
        #expect(hold == before)
    }

    @Test func unknownIndexRejected() {
        var hold = CargoHold(capacity: 20, commodityCount: 6)
        let before = hold
        for index in [-1, Int.min, 6, 7, 16, 1_000, Int.max] {
            #expect(hold.add(1, of: index) == .unknownCommodity)
            #expect(hold.remove(1, of: index) == .unknownCommodity)
            #expect(hold.tons(of: index) == 0)
        }
        #expect(hold == before)
    }

    @Test func unknownIndexOnFullSizeHold() {
        var hold = CargoHold.launch
        #expect(hold.add(1, of: 16) == .unknownCommodity)
        #expect(hold.add(1, of: 15) == nil)
    }

    @Test func zeroTonsOnUnknownCommodityIsUnknown() {
        var hold = CargoHold(capacity: 20, commodityCount: 3)
        #expect(hold.add(0, of: 3) == .unknownCommodity)
        #expect(hold.remove(0, of: -1) == .unknownCommodity)
    }

    @Test func negativeAmountWinsOverUnknownCommodity() {
        var hold = CargoHold(capacity: 20, commodityCount: 3)
        #expect(hold.add(-1, of: 9) == .negativeAmount)
    }

    @Test func extremeAmountsDoNotWrap() {
        var hold = CargoHold.launch
        _ = hold.add(7, of: 0)
        let before = hold
        #expect(hold.add(Int.max, of: 0) == .overCapacity)
        #expect(hold.add(Int.min, of: 0) == .negativeAmount)
        #expect(hold.remove(Int.max, of: 0) == .notEnoughStock)
        #expect(hold.remove(Int.min, of: 0) == .negativeAmount)
        #expect(hold == before)
    }

    @Test func generatedSequenceKeepsInvariants() {
        var hold = CargoHold(capacity: 20, commodityCount: 6)
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int(truncatingIfNeeded: state >> 33)
        }
        var accepted = 0
        var rejected = 0
        for _ in 0..<5_000 {
            let tons = next() % 14 - 3
            let index = next() % 9 - 1
            let before = hold
            let result = next() % 2 == 0 ? hold.add(tons, of: index) : hold.remove(tons, of: index)
            if result == nil {
                accepted += 1
            } else {
                rejected += 1
                #expect(hold == before)
            }
            #expect(hold.used <= hold.capacity)
            #expect(hold.free >= 0)
            for slot in 0..<16 { #expect(hold.tons(of: slot) >= 0) }
        }
        #expect(accepted > 0)
        #expect(rejected > 0)
    }
}
