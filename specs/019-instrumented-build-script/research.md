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
`CODE_SIGNING_ALLOWED=NO` (and, since R10, `CLANG_MODULES_PRUNE_AFTER=0`), into `.build/release-check/`,
then runs `strings -a` on `Build/Products/Release/swiftSky.app/Contents/MacOS/swiftSky` and fails if
any of `skipped=`, `dropped=`, `worst=`, `SWIFTSKY_INSTRUMENTATION` appears.

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

## R10. Xcode prunes the explicit-module caches under a warm build (found 2026-10-14)

**Finding**: On 2026-10-14, at `d1b36e6`, `./Scripts/verify.sh` failed on this Mac: both stages of this
feature exited 0 but printed lines like
`warning: <repo>/.build/release-check/SDKExplicitPrecompiledModules/AppKit-….pcm: No such file or directory`.
Both folders had been filled on 2026-10-07, and no source file had changed since. Afterwards
`.build/release-check/SDKExplicitPrecompiledModules/` held only a fresh `modules.timestamp`.
`rm -rf .build/instrumented .build/release-check` fixed it. The cause, from swift-build's source and
reproduced here (quickstart check 17):

- At the end of every build, swift-build (`BuildOperation.pruneExplicitPrecompiledModules`) prunes the
  folder's explicit-module caches, `SDKExplicitPrecompiledModules/` and
  `Build/Intermediates.noindex/{,Swift}ExplicitPrecompiledModules/`, through libclang's module-cache
  prune. At most once per `CLANG_MODULES_PRUNE_INTERVAL` (Xcode: 86,400 s, a day, measured from
  `modules.timestamp`), it deletes every `.pcm` whose access time is older than
  `CLANG_MODULES_PRUNE_AFTER` (Xcode: 345,600 s, four days).
- A build with nothing to compile reads no cached `.pcm`, and APFS updates a file's access time on a
  read only while it is not later than the modification time, so a cached module's access time stays
  near its first use however often it is used afterwards. A folder built only from an unchanged checkout
  is therefore pruned whole by the first build four days after it was filled.
- The object files' debug information names those `.pcm` files by absolute path. Release makes a dSYM
  (`DEBUG_INFORMATION_FORMAT = dwarf-with-dsym`). The next build rebuilds the project's own pruned
  modules and relinks, but does not rebuild the SDK's, so `dsymutil` warns once per missing module (19
  for the macOS app), on that build and every later one: nothing restores them. The build exits 0, and
  `verify.sh` fails the stage on its `warning:` lines. Debug makes no dSYM, which is why the Debug
  stages never showed it.

CI is not affected: `actions/checkout` removes ignored files, so every CI run builds both folders cold.

**Decision**: Both builds pass `CLANG_MODULES_PRUNE_AFTER=0` on the `xcodebuild` command line
(`Scripts/build-instrumented.sh` for the instrumented one, `verify.sh` for plain Release). swift-build
skips the prune when the value is not positive (`guard pruneAfter > 0`). Clang also receives it, as
`-fmodules-prune-after=0`, which concerns only its implicit-module cache. The setting governs cache
upkeep, not the code compiled, and adds no warning. It changes the compile commands, so the first build
after it rebuilds each folder once (37 s for `verify.sh`, check 10), which also repairs a folder that
was already pruned (check 17).

**Cost**: Old module variants are no longer removed. One set is about 130 MB per folder; a new set
appears only when the compilation context changes (an Xcode or SDK update, a changed setting).
`rm -rf .build/instrumented .build/release-check` reclaims the space at the price of one cold run.

**Alternatives rejected**:
- *Clean before every build*: makes every warm run cold, about 55 s more each time (check 10).
- *Detect the warning and rebuild*: a second exemption in the warning gate keyed to one tool's message,
  and a cold run whenever it fires; `build-instrumented.sh` users would still see the warnings, and the
  dSYM would still lack the modules' type information.
- *Refresh the access times before each build* (`touch -a` on every cached `.pcm`): would work, but
  reaches into the build system's cache from outside on every run; the build setting is simpler.
- *A larger `CLANG_MODULES_PRUNE_AFTER`*: only postpones the failure.
- *Turning off explicit modules, or the dSYM*: changes how the measured and the checked builds are
  made, only to hide the symptom.
