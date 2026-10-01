# Implementation Plan: Click to Order the Ship on macOS

**Branch**: `009-click-to-order-macos` | **Date**: 2026-10-01 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-click-to-order-macos/spec.md`

## Summary

A primary click on the macOS game surface becomes the ship's move order, through 008's order request
unchanged. An `NSClickGestureRecognizer` (primary button, one click) on `MetalSurfaceView` reads the
click in the view's bottom-left points. It ignores Control-clicks, flips the position into top-left view
space with a new pure `ClickPosition` helper against `bounds.height`, and posts
`.moveOrderRequested`. `acceptsFirstMouse(for:)` stays `false`, now explicitly, so a click on an
inactive window only activates it.

**Technical approach**: R1 (recogniser and Control filter), R2 (inactive windows), R3 (flip on the main
thread, pure and tested), R4 (tests). Nothing after the post changes (R5). See [research.md](./research.md).

## Technical Context

**Language/Version**: Swift 6.4, Swift 6 language mode, strict concurrency. Unchanged.

**Primary Dependencies**: Apple frameworks only. AppKit's `NSClickGestureRecognizer` in the platform
layer (already imports AppKit). No third-party dependencies.

**Storage**: N/A.

**Testing**: Swift Testing, headless: a new `ClickPositionTests` suite in `SwiftSkyPlatformTests`. Run
through `Scripts/verify.sh`. Click recognition, modifiers, inactive windows and VoiceOver are verified
in the quickstart.

**Target Platform**: macOS 26+. iOS unchanged.

**Project Type**: Cross-platform application with shared layer libraries and thin app targets.
Unchanged.

**Performance Goals**: Frame budget unchanged (001 SC-003). Nothing per frame is added (R6).

**Constraints**: No change to the order request, the frame loop, `SurfaceEvent`, the logic or rendering
layers, or iOS code (FR-007). The main thread never blocks.

**Scale/Scope**: New: `Sources/SwiftSkyPlatform/ClickPosition.swift`,
`Tests/SwiftSkyPlatformTests/ClickPositionTests.swift`. Changed: `MetalSurfaceView.swift` (macOS
block only), `CLAUDE.md`, `.tickets/11.yaml`.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Evaluated against `.specify/memory/constitution.md` v1.1.0.

### Initial evaluation (pre-design)

| Principle | Gate | Status |
|-----------|------|--------|
| I. Architecture Discipline | Layers separate; unidirectional flow | **PASS**. Input is recognised in the platform layer behind `#if os(macOS)`; the shared request and everything after it are untouched (FR-007). |
| II. Test Coverage Discipline | Tests for non-trivial logic; headless; one command | **PASS**. The flip, the only new logic, is pure and tested together with 008's conversion (FR-008). |
| III. Performance & Resource Efficiency | Budget; no hot-path allocation; before/after | **PASS**. No per-frame work added (R6). Before/after is quickstart check 9. |
| IV. Accessibility & Platform UX | HIG input; VoiceOver | **PASS**. The standard click recogniser, secondary-click convention and inactive-window convention follow the macOS HIG (R1, R2). VoiceOver's description is unchanged; VoiceOver ordering is out of scope (FR-009). |
| V. Simplicity & YAGNI | Simplest solution | **PASS**. One recogniser, one pure function, one explicit override. |

**Gate result: PASS.** Proceed to Phase 0.

### Post-design re-evaluation (after Phase 1)

| Principle | Status after design | Change from initial |
|-----------|--------------------|---------------------|
| I | **PASS** | Confirmed. `ClickPosition` imports no AppKit (R3). |
| II | **PASS** | Confirmed. C1–C5 headless; C6–C10 review and quickstart. |
| III | **PASS** | Confirmed. |
| IV | **PASS** | Confirmed. |
| V | **PASS** | R3 rejects flipping the view and changing the request; R1 rejects custom mouse handling. |

**Gate result: PASS.**

## Project Structure

### Documentation (this feature)

```text
specs/009-click-to-order-macos/
├── plan.md              # This file
├── research.md          # Phase 0: decision record R1–R6
├── data-model.md        # Phase 1: ClickPosition, the click
├── quickstart.md        # Phase 1: validation guide, checks 1–10, evidence
├── contracts/
│   └── click-to-order.md  # API and guarantees C1–C10
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Sources/SwiftSkyPlatform/
├── ClickPosition.swift          # NEW: (x, h − y), pure, platform-neutral (R3)
└── MetalSurfaceView.swift       # CHANGED: macOS click recogniser, Control filter, acceptsFirstMouse (R1, R2)

Tests/SwiftSkyPlatformTests/
└── ClickPositionTests.swift     # NEW: C1–C5

CLAUDE.md                        # CHANGED: mention spec 009 and the click
.tickets/11.yaml                 # CHANGED: status done at the end
```

**Structure Decision**: One file per concept in the platform layer, as 008's `MoveOrderRequest.swift`.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| **No CI pipeline**, recorded as Principle II (v1.1.0) requires | There is still no git remote | Not a violation under v1.1.0. `Scripts/verify.sh` remains the single command. |
