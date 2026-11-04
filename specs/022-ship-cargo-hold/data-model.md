# Data Model: Ship Cargo Hold

## Commodity (logic layer)
`id: String` (stable, unique, non-empty), `name: String` (non-empty), `basePrice: Int` (> 0, whole credits).

## CommodityList
Ordered, validated `[Commodity]` (1...16). `load()` reads the bundled file; `init(decoding: Data)` is the
testable path. Errors (`CommodityListError`): `fileMissing`, `malformed(reason)`, `empty`,
`tooMany(max)`, `duplicateID(id)`, `emptyName(id)`, `emptyID`, `nonPositivePrice(id)`. No partial list.
`index(ofID:) -> Int?`, `subscript(index)`, `count`.

File shape: `{ "commodities": [ { "id": "water", "name": "Water", "basePrice": 10 }, ... ] }`; starter list of 6
placeholders.

## CargoHold (plain value, inline)
- `capacity: Int` (>= 0; init clamps a negative to 0), `commodityCount: Int` (0...16, clamped). `.launch` is capacity 20 with `commodityCount = maxCommodities` (16): the hold cannot see the list, so it accepts any slot index; mapping an id to an index, and rejecting an id not in the list, is `CommodityList.index(ofID:)` returning `nil` at the caller (spec US2 scenario 2; tested in CommodityListTests). Tests of the unknown-index rule use `CargoHold(capacity:commodityCount:)` with a smaller count.
- amounts: `InlineArray<16, Int>`, slots `>= commodityCount` always 0
- derived: `used` (sum), `free` (capacity - used), `tons(of index)` (0 for unknown)
- `mutating add(_ tons: Int, of index: Int) -> CargoRejection?`, `mutating remove(_:of:)` likewise; `nil` = accepted.
- Order of checks: negative amount, unknown commodity, then add: over capacity (overflow-safe: `tons > free`),
  remove: not enough stock. 0 t succeeds only when the commodity is known; for an unknown commodity with 0
  t the unknown-commodity rule wins (also stated in contract C1).
- Invariants: no amount < 0; `used <= capacity`; rejection leaves the value bit-equal.

## CargoRejection
`negativeAmount`, `unknownCommodity`, `overCapacity`, `notEnoughStock`.

## Ship
Adds `hold: CargoHold` (var). Launch ship: `.launch` (capacity 20, empty). Equatable includes it.

## DebugOverlayShip.Cargo (rendering layer)
`capacity`, `used`, `free`, `count`, amounts `InlineArray<16, Int>`. `DebugOverlayShip.cargo: Cargo` set by `init(_ state:)`;
allocation-free.
