# Implementation Plan: A Re-order From Rest Starts in Aligning

**Branch**: `claude/sky-46-autopilot-rest-phase-0b0e2c` (spec 020) | **Date**: 2026-10-18 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/020-autopilot-rest-phase/spec.md`

## Summary

When the autopilot names a tick's phase, a ship whose speed is at most `AutopilotLaw.settleSpeed`
(0.001 u/s) counts as at rest: its velocity has no direction, so it is never "against the motion". That
removes the `flipping` (or `braking`) that a re-order after station keeping reports at once (SKY-46). The
inputs are untouched: only the phase naming reads the new flag, and the hold rule still reads the raw
`ĥ·v` test.

**Technical approach** (decision record in [research.md](./research.md)):
- **Reproduced** (R1): after 600 ticks of station keeping, a re-order straight behind the leftover velocity
  starts `braking`, and one at 120° starts `flipping`.
- **Fix** (R2): `atRest = speed <= settleSpeed`. `namedAgainstMotion = facingAgainstMotion && !atRest` in the
  settled return, the thrusting rule and the coasting rule, and `!atRest &&` in the turning rule's guard.
- **Inputs unchanged** (R3): a probe found the six re-order flights' ship-state fingerprints identical
  before and after. The test pins an input-and-state fingerprint recorded **before** the fix.
- **Tests** (R4): a new suite, `AutopilotRestPhaseTests.swift`. 006's and 010's test files are untouched.
- **Docs** (R5): 006 research R6 and contracts step 8 gain the rest rule, and `CLAUDE.md` gains one sentence.

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: None new. The logic layer still imports only `Darwin` (in `AutopilotLaw.swift`).

**Storage**: N/A.

**Testing**: Swift Testing, headless, in `SwiftSkySimulationTests`, run by `Scripts/verify.sh`.

**Target Platform**: iOS 26+ and macOS 26+. Unchanged. The logic layer is shared.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets. Unchanged.

**Performance Goals**: Unchanged. The change adds one comparison and two `&&` per tick, with no allocation
(006 FR-015) and nothing in the render path.

**Constraints**: Bit-identical inputs and ship states (spec FR-004, FR-007). Pure and deterministic (006
FR-012). Every input stays finite (006 FR-013).

**Scale/Scope**: 1 changed source file (`Sources/SwiftSkySimulation/AutopilotLaw.swift`, about 6 lines). 1 new
test file. 2 changed 006 docs (`research.md` R6, `contracts/autopilot.md` step 8) and `CLAUDE.md`. No change
to `Package.swift`, `verify.sh` or any other layer.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

| Principle | Check | Status |
| --- | --- | --- |
| I. Architecture Discipline | The change is in the logic layer only. No Metal or SwiftUI type is used, and the data flow is unchanged. | PASS |
| II. Test Coverage Discipline | Logic-bearing change with new tests: reproduction, boundary, forward-only, bit-identical fingerprint. They are headless and deterministic, and run by `verify.sh`, which CI runs. | PASS |
| III. Performance & Resource Efficiency | No hot-path allocation, and constant extra work per tick. It is not the render hot path, so no before/after frame measurement is needed beyond `verify.sh`. | PASS |
| IV. Accessibility & Platform UX | No UI change. The overlay only reads the phase. | PASS (N/A) |
| V. Simplicity & YAGNI | One local flag reuses an existing constant. No new type, knob or abstraction. | PASS |

Post-design re-check (after Phase 1): unchanged, all PASS. No Complexity Tracking entries.

## Project Structure

### Documentation (this feature)

```text
specs/020-autopilot-rest-phase/
├── plan.md              # This file
├── research.md          # Phase 0: R1–R5
├── data-model.md        # Phase 1: the rest flag and phase rules
├── quickstart.md        # Phase 1: validation guide
├── contracts/
│   └── phase-rule.md    # Phase 1: the amended step 8 of 006 contracts/autopilot.md
├── checklists/
│   └── requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/SwiftSkySimulation/
└── AutopilotLaw.swift                       # changed: atRest, namedAgainstMotion, turning guard

Tests/SwiftSkySimulationTests/
├── AutopilotRestPhaseTests.swift            # new: 020's suite
├── AutopilotTests.swift                     # unchanged (006); its helpers are reused
└── StateBits.swift                          # unchanged; bits(_:) reused

specs/006-ship-autopilot/
├── research.md                              # R6 gains the rest paragraph
└── contracts/autopilot.md                   # step 8 gains the rest clause
```

**Structure Decision**: The existing three-layer layout. Only the logic layer and its tests change.

## Implementation order

1. Write `AutopilotRestPhaseTests.swift` against the **unfixed** law. Record the leftover velocity bits and the
   two flights' fingerprints and tick counts from it, then confirm that the reproduction tests fail
   (phase-name tests) and that the fingerprint tests pass.
2. Apply the R2 change. All 020 tests pass, the fingerprints are unchanged, and 006's and 010's suites
   pass untouched.
3. Update the docs (R5) and run `./Scripts/verify.sh`.
