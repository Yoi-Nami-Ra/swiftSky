# Contracts: Ship Cargo Hold

## C1 Hold API (logic layer, internal to the project)
`CargoHold(capacity: Int, commodityCount: Int)`, `.launch`, `used`, `free`, `capacity`, `tons(of:)`,
`add(_:of:) -> CargoRejection?`, `remove(_:of:) -> CargoRejection?`. Rejection never mutates; 0 t on a known
commodity returns `nil`, 0 t on an unknown one returns `unknownCommodity`; no throw, no log. Overflow (`Int.max`) is `overCapacity`.

## C2 Commodity file
JSON object with `commodities` array of `{id, name, basePrice}`. Bundled at
`Sources/SwiftSkySimulation/Resources/commodities.json`; validation rules in data-model.md.

## C3 Overlay lines (Debug and instrumented Release only)
Under the order lines: `hold    <used> / <capacity> t  free <free>`; then for each commodity with tons > 0,
`  <name> <tons>` (a slot with no name in the list shows `?`). Values from the latest tick at the 4 Hz refresh. Not present in plain Release.

## C4 Launch argument
`--no-debug-cargo` removes every cargo line; default on; other lines unchanged; unknown in plain Release.
