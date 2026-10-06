# Research: Replace the Profiling Build with an Instrumented Build Script

## R1. The build: Release plus the condition on the command line (from 011 R12)

**Decision**: The script runs, per platform,

```sh
xcodebuild build -project swiftSky.xcodeproj -scheme "<scheme>" -configuration Release \
  -destination "<destination>" -derivedDataPath .build/instrumented \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION' \
  'GCC_PREPROCESSOR_DEFINITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION=1' \
  CODE_SIGNING_ALLOWED=NO -quiet
```

with scheme `swiftSky (macOS)` / destination `platform=macOS`, and `swiftSky (iOS)` /
`generic/platform=iOS Simulator`.

**Rationale**: Command-line build settings apply to every target, package targets included, so the
layers compile `-O` with the condition and the counter's C file with the define (011 R12, verified
there with the build log, `strings` and `nm`). The `$(inherited)` keeps whatever the project and the
package already set. `CODE_SIGNING_ALLOWED=NO` matches `verify.sh`'s Debug builds and lets the script run
on a machine with no development team; a simulator app and a locally launched unsigned Mac app both run
(011's evidence was taken from such builds).

**Alternatives considered**: keeping a Profiling configuration and making it work — SwiftPM has only
debug and release, and Xcode maps an unknown configuration name to release for the package, so no
package-side setting can tell Profiling from Release (011 R1); an `.xcconfig` file — still has to reach
the package targets, which only the command line does; defining the condition for release in the
package — would put the instrumentation in the shipped build (SC-004a).

## R2. One derived-data folder for both platforms

**Decision**: `.build/instrumented/`, shared by both platforms. Products land in
`.build/instrumented/Build/Products/Release/swiftSky.app` (macOS) and
`.build/instrumented/Build/Products/Release-iphonesimulator/swiftSky.app` (iOS simulator).

**Rationale**: Xcode separates products by platform inside one derived-data folder, so one folder holds
both without collision and each stays incremental. `.build/` is already git-ignored, and SwiftPM's own
`.build` content lives in other subfolders, so there is no clash with `swift build`.

**Alternatives considered**: Xcode's default derived data (path is hashed and machine-specific, so the
printed path could not be documented); a folder per platform (no benefit).

## R3. The plain Release build for the negative check

**Decision**: `verify.sh` builds the macOS app in Release, with no overrides other than
`CODE_SIGNING_ALLOWED=NO`, into `.build/release-check/`, then runs `strings -a` on
`Build/Products/Release/swiftSky.app/Contents/MacOS/swiftSky` and fails if any of `skipped=`, `dropped=`,
`worst=`, `SWIFTSKY_INSTRUMENTATION` appears.

**Rationale**: The two Release builds differ only in command-line settings; sharing one folder would make
each rebuild everything the other built. 001 check 27's string probes are what a built product can be
checked for without judgement; its symbol probes and the stripped-ivar note stay a manual check (spec
Assumptions).

## R4. The positive probe

**Decision**: `strings -a` on the instrumented macOS executable must find `dropped=`.

**Rationale**: `dropped=` is in the frame summary's format, compiled only under the Swift condition in
the platform layer (a package target), so it proves the condition reached the package, which is exactly
what Profiling failed to do. The C define needs no probe of its own: `AllocationCounter.c` defines its
functions only under `SWIFTSKY_INSTRUMENTATION`, and the platform layer calls them under the Swift
condition, so a build with the Swift override and without the C override fails to link (Clarifications).

## R5. Output streams and exit status

**Decision**: The script writes only the app paths to standard output (absolute, one per line, macOS
first when both are built), sends `xcodebuild`'s output to standard error, runs under `set -eu`, and
exits with `xcodebuild`'s failure status on a failed build. Usage errors exit 64 (`EX_USAGE`).

**Rationale**: `verify.sh` captures the path with `$(…)`; anything else on standard output would break
that. `-quiet` keeps standard error short but still shows warnings and errors, which `verify.sh`'s stage
runner reads for its warning gate (it captures both streams).

## R6. Removing Profiling from the project

**Decision**: Delete the three `XCBuildConfiguration` blocks named Profiling (`5500…0003`, `6600…0003`,
`7700…0003`) and their entries in the three `XCConfigurationList`s. Leave every Debug and Release block
untouched; `defaultConfigurationName` is already Release.

**Rationale**: That is all Profiling consists of; there are no shared schemes (`xcshareddata` is absent),
so no checked-in scheme refers to it. `xcodebuild -list` confirms the result (SC-001).

## R7. Wording

**Decision**: "Debug and instrumented Release builds" (or "Debug builds and the instrumented Release
build (`Scripts/build-instrumented.sh`)") where documents said Debug/Profiling. The annotation for 008
check 12 and 009 check 9, and for any quickstart result that says it was run on a Profiling build:

> *Note (019)*: a Profiling build carried no package instrumentation (011 R1), so frame figures recorded
> from one cannot have come from the instrumented build. Any future measurement uses
> `Scripts/build-instrumented.sh`.

Statements already saying "a Profiling build carries no instrumentation (011 R1)" are true history and
are reworded only to name the script as the method. Historical spec, research, data-model, task and
contract files are left alone (FR-013).

## R8. Time added to `verify.sh`

**Decision**: Measured on the finished branch, warm and cold, and recorded in the quickstart (SC-005).
Expected: two optimised macOS builds; the first run after a clean checkout costs most, later runs are
incremental.

## R9. The macOS app needs an application category (found in T005)

**Finding**: The first Release build of the macOS app warned `No App Category is set for target
'swiftSky (macOS)'`. Release validates the product (`VALIDATE_PRODUCT`), Debug does not, which is why the
Debug builds in `verify.sh` never showed it. `verify.sh` fails a stage on any `warning:` line, so both new
stages would fail on it.

**Decision**: Add `LSApplicationCategoryType = public.app-category.games` to `Apps/macOS/Info.plist`.

**Rationale**: It is the correct value for this app and the warning's own remedy; no build setting
changes (FR-002). **Alternative rejected**: a second exemption in `verify.sh`'s warning filter — it would
hide a real, one-line product defect behind tooling.
