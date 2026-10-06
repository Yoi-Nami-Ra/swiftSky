# Feature Specification: Replace the Profiling Build with an Instrumented Build Script

**Feature Branch**: `019-instrumented-build-script`

**Created**: 2026-10-07

**Status**: Draft

**Input**: User description: "SKY-36 — Replace the Profiling build with an instrumented script"
(`.tickets/36.yaml`). The Profiling configuration is meant to be an optimised build with the frame
instrumentation compiled in (001 research R12, FR-021e), but it carries none of it: the package defines
the instrumentation condition for its debug configuration only, and Xcode builds every package target
with its Release settings when the app uses Profiling, so the condition reaches the app module only
(011 research R1). 011 research R12 has the working method — a Release build with the condition added on
the build command line, which reaches the package targets too. Remove Profiling, add a script that makes
that build, guard it in the verification script, and bring the documentation in line.

## Overview

The project promises developers an **optimised build with the frame instrumentation compiled in**: the
frame summaries, the allocation counter and the debug overlay, in code built the way it ships. It is the
build every performance measurement (Principle III's before/after figures, 001 check 25) is meant to be
taken with. Today that promise is a build configuration named Profiling, and it is broken: a Profiling
binary contains no frame summary, no allocation counter and no debug overlay. The one working way to get
the build (011 R12) is a long command that each developer has to copy from a research note.

This feature replaces the broken configuration with a checked-in command that makes the working build,
and makes the verification script prove — on every run — that the build carries the instrumentation and
that plain Release still carries none. The documentation stops sending readers to "Profiling builds".

Out of scope: what the instrumentation measures; adding any instrumentation to plain Release; re-running
008 check 12 and 009 check 9; rewording the historical spec, research, plan (other than 001's
Complexity Tracking row), data-model, task and contract files of earlier features, which stay as the
record of what was believed when they were written.

### Relationship to earlier specs

- **Corrected**: 001 FR-021e's "debug and profiling builds" is now met by Debug and by the instrumented
  Release build that the new script makes. 001's plan, Complexity Tracking row for "a third build
  configuration", is reworded to the script.
- **Automated**: 001 check 27 (a Release build carries no instrumentation, SC-004a) becomes part of the
  verification script for the macOS app, alongside its new positive counterpart.
- **Replaced**: 011 quickstart's "The method", step 1 (the hand-written build command), now calls the
  script. The rest of the method is unchanged.
- **Annotated, not re-run**: 008 quickstart check 12 and 009 quickstart check 9.

## Clarifications

### Session 2026-10-07

- Q: Where does the script build? → A: `.build/instrumented/` (repository root, already git-ignored), one
  folder for both platforms; the apps land under its `Build/Products/Release/` and
  `Build/Products/Release-iphonesimulator/` (FR-005).
- Q: Where does `verify.sh` build the plain Release app for the negative check? → A: In a separate fixed
  folder, `.build/release-check/`, so the two Release builds with different settings never overwrite each
  other and each stays incremental (FR-008).
- Q: What does the positive check look for? → A: `dropped=` in the executable only. A build with the
  Swift condition but not the C one does not link (the counter's functions exist only under the C
  define), so the C override is guarded by the build itself (FR-008).
- Q: What does the script write where? → A: Only the app paths on standard output, one per line; the
  build's own output goes to standard error, kept quiet, so a caller can capture the paths (FR-006).
- Q: Does `verify.sh`'s zero-warning gate apply to the two new builds? → A: Yes; they run as ordinary
  stages, so a compiler warning in either fails the run, as for every other build (FR-008, SC-015 of 001).

## User Scenarios & Testing *(mandatory)*

The users of this feature are the developers building swiftSky. Players see no change.

### User Story 1 - Developer makes an optimised instrumented build with one command (Priority: P1)

A developer who needs to measure frame time or allocations runs one checked-in command, naming the
platform (iOS, macOS, or both by default). It builds the app optimised, with the instrumentation compiled
into every layer, into a fixed folder, and prints where each built app is. The developer launches it and
reads the frame summaries, `allocation counter ready`, and the debug overlay, as the method in 011
describes.

**Why this priority**: This is the build every performance check depends on; today it exists only as a
copied command.

**Independent Test**: Run the command for macOS, check that it ends successfully and prints an app path,
then check that the app's executable contains the frame-summary text and launch it to see the overlay
and the log lines.

**Acceptance Scenarios**:

1. **Given** a clean checkout, **When** the developer runs the command with `macos`, **Then** it builds
   the macOS app optimised with the instrumentation in every layer, prints the path of the built app, and
   exits 0.
2. **Given** that macOS app, **When** its executable is inspected, **Then** it contains the frame-summary
   text (`dropped=`); **and when** it is launched, **Then** the log shows `allocation counter ready` and
   frame summaries, and the debug overlay is drawn.
3. **Given** a clean checkout, **When** the developer runs the command with `ios`, **Then** it builds the
   iOS app for the simulator the same way, prints its path, and exits 0; that app's executable contains
   `dropped=`.
4. **Given** no argument, **When** the command runs, **Then** it builds both and prints both paths.
5. **Given** an argument other than `ios`, `macos` or `both`, **When** the command runs, **Then** it
   builds nothing, prints its usage, and exits non-zero.
6. **Given** a build fails, **When** the command ends, **Then** it exits non-zero and prints no app path
   for the failed platform.

---

### User Story 2 - The verification script proves both builds are right (Priority: P2)

A developer runs the single verification command. Besides its existing stages, it now makes the
instrumented macOS build and checks the instrumentation is in it, and makes a plain Release macOS build
and checks the instrumentation is not. Either check failing fails the run.

**Why this priority**: Without a guard, the instrumented build can silently break again, exactly as
Profiling did; but the guard needs US1's command to exist.

**Independent Test**: Run the verification command and see both new stages pass; remove the overrides
from the build command once, see the positive stage fail, then restore them.

**Acceptance Scenarios**:

1. **Given** the current code, **When** the verification command runs, **Then** a stage builds the
   instrumented macOS app and passes because its executable contains `dropped=`, and a stage builds the
   Release macOS app and passes because its executable contains none of 001 check 27's probes.
2. **Given** the instrumentation overrides removed from the build command, **When** the verification
   command runs, **Then** the positive stage fails and the run reports failure.
3. **Given** instrumentation leaking into plain Release (for example the condition defined for release
   in the package), **When** the verification command runs, **Then** the negative stage fails and the
   run reports failure.

---

### User Story 3 - The documentation names one way to make the build (Priority: P3)

A developer reading CLAUDE.md, a source comment, the 001 plan or a quickstart finds "Debug and
instrumented Release builds" where it said "Debug/Profiling", and finds that the recorded results which
claimed a Profiling build (008 check 12, 009 check 9) carry a note saying such a build had no package
instrumentation, pointing to the script for any future measurement.

**Why this priority**: Wrong documentation sends the next measurement to a build that cannot take it;
but it can only point to the script once the script exists.

**Independent Test**: Search the named documents for "Profiling" and read each remaining hit.

**Acceptance Scenarios**:

1. **Given** the updated repository, **When** CLAUDE.md, the 001 plan, the source files and
   `Package.swift` are searched for "Profiling", **Then** no hit describes Profiling as a build that
   exists or carries instrumentation.
2. **Given** 008 quickstart check 12 and 009 quickstart check 9, **When** they are read, **Then** each
   carries the note of FR-011, and their recorded results are otherwise unchanged.
3. **Given** the quickstarts of 001–004, 006, 007, 010 and 011, **When** they are read, **Then** a
   statement that a check was run on a Profiling build carries the note of FR-012, and every other
   mention follows FR-010's wording.

### Edge Cases

- **Xcode or the Metal toolchain missing**: the script fails as `xcodebuild` fails, non-zero, with its
  output visible; the verification script's existing Metal preflight already stops the run first.
- **No iOS simulator runtime installed**: building for the generic simulator destination needs the SDK,
  not a booted simulator, so `ios` still builds; if the SDK is missing, the script fails non-zero.
- **The fixed build folder already holds an earlier build**: it is reused; an incremental build is
  correct because the overrides are on every build command, so nothing stale from a different setting
  survives (Xcode rebuilds targets whose settings changed).
- **Run from another directory**: the script works from any working directory, like `verify.sh`.
- **Code signing**: the script builds without signing for the macOS app as `verify.sh` does, so it runs
  on a machine without a development team; a simulator app needs no signing.
- **Leftover `Profiling` folders** in a developer's own derived data: harmless and not touched.
- **A user scheme selecting Profiling** on a developer's machine: schemes are not shared; such a scheme
  falls back to an existing configuration once Profiling is gone; nothing checked in depends on it.

## Requirements *(mandatory)*

### Functional Requirements

**The build configurations**

- **FR-001**: The Xcode project MUST have exactly two build configurations, Debug and Release, at the
  project level and for both app targets. The Profiling configuration MUST be removed entirely.
- **FR-002**: Removing Profiling MUST NOT change any setting of Debug or Release.

**The instrumented build command**

- **FR-003**: A checked-in script, `Scripts/build-instrumented.sh`, MUST build the app in the Release
  configuration with the instrumentation condition added for Swift and for C on the build command line,
  as 011 research R12 describes, so it reaches every package target as well as the app.
- **FR-004**: It MUST take the platform as its only argument — `ios`, `macos` or `both` — and default to
  `both` when none is given. Any other argument, or more than one, MUST print usage and exit non-zero
  without building.
- **FR-005**: It MUST build into one fixed build folder, `.build/instrumented/` at the repository root
  (ignored by git), for both platforms and on every run, so that the path of each built app is
  predictable.
- **FR-006**: On success it MUST print the absolute path of each built app, one per line, on standard
  output and nothing else there, and exit 0. The build's own output MUST go to standard error, kept
  quiet. On any build failure it MUST exit non-zero.
- **FR-007**: The iOS build MUST target the iOS Simulator (generic destination, no booted simulator
  needed); the macOS build MUST target the host Mac. Neither needs a signing identity.

**The verification guard**

- **FR-008**: `Scripts/verify.sh` MUST, as two stages that each fail the run:
  (a) build the instrumented macOS app with the script and pass only if its executable contains the
  frame-summary text `dropped=`; and
  (b) build the plain Release macOS app, in its own fixed folder `.build/release-check/`, and pass only if
  its executable contains none of 001 check 27's probes (`skipped=`, `dropped=`, `worst=`,
  `SWIFTSKY_INSTRUMENTATION`).
  Both stages are ordinary stages: exit status and the zero-warning gate apply. The positive check needs
  no probe for the C override: without it the counter's functions do not exist and the app does not
  link.
