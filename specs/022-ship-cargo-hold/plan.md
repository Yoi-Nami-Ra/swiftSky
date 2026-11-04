# Implementation Plan: Ship Cargo Hold

**Branch**: `sky-52-cargo-hold` (spec 022) | **Date**: 2026-11-04 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/022-ship-cargo-hold/spec.md`

## Summary

`Ship` gains a plain-value `CargoHold` (capacity and per-commodity whole tons, inline storage, no heap).
Adds and removes return a `CargoRejection?`-style result and never change a rejected hold. The commodity
list (id, name, base price) is a JSON file bundled as a SwiftPM resource of `SwiftSkySimulation` (D1) and
loaded and validated once by `CommodityList` (the only Foundation user in the logic layer). The debug
overlay gets cargo lines through a new inline `DebugOverlayShip.Cargo` snapshot; `--no-debug-cargo`
hides them (D4a). Nothing in the game changes the hold yet.

## Technical Context

**Language/Version**: Swift 6.2, language mode 6, strict concurrency (`Package.swift`, `layerSettings`)

**Primary Dependencies**: none new. Logic layer imports Darwin (motion) and, in one file, Foundation
(`Bundle.module`, `JSONDecoder`). No package dependency is added; "declares no dependencies" (001) still holds.

**Storage**: bundled data file `Sources/SwiftSkySimulation/Resources/commodities.json`; no save/load (SKY-57)

**Testing**: Swift Testing in `Tests/SwiftSkySimulationTests/`, `SwiftSkyRenderingTests/`,
`SwiftSkyPlatformTests/`; `./Scripts/verify.sh`

**Target Platform**: iOS 26 / macOS 26

**Project Type**: cross-platform game (three layer targets + two Xcode app targets)

**Performance Goals**: no per-frame allocation from the cargo lines (011 check 25, zero allocations); no
change to tick cost

**Constraints**: `SimulationState` is copied every frame, so the hold is a small inline value (about 150
bytes); no Dictionary, Array or String in it. Whole-ton `Int`.

**Scale/Scope**: up to 16 commodities (`CargoHold.maxCommodities`), starter list of 6; one hold

## Constitution Check (v1.1.0)

Gate, before research:

- I Architecture Discipline: PASS. Hold and list are logic-layer values; overlay data flows one way
  (state -> snapshot -> overlay). The only new import is Foundation inside the logic layer, in the loader.
  Flagged in research R1; the layer rule is "no rendering/platform/dependency", which Foundation does not break.
- II Test Coverage: PASS. Tests for hold rules, list validation, snapshot, overlay text, argument parsing.
- III Performance: PASS by design (R2, R4); verified by the allocation counter (quickstart).
- IV Accessibility: PASS. Overlay is already hidden from assistive tech; cargo lines add no control.
- V Simplicity: PASS. No dictionary, no lookup service (D5), fixed starter list; no cargo mass.

Re-check after design: PASS, no violations; Complexity Tracking empty.

## Project Structure

### Documentation

```text
specs/022-ship-cargo-hold/
├── spec.md
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/cargo-and-overlay.md
└── tasks.md        (/speckit-tasks, not created here)
```

### Source Code

```text
Package.swift                                   # resources: [.copy("Resources/commodities.json")] on SwiftSkySimulation; update header comments
Sources/SwiftSkySimulation/
├── Resources/commodities.json                  # new, starter list
├── Commodity.swift                             # new: Commodity, CommodityList (+ validation, load)
├── CargoHold.swift                             # new: CargoHold, CargoRejection
├── Ship.swift                                  # hold: CargoHold (var, init default capacity 20)
Sources/SwiftSkyRendering/
├── Debug/DebugOverlay.swift                    # DebugOverlayShip.Cargo; cargo lines; names table
└── Text/TextBuffer.swift                       # write(asciiBytes:) allocation-free
Sources/SwiftSkyPlatform/GameSurfaceView.swift  # DebugCargoOption (--no-debug-cargo)
Sources/SwiftSkyPlatform/FrameLoop.swift        # pass the option / list names to the overlay
Scripts/verify.sh                               # Release strings check for cargo labels; resource copy check if needed
Tests/SwiftSkySimulationTests/                  # CargoHoldTests, CommodityListTests
Tests/SwiftSkyRenderingTests/                   # DebugOverlayCargoTests
Tests/SwiftSkyPlatformTests/                    # DebugCargoOptionTests
```

**Structure Decision**: extend the existing three layers; no new target.

## Complexity Tracking

None.
