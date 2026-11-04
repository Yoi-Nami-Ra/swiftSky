# Implementation Plan: iOS GPU Frame Capture Check

**Branch**: `021-ios-gpu-frame-capture` | **Date**: 2026-10-18 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/021-ios-gpu-frame-capture/spec.md`

## Summary

Close the iOS half of 001's quickstart checks 4 (a shader-backed draw covers the surface, SC-019,
FR-002a) and 5 (the quad's pipeline and vertex buffer are built once, FR-002b) by observing the running
Debug iOS app in the simulator with lldb, then recording what was seen in
`specs/001-metal-app-shell/quickstart.md`. No app code changes. Amended 2026-10-18: the hand capture
in Xcode's GPU debugger is replaced by `probe.sh`, which runs unattended (spec Clarifications).

The evidence is chosen so it cannot pass by accident (research R2, R3): the pass clears to black and
the quad draws black, so colour proves nothing. Check 4 rests on one quad draw per presented frame, the
sampled draw's pipeline, buffer contents and arguments, and no viewport change. Check 5 rests on zero
creation calls while frames run and equal object addresses in two samples 5 s apart.

## Technical Context

**Language/Version**: Swift 6 / Metal Shading Language (existing code; nothing is written)

**Primary Dependencies**: Xcode 27.0 (27A266a): `xcodebuild`, `xcrun simctl`, `xcrun lldb`

**Storage**: N/A (the record is Markdown in 001's quickstart)

**Testing**: `probe.sh`, by the procedure in [quickstart.md](quickstart.md); `./Scripts/verify.sh`
stays green because no code changes

**Target Platform**: iOS, in the iOS Simulator (R1)

**Project Type**: mobile/desktop game (iOS and macOS apps over three Swift package layers)

**Performance Goals**: N/A

**Constraints**: No change to `Sources/` (spec FR-008); no capture files or screenshots committed
(FR-005); the observation is made with lldb, unattended (FR-002)

**Scale/Scope**: Two quickstart checks, iOS only; macOS is SKY-19 (since done: `probe-macos.sh`, with the
shared part of both probes moved to `probe-common.sh`)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.* Constitution v1.1.0.

| Principle | Assessment |
|-----------|------------|
| I. Architecture Discipline | No source code changes; no layer gains a dependency. **PASS** |
| II. Test Coverage Discipline | No new logic. Visual/render verification is exempt from automated tests; the check is a checked-in script, `probe.sh`, outside the test command because it needs a simulator and a debugger. **PASS** |
| III. Performance & Resource Efficiency | Observes, without changing, that the quad's pipeline and buffer are not rebuilt per frame (no hot-path allocation, FR-002b). **PASS** |
| IV. Accessibility & Platform UX | No UI. **N/A** |
| V. Simplicity & YAGNI | Nothing is added to the app; one script of lldb commands, no framework. **PASS** |

Post-design re-check (after Phase 1): unchanged — **PASS**. No Complexity Tracking entry is needed.

## Project Structure

### Documentation (this feature)

```text
specs/021-ios-gpu-frame-capture/
├── plan.md              # This file
├── research.md          # Phase 0: what counts as evidence, how the probe runs
├── data-model.md        # Phase 1: the probe run and the check record
├── quickstart.md        # Phase 1: running the probe and reading its output
├── probe.sh             # The lldb probe (build, launch, attach, count, sample)
├── probe-macos.sh       # Its macOS twin (SKY-19)
├── probe-common.sh      # The lldb runs and checks both probes share (SKY-19)
├── capture-notes.md     # The observed values, filled from the probe output
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Phase 2 (/speckit-tasks)
```

No `contracts/`: the feature exposes no interface.

### Source Code (repository root)

```text
specs/001-metal-app-shell/
└── quickstart.md        # The only file the feature changes outside its own directory:
                         # checks 4 and 5 records, the open-checks summary

Sources/SwiftSkyRendering/      # Read, not changed: the evidence's subject
├── FullscreenQuad.swift        # pipeline "swiftSky.fullscreenQuad", buffer "swiftSky.quadVertices"
├── Renderer.swift              # quad built once in init (line 107), drawn first each frame (194–196)
└── Shaders.metal               # swiftsky_quad_vertex / swiftsky_quad_fragment

.tickets/18.yaml                # Status at the end (done, or a filed bug on FAIL)
```

**Structure Decision**: Documentation-only change. The record goes where 001 tracks its checks, so
the next reader of that quickstart sees the result beside the check it closes.

## Complexity Tracking

No violations.