- **FR-009**: The verification script MUST NOT launch either app, boot a simulator or read the system
  log; both checks inspect the built executable only.

**Documentation**

- **FR-010**: CLAUDE.md, the 001 plan's Complexity Tracking row for the third build configuration, the
  source and `Package.swift` comments, and the quickstarts named in FR-012 MUST say "Debug and
  instrumented Release builds" (or an equivalent naming the script) where they now say Debug/Profiling,
  and MUST NOT describe a Profiling build as existing or as carrying instrumentation.
- **FR-011**: 008 quickstart check 12 and 009 quickstart check 9 MUST each carry a note that a Profiling
  build carried no package instrumentation, so the recorded frame figures cannot have come from the
  instrumented build, and that any future measurement uses `Scripts/build-instrumented.sh`. Their
  results MUST NOT be re-run or rewritten.
- **FR-012**: In the quickstarts of 001–004, 006, 007, 010 and 011, a statement that a check *was run*
  on a Profiling build MUST carry a short note as in FR-011; every other mention of Profiling there MUST
  follow FR-010's wording. 011's "The method" step 1 MUST call the script instead of spelling out the
  build command.
- **FR-013**: Historical spec, research, data-model, plan (other than 001's row), tasks and contract
  files MUST be left as they are.

### Key Entities

- **Instrumented build**: the Release configuration plus the instrumentation condition on the build
  command line; optimised; carries the frame summaries, the allocation counter and the debug overlay.
- **Plain Release build**: the shipped configuration; carries none of the instrumentation (SC-004a).
- **Frame-summary text**: `dropped=`, the probe that tells the two apart in a built executable.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Listing the project's build configurations shows exactly two: Debug and Release.
- **SC-002**: One command, with no further arguments, produces an optimised macOS app whose executable
  contains the frame-summary text, and whose launch shows `allocation counter ready` and frame summaries
  in the log; the same holds for the iOS app in the simulator.
- **SC-003**: The verification command passes on the finished branch, and fails in each of the two
  deliberate breakages (overrides removed; instrumentation leaking into Release) — each tried once and
  restored.
- **SC-004**: No document named in FR-010 still describes a Profiling build as existing or as carrying
  instrumentation, and both annotated checks carry the note.
- **SC-005**: The verification command's added time is recorded; it stays a single command a developer
  can run before every commit.

## Assumptions

- The ignored build output folder (`.build/`) is a suitable home for the fixed build folder; it is
  already ignored by git.
- Building the plain Release app in `verify.sh` alongside the instrumented one is acceptable in time; the
  existing Debug builds stay as they are.
- Only the macOS app is guarded in `verify.sh`, as the ticket says; the iOS instrumented build is
  checked by hand (SC-002).
- The iOS done-check that needs a running simulator and its log is left to the developer.
- The probe set for the negative check is 001 check 27's strings; symbol probes stay a manual check.
