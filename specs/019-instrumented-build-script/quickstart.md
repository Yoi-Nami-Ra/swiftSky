# Quickstart: Replace the Profiling Build with an Instrumented Build Script

Validation guide for [spec.md](./spec.md). The script's interface is in
[contracts/build-instrumented.md](./contracts/build-instrumented.md).

## Prerequisites

- Xcode 27 with the Metal toolchain and the iOS Simulator SDK; a checkout of this branch.
- Read logs with `/usr/bin/log` (in zsh a bare `log` is a shell builtin).

## Checks

| # | Check | Expected | Covers |
|---|-------|----------|--------|
| 1 | `xcodebuild -list -project swiftSky.xcodeproj` | Build Configurations: Debug, Release — nothing else | SC-001, FR-001 |
| 2 | `git diff main -- swiftSky.xcodeproj` | Only Profiling blocks and list entries removed; no Debug or Release line changed | FR-002 |
| 3 | `./Scripts/build-instrumented.sh macos`; `strings -a <app>/Contents/MacOS/swiftSky \| grep -c dropped=` | Exit 0; one absolute path printed; count ≥ 1 | US1, FR-003–FR-006 |
| 4 | Launch the app from check 3 (`open -n <app>`), 15 s, then `/usr/bin/log show --last 1m --style compact --predicate 'subsystem == "com.swiftsky.app" AND category == "frame"'` | `allocation counter ready`, then frame summaries; the debug overlay is drawn | SC-002, US1 |
| 5 | `./Scripts/build-instrumented.sh ios`; `strings -a <app>/swiftSky \| grep -c dropped=` | Exit 0; one path; count ≥ 1 | US1, FR-007 |
| 6 | iOS app from check 5 in the simulator, 011 "The method" steps 2–4 | `allocation counter ready` and frame summaries | SC-002 |
| 7 | `./Scripts/build-instrumented.sh` (no argument) | Both built; two paths, macOS first | FR-004 |
| 8 | `./Scripts/build-instrumented.sh tvos`; `… macos ios` | Usage on standard error, exit 64, nothing built | FR-004 |
| 9 | `./Scripts/build-instrumented.sh macos 2>/dev/null` from `/tmp` | Only the path on standard output | FR-005, FR-006 |
| 10 | `./Scripts/verify.sh`, timed, warm and cold (after `rm -rf .build/instrumented .build/release-check`) | Every stage PASS, including the two new ones; times before and after recorded | SC-003, SC-005, FR-008 |
| 11 | Remove the two overrides from the script, run `./Scripts/verify.sh`, restore | The instrumented stage FAILS and the run reports failure | SC-003, US2 |
| 12 | Define the condition for release in `Package.swift`'s `layerSettings`, run `./Scripts/verify.sh`, restore | The Release stage FAILS and the run reports failure | SC-003, US2 |
| 13 | Remove only the C override from the script, run `./Scripts/build-instrumented.sh macos`, restore | The build fails to link (research R4) | FR-008 |
| 14 | `grep -n Profiling CLAUDE.md specs/001-metal-app-shell/plan.md Package.swift Sources -r` | No hit describes a Profiling build as existing or instrumented | SC-004, FR-010 |
| 15 | Read 008 quickstart check 12 and 009 quickstart check 9 | Each carries the 019 note; results otherwise unchanged | SC-004, FR-011 |
| 16 | `grep -n Profiling specs/{001,002,003,004,006,007,008,009,010,011}-*/quickstart.md` | Each hit is either a 019 note or history pointing to the script | FR-012 |

## Results

| # | Date | Result | Evidence |
|---|------|--------|----------|
| 1 | 2026-10-07 | **PASS** | `xcodebuild -list`: Build Configurations Debug, Release |
| 2 | 2026-10-07 | **PASS** | `git diff --stat`: `project.pbxproj` 58 deletions, 0 insertions — three Profiling blocks and their three list entries; no Debug or Release line touched |
| 3 | 2026-10-07 | **PASS** | `./Scripts/build-instrumented.sh macos`: exit 0 in 35 s from an empty `.build/instrumented/`; standard output is the one line `<repo>/.build/instrumented/Build/Products/Release/swiftSky.app`; `strings -a … \| grep -c dropped=` → 2. The first run warned `No App Category is set for target 'swiftSky (macOS)'` (Release validates the product); fixed in `Apps/macOS/Info.plist` (research R9), no warning since |
| 5 | 2026-10-07 | **PASS** | `./Scripts/build-instrumented.sh ios`: exit 0 in 34 s, no warning; one path, `…/Release-iphonesimulator/swiftSky.app`; `grep -c dropped=` → 4 |
| 7 | 2026-10-07 | **PASS** | No argument: exit 0, two lines, macOS path first, then iOS |
| 8 | 2026-10-07 | **PASS** | `tvos` and `macos ios`: usage on standard error, exit 64, nothing built |
| 9 | 2026-10-07 | **PASS** | Run from a directory outside the repository with standard error discarded: standard output holds the absolute app path only |
| 13 | 2026-10-07 | **PASS** | C override line removed: `Undefined symbols for architecture arm64` … `linker command failed`, exit 65, no path printed; line restored, build passes again |
| 10 | 2026-10-07 | **PASS** | `./Scripts/verify.sh`, every stage PASS including `instrumented macOS build carries the instrumentation` and `Release macOS build carries no instrumentation (001 check 27)`. Times on this Mac (Apple silicon), same worktree. **Before** (019 spec commit, two stages fewer): 83 s fully cold (fresh worktree: empty `.build/` and no Xcode derived data), 17 s warm. **After**: 18 s warm (26 s on the first warm run), 88 s with only `.build/instrumented/` and `.build/release-check/` empty, 148 s with all of `.build/` empty (SwiftPM build and both new folders cold; the Debug apps' derived data warm). So a warm run costs about 1 s more, and a cold one about 65 s more: two optimised macOS builds. CI (018) checks out with `actions/checkout`, whose clean step removes ignored files, so every CI run pays the cold figure, well inside 018's 30-minute limit |
| 11 | 2026-10-07 | **PASS** | Both overrides removed from the script: `FAIL instrumented macOS build carries the instrumentation` — `no frame-summary text (dropped=) in …/swiftSky`; `VERIFICATION FAILED`, exit 1. Restored with `git checkout --` |
| 12 | 2026-10-07 | **PASS** | `SWIFTSKY_INSTRUMENTATION` defined unconditionally for Swift and C in `Package.swift`: `FAIL Release macOS build carries no instrumentation (001 check 27)`, printing the two frame-summary format strings it found; `VERIFICATION FAILED`, exit 1. Restored with `git checkout --` |
