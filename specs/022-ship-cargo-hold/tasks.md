# Tasks: Ship Cargo Hold

**Input**: Design documents from `specs/022-ship-cargo-hold/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cargo-and-overlay.md, quickstart.md

**Tests**: Required (constitution II; spec SC-001..SC-004). Written with the code they cover, in the same phase.

**Phasing**: Each phase is sized to be implemented, verified (`./Scripts/verify.sh`, or the named `swift test` targets while iterating) and committed on its own, in dependency order. Phase 3 needs phase 2; phase 1 (the only `Package.swift` edit) and phase 2 do not depend on each other. See Dependencies.

## Format: `[ID] [P?] [Story] Description`

## Phase 1: Commodity data file and loader (US3, P2)

**Goal**: `commodities.json` bundled in `SwiftSkySimulation` and a validated `CommodityList` loaded from it.

**Independent Test**: `swift test --filter CommodityListTests`; then both app targets still build (verify.sh).

- [x] T001 Create the starter list of 6 placeholder commodities (`{ "commodities": [ { "id", "name", "basePrice" } ] }`, ids unique, prices positive whole credits) in Sources/SwiftSkySimulation/Resources/commodities.json
- [x] T002 Add `resources: [.copy("Resources/commodities.json")]` to the `SwiftSkySimulation` target and update the header comments (logic layer imports Foundation in one loader file only; still no package dependencies; decision recorded for SKY-52) in Package.swift
- [x] T003 [US3] Implement `Commodity`, `CommodityList` (`init(decoding: Data) throws`, `load()` via `Bundle.module`, `index(ofID:)`, `subscript`, `count`, 1...16 entries) and `CommodityListError` (`fileMissing`, `malformed(reason)`, `empty`, `tooMany(max)`, `duplicateID`, `emptyName`, `emptyID`, `nonPositivePrice`; no partial list) in Sources/SwiftSkySimulation/Commodity.swift; this is the only logic-layer file importing Foundation (research R1, R3)
- [x] T004 [P] [US3] Write CommodityListTests: bundled file loads (non-empty, unique ids, positive prices), `index(ofID:)` (known id gives its index, an id not in the list gives `nil`: US2 scenario 2), and one test per malformed case (bad JSON, empty list, 17 entries, duplicate id, empty id, empty name, zero and negative price) in Tests/SwiftSkySimulationTests/CommodityListTests.swift
- [x] T005 Run `swift test --filter CommodityListTests`, then `./Scripts/verify.sh` (explicit-dependency import check accepts Foundation, no resource warnings, both app builds find the bundle; research R1 risks) and fix any failure

**Checkpoint**: Commit "SKY-52: commodity list and bundled data file".

---

## Phase 2: Hold rules (US1 + US2, P1) MVP

**Goal**: `CargoHold` value with add/remove rules, rejection reasons and invariants.

**Independent Test**: `swift test --filter CargoHoldTests` (spec US1/US2 scenarios, SC-001..SC-003).

- [x] T006 [US1] Implement `CargoRejection` (`negativeAmount`, `unknownCommodity`, `overCapacity`, `notEnoughStock`) and `CargoHold` (`capacity` clamped >= 0, `commodityCount` 0...16, `InlineArray<16, Int>` amounts, `maxCommodities`, `defaultCapacity` = 20, `.launch`, `used`, `free`, `tons(of:)`, `add(_:of:)`, `remove(_:of:)` returning `CargoRejection?`; check order per data-model; overflow-safe `tons > free`; Equatable; no heap) in Sources/SwiftSkySimulation/CargoHold.swift
- [x] T007 [P] [US1] Write CargoHoldTests for US1: add 5 t then read back, remove 2 t, used/free, fill to exactly capacity then reject 1 t more, 19 used plus 2 rejected, remove more than held rejected, 0 t on a known commodity is `nil` and changes nothing, capacity 0 accepts nothing, in Tests/SwiftSkySimulationTests/CargoHoldTests.swift
- [x] T008 [US2] Extend CargoHoldTests for US2: negative add and remove, unknown index (negative, equal to count, large; on a hold built with a count below 16), 0 t on an unknown commodity is `unknownCommodity`, `Int.max` and `Int.min` amounts are `overCapacity`/`negativeAmount` without wrapping, each rejection leaves the hold equal (SC-003), and a generated sequence of accepted and rejected operations keeping `used <= capacity` and no negative amount (SC-002) in Tests/SwiftSkySimulationTests/CargoHoldTests.swift
- [x] T009 Run `swift test --filter SwiftSkySimulationTests`, then `./Scripts/verify.sh`

**Checkpoint**: Commit "SKY-52: cargo hold rules and tests".

---

## Phase 3: Ship integration (US1, FR-001, FR-012)

**Goal**: The ship carries a hold; motion and autopilot are untouched.

**Independent Test**: simulation tests, including all existing motion and autopilot tests unchanged (SC-007).

- [x] T010 [US1] Add `var hold: CargoHold` to `Ship` with `hold: CargoHold = .launch` on both initialisers (the launch one taking `limits:` and the mid-flight one), included in Equatable; `limits` stays `let`; motion and autopilot code does not read it (research R7) in Sources/SwiftSkySimulation/Ship.swift
- [x] T011 [P] [US1] Write ShipHoldTests: launch ship has capacity 20 and is empty, `state.ship.hold.add(...)` mutates in place, ships differing only in hold are not equal, adding cargo leaves position, velocity, heading, autopilot and planned path bit-equal after identical ticks (FR-012, FR-013: the hold takes an index and knows nothing of ship storage; use StateBits) in Tests/SwiftSkySimulationTests/ShipHoldTests.swift
- [x] T012 Check that `SimulationState` size stays small (no per-frame or per-copy regression; record the new size next to 010's ~4.2 KB figure in specs/022-ship-cargo-hold/research.md R2) and run `./Scripts/verify.sh`; existing motion and autopilot tests must pass without edits

**Checkpoint**: Commit "SKY-52: ship carries a cargo hold".

---

## Phase 4: Debug overlay cargo lines and argument (US4, P2)

**Goal**: Cargo lines under the order lines, `--no-debug-cargo`, allocation-free, absent from plain Release.

**Independent Test**: `swift test --filter SwiftSkyRenderingTests` and `--filter SwiftSkyPlatformTests`; quickstart checks 3, 4, 5.

- [x] T013 [P] [US4] Add `TextBuffer.write(asciiBytes:limit:)` (buffer-pointer write, no allocation, documented per-frame safe) in Sources/SwiftSkyRendering/Text/TextBuffer.swift
- [x] T014 [US4] Add `DebugOverlayShip.Cargo` (`capacity`, `used`, `free`, `count`, `InlineArray<16, Int>` amounts) set by `init(_ state:)` from `state.ship.hold`, the pre-encoded ASCII name table (non-ASCII to `?`, truncated to 10 columns, built once from the list), a `showsCargo` flag on `DebugOverlay`, and the lines `hold    <used> / <capacity> t  free <free>` then `  <name> <tons>` per non-zero commodity (labels as `StaticString` inside `#if SWIFTSKY_INSTRUMENTATION`) in Sources/SwiftSkyRendering/Debug/DebugOverlay.swift (research R4)
- [x] T015 [P] [US4] Write DebugOverlayCargoTests: empty hold shows `0 / 20` and free 20, partial and full holds, only non-zero commodities listed, worst case 16 commodities fits the 1,024-character capacity (17 lines), `showsCargo == false` removes every cargo line and leaves the others unchanged, snapshot taken from the latest tick in Tests/SwiftSkyRenderingTests/DebugOverlayCargoTests.swift
- [x] T016 [US4] Add `DebugCargoOption` (`--no-debug-cargo`, default on, in the `#if SWIFTSKY_INSTRUMENTATION` block beside `DebugShipOptions`) in Sources/SwiftSkyPlatform/GameSurfaceView.swift and pass the option and the loaded list's names to the overlay in the same file's `buildSetup()` (a load failure is logged once at startup, never per frame, and the overlay then gets an empty name table; research R5)
- [x] T017 [P] [US4] Write DebugCargoOptionTests (present, absent, with other arguments, with `--no-debug-overlay`) in Tests/SwiftSkyPlatformTests/DebugCargoOptionTests.swift
- [x] T018 [US4] Extend the `strings` check in `release_has_no_instrumentation` with the unique cargo labels and `--no-debug-cargo` (not the commodity file's field names; research R6), and update the script's header comment, in Scripts/verify.sh
- [x] T019 Run `./Scripts/verify.sh`; then quickstart checks 2 to 5 with `./Scripts/build-instrumented.sh macos` (bundle contains `commodities.json`, overlay shows the hold line by default, `--no-debug-cargo` hides it, frame summary `allocs=0`); results recorded in specs/022-ship-cargo-hold/quickstart.md. The overlay's look and `--no-debug-cargo` were checked by the user on 2026-11-04 ("each works fine").
- [ ] T019a Check by hand with VoiceOver that the overlay still carries no accessibility element (FR-010). Not checked yet.

**Checkpoint**: Commit "SKY-52: debug overlay cargo lines and --no-debug-cargo".

---

## Phase 5: Documentation and close-out

**Purpose**: Repository docs name the new spec, per project convention.

- [x] T020 Update the root CLAUDE.md: add `specs/022-ship-cargo-hold` to the "Built so far" list; add Key locations entries for `Commodity.swift`, `CargoHold.swift` and `Resources/commodities.json` (the one Foundation file in the logic layer, `Bundle.module`), the overlay's cargo lines and `DebugOverlayShip.Cargo`, `TextBuffer.write(asciiBytes:limit:)`, and `--no-debug-cargo` in the debug launch arguments list; amend any sentence saying the logic layer imports only Darwin or "declares no dependencies" if it now misleads in CLAUDE.md
- [x] T021 [P] Mark the spec's Status and the ticket result for SKY-52 per the SKY-21 pattern (record quickstart results; set Status in specs/022-ship-cargo-hold/spec.md and do not touch .tickets/: the coordinator handles ticket status)
- [x] T022 Final `./Scripts/verify.sh` on the finished branch, and `grep -rn "Darwin" Package.swift CLAUDE.md` to confirm no stale statement about logic-layer imports remains

**Checkpoint**: Commit "SKY-52: document the cargo hold".

---

## Dependencies

- Phase 1 first (it edits Package.swift). Phase 2 is independent of phase 1's loader (the hold takes an index) and can follow in either order. Phase 3 needs phase 2. Phase 4 needs phases 1 and 3. Phase 5 last.
- Within a phase: implementation task, then its [P] test tasks, then the run task.

## Parallel opportunities

T004 with T001..T003 once T003's API is fixed; T007 with T006's signature fixed; T013, T015, T017 in different files.

## Implementation strategy

MVP is phase 2 (hold rules, US1 and US2) plus phase 3. Then phase 1 and phase 4 complete the ticket's "done when" (tests; overlay shows used and free). Do phase 5 last.
