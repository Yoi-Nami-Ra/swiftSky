# Research: Ship Cargo Hold

## R1 Bundled data file in a dependency-free logic target
- Decision: `resources: [.copy("Resources/commodities.json")]` on `SwiftSkySimulation`; loaded with
  `Bundle.module.url(forResource:withExtension:)` and `JSONDecoder` in `Commodity.swift`.
- Rationale: same pattern as `ship.png` in the rendering target (`.copy`, bytes untouched; JSON needs no
  processing). SwiftPM synthesises `Bundle.module` for the target and the Xcode project builds the local
  package, so the resource bundle is embedded in both app targets as it already is for rendering. Foundation
  is not a package dependency, so the "no dependencies" rule stands; it is imported in one file only.
- Risks to check at implementation: the `--explicit-target-dependency-import-check=error` step accepts
  Foundation (a system module); `verify.sh` warnings-as-failures (a resource target with no unhandled
  files has none); both app builds still find the bundle; the headless tests find it via `Bundle.module`.
- Alternatives: JSON as a Swift literal (not data, violates D1); a hand-written line format (avoids
  Foundation decoding but `Bundle.module` needs Foundation anyway); `.process` (may transform; no gain).

## R2 Hold storage
- Decision: `InlineArray<16, Int>` of tons indexed by commodity index (list order), plus `capacity: Int`
  and `commodityCount: Int`. About 150 bytes, a plain Equatable value, same technique as 010's PlannedPath.
- Rationale: a Dictionary heap-allocates and copy-on-write shares a buffer between the loop's state and
  the renderer's copy; the inline array copies bytes. A running `used` sum is not stored; it is derived
  (16 adds), so no field can drift from the amounts (FR-007).
- Alternatives: `Dictionary<String, Int>` (heap, string keys); `[Int]` (heap).
- Measured (phase 3, T012): `MemoryLayout<CargoHold>.size` 144 bytes, `Ship` 216, `SimulationState` 4,393 bytes (010's figure was ~4.2 KB); still a plain inline value, no heap.

## R3 Commodity identity
- Decision: the file's stable string `id` is validated and mapped by `CommodityList.index(ofID:)` to an
  `Int` index; hold operations take that index. An index outside `0..<commodityCount` is the "unknown
  commodity" rejection. The hold holds no reference to the list.
- Rationale: keeps the hold a pure inline value (FR-009) and independent of how ships are stored (D5);
  string lookup happens outside any per-frame path.
- Max 16 commodities is enforced by list validation (error names the limit). `CargoHold.launch` has 16 slots
  (see data-model); the list, not the hold, decides which ids exist. A caller with an id uses
  `CargoHold.add(_:of:in:)` / `remove(_:of:in:)` (in `Commodity.swift`), which reject an id not in the list
  with `unknownCommodity`, so FR-004 and FR-005 hold on the launch hold too (022 review).

## R4 Overlay cargo text without allocation
- `TextBuffer.write(_: String)` is documented as not per-frame safe. Decision: the overlay pre-encodes
  commodity names once (at construction, from the list) into a `ContiguousArray<UInt8>` ASCII table
  (non-ASCII -> `?`, truncated to 10 columns), and a new `TextBuffer.write(asciiBytes:limit:)` writes from
  a buffer pointer. Numbers use `write(UInt64)`.
- Snapshot: `DebugOverlayShip.Cargo` (capacity, used, free, `InlineArray<16, Int>` amounts, count) built
  from `state.ship.hold`, taken at the 4 Hz refresh from the latest tick, like 015.
- Lines: `hold    12 / 20 t  free 8`, then one line per non-zero commodity `  <name> <tons>`. Worst
  case 17 lines; the check against the text capacity (1,024 chars) is a test.

## R5 Toggle
- Decision: `DebugCargoOption` beside `DebugShipOptions`, `--no-debug-cargo`, in the `#if
  SWIFTSKY_INSTRUMENTATION` block; sets a `showsCargo` flag on `DebugOverlay`. With `--no-debug-overlay`
  there is nothing to show either way. If the list fails to load at startup, the error is logged once, the
  overlay gets an empty name table (amounts, if any, show with `?` names) and the game runs on. That covers a
  missing or bad `commodities.json` inside the resource bundle. A missing resource bundle is not recoverable:
  SwiftPM's generated `Bundle.module` calls `fatalError` when it finds no bundle, as it already does for the
  rendering layer's `ship.png` (022 review). Parsing is a pure struct, tested in the platform tests.

## R6 Release strings check
- Decision: extend the `strings` grep in `release_has_no_instrumentation` with the cargo labels (`hold    `,
  `free`-style label text chosen to be unique, plus `--no-debug-cargo`). Labels are `StaticString`s inside
  `#if SWIFTSKY_INSTRUMENTATION`. The shipped `commodities.json` and its field names are expected in
  Release (it is game data); the check targets overlay labels and the argument only.

## R7 Default capacity and ship init
- Decision: `Ship.init(limits:)` gets `hold: CargoHold = .launch` (capacity 20, from `CargoHold.defaultCapacity`).
  The hold is a `var` on `Ship` (so `state.ship.hold.add(...)` mutates in place); `limits` stays `let`. The
  mid-flight `Ship.init` takes the hold with the same default. Motion code never reads it (FR-012).
