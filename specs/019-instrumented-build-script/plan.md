# Implementation Plan: Replace the Profiling Build with an Instrumented Build Script

**Branch**: `019-instrumented-build-script` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `specs/019-instrumented-build-script/spec.md`

## Summary

Remove the Profiling build configuration from `swiftSky.xcodeproj` (three `XCBuildConfiguration` blocks
and their three entries in the configuration lists), which never carried the instrumentation into the
package (011 R1). Add `Scripts/build-instrumented.sh`, a POSIX `sh` script that runs 011 R12's
`xcodebuild` command — Release plus the instrumentation condition for Swift and C on the command line —
for the macOS app, the iOS simulator app, or both, into `.build/instrumented/`, and prints each app's
absolute path on standard output. Extend `Scripts/verify.sh` with two stages: the instrumented macOS
app's executable must contain `dropped=`, and a plain Release macOS app built into
`.build/release-check/` must contain none of 001 check 27's probes. Then reword the documentation
(CLAUDE.md, the 001 plan's Complexity Tracking row, source and `Package.swift` comments, the named
quickstarts), and annotate 008 check 12 and 009 check 9.

## Technical Context

**Language/Version**: POSIX `sh` (as `verify.sh`, run by `/bin/sh` on macOS); Swift 6.4 / Xcode 27
toolchain unchanged.

**Primary Dependencies**: `xcodebuild`, `strings` (Xcode command-line tools). No new dependency.

**Storage**: Build output under `.build/` (git-ignored): `.build/instrumented/`, `.build/release-check/`.

**Testing**: `./Scripts/verify.sh` is the test of this feature (FR-008): its two new stages are the
automated checks. There is no Swift logic to unit-test; the change is build configuration, a shell
script and documentation (Principle II's logic requirement does not apply).

**Target Platform**: macOS host for the script; builds the macOS app and the iOS Simulator app.

**Project Type**: Build tooling for a cross-platform Metal game (iOS + macOS).

**Performance Goals**: `verify.sh` stays a single pre-commit command; its added time is measured and
recorded (SC-005). No runtime code changes, so no frame-time or allocation effect (Principle III n/a).

**Constraints**: No change to Debug or Release settings (FR-002); the zero-warning gate applies to the
new builds (Clarifications); `verify.sh` must not launch an app, boot a simulator or read the log
(FR-009).

**Scale/Scope**: 1 project file edit, 1 new script (~60 lines), ~40 lines added to `verify.sh`, about
20 documentation edits across ~20 files.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.* Constitution v1.1.0.

| Principle | Assessment |
|-----------|------------|
| I. Architecture Discipline | No source code moves; no layer gains a dependency. **PASS** |
| II. Test Coverage Discipline | No new logic. The feature's own behaviour is checked by the single checked-in command, which it extends (FR-008); the deliberate-breakage checks (SC-003) prove the new stages can fail. CI absence stays recorded in 001's plan. **PASS** |
| III. Performance & Resource Efficiency | Restores the instrument Principle III's before/after measurements depend on; no hot-path change, so no measurement is owed. **PASS** |
| IV. Accessibility & Platform UX | No UI. **N/A** |
| V. Simplicity & YAGNI | Removes a build configuration that did nothing; replaces a copied command with one script. The script takes one argument; no options, no configuration knobs. **PASS** (simplifies) |

Post-design re-check (after Phase 1): unchanged — **PASS**. No Complexity Tracking entry is needed.

## Project Structure

### Documentation (this feature)

```text
specs/019-instrumented-build-script/
├── plan.md              # This file
├── research.md          # Phase 0
├── data-model.md        # Phase 1 (the two builds and the probes)
├── quickstart.md        # Phase 1 (validation checks)
├── contracts/
│   └── build-instrumented.md   # The script's command-line contract
└── tasks.md             # /speckit-tasks
```

### Source Code (repository root)

```text
swiftSky.xcodeproj/project.pbxproj   # remove Profiling (3 blocks, 3 list entries)
Scripts/
├── build-instrumented.sh            # NEW (FR-003–FR-007)
└── verify.sh                        # + two stages (FR-008, FR-009)
Package.swift                        # comments only (FR-010)
Sources/SwiftSkyPlatform/GameSurfaceView.swift, FrameTimeWindow.swift, OverlayRefreshSchedule.swift
Sources/SwiftSkyRendering/Debug/DebugOverlay.swift, DebugTextPattern.swift   # doc comments only
CLAUDE.md                            # FR-010
specs/001-metal-app-shell/plan.md    # Complexity Tracking row (FR-010)
specs/{001,002,003,004,006,007,008,009,010,011}-*/quickstart.md   # FR-011, FR-012
```

**Structure Decision**: Existing layout; the new script sits beside `verify.sh` in `Scripts/`.

## Complexity Tracking

No violations.
