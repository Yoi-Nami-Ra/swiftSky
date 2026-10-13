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
| 4 | 2026-10-07 | **PASS** | `open -n .build/instrumented/Build/Products/Release/swiftSky.app` (Apple silicon Mac, 120 Hz display), read with `/usr/bin/log show`: `allocation counter ready` at 09:07:46, then frame summaries, e.g. `frames=113 skipped=0 dropped=0 mean=0.155665ms worst=0.851792ms budget=8.333333ms ticks=67 allocs=0 allocframes=0 eventallocs=0 gfxallocs=1130`; 144 summaries over the run, every one `allocs=0 allocframes=0`. The debug overlay was on screen (confirmed by the developer). An order clicked during the run logged `order view=(351.562500, 269.644531) world=(-288.437500, 90.355469) … arrives=yes` |
| 5 | 2026-10-07 | **PASS** | `./Scripts/build-instrumented.sh ios`: exit 0 in 34 s, no warning; one path, `…/Release-iphonesimulator/swiftSky.app`; `grep -c dropped=` → 4 |
| 6 | 2026-10-13 | **PASS** | `main` at `319b343`, `./Scripts/build-instrumented.sh ios` (one path, `grep -c dropped=` → 4), iPhone 17 Pro simulator (iOS 27.0), 011 "The method" steps 2–4, no arguments, 60 s idle: `allocation counter ready` at 23:41:23, then 22 frame summaries, e.g. `frames=240 skipped=0 dropped=1 mean=0.356164ms worst=60.720792ms budget=16.666667ms ticks=317 allocs=0 allocframes=0 eventallocs=0 gfxallocs=3360 mainworst=0.000000ms mainover=0`. Every summary `allocs=0 allocframes=0`; the first carries start-up's `eventallocs=4433` and the one dropped frame (60.7 ms), later ones `eventallocs=0`, `gfxallocs=3360` per 120 frames (28 per frame). On relaunch the debug overlay and the ship were drawn (screenshot) |
| 7 | 2026-10-07 | **PASS** | No argument: exit 0, two lines, macOS path first, then iOS |
| 8 | 2026-10-07 | **PASS** | `tvos` and `macos ios`: usage on standard error, exit 64, nothing built |
| 9 | 2026-10-07 | **PASS** | Run from a directory outside the repository with standard error discarded: standard output holds the absolute app path only |
| 10 | 2026-10-07 | **PASS** | `./Scripts/verify.sh`, every stage PASS including `instrumented macOS build carries the instrumentation` and `Release macOS build carries no instrumentation (001 check 27)`. Times on this Mac (Apple silicon), same worktree. **Before** (019 spec commit, two stages fewer): 83 s fully cold (fresh worktree: empty `.build/` and no Xcode derived data), 17 s warm. **After**: 18 s warm (26 s on the first warm run), 88 s with only `.build/instrumented/` and `.build/release-check/` empty, 148 s with all of `.build/` empty (SwiftPM build and both new folders cold; the Debug apps' derived data warm). So a warm run costs about 1 s more, and a cold one about 65 s more: two optimised macOS builds. CI (018) checks out with `actions/checkout`, whose clean step removes ignored files, so every CI run pays the cold figure, well inside 018's 30-minute limit |
| 10 (final) | 2026-10-07 | **PASS** | On the finished branch after merging `main` (016, 018): `./Scripts/verify.sh` every stage PASS, 122 s on the first run after the merge (sources changed), 21 s warm |
| 11 | 2026-10-07 | **PASS** | Both overrides removed from the script: `FAIL instrumented macOS build carries the instrumentation` — `no frame-summary text (dropped=) in …/swiftSky`; `VERIFICATION FAILED`, exit 1. Restored with `git checkout --` |
| 12 | 2026-10-07 | **PASS** | `SWIFTSKY_INSTRUMENTATION` defined unconditionally for Swift and C in `Package.swift`: `FAIL Release macOS build carries no instrumentation (001 check 27)`, printing the two frame-summary format strings it found; `VERIFICATION FAILED`, exit 1. Restored with `git checkout --` |
| 13 | 2026-10-07 | **PASS** | C override line removed: `Undefined symbols for architecture arm64` … `linker command failed`, exit 65, no path printed; line restored, build passes again |
| 14 | 2026-10-07 | **PASS** | `grep -n Profiling` in CLAUDE.md, the 001 plan, `Package.swift` and `Sources/`: 4 hits, all history — CLAUDE.md's 019 entry and its instrumented-build paragraph ("There is no Profiling build any more"), `Package.swift`'s "It replaced an Xcode "Profiling" configuration", and the 001 plan's Complexity Tracking row ("Profiling, never carried the instrumentation … and was removed") |
| 15 | 2026-10-07 | **PASS** | 008 check 12's and 009 check 9's results each end with the 019 note; their check definitions name the instrumented build (with "written as Profiling before 019"); recorded figures unchanged |
| 16 | 2026-10-07 | **PASS** | Quickstarts 001–004, 006–011: every remaining "Profiling" sits beside a 019 pointer to the script (002, 003, 004, 006, 008, 010: "Method since 011 … build it with `Scripts/build-instrumented.sh` (019); the former Profiling build carried no instrumentation (011 R1) and was removed (019)"; 001 check 25; 010 check 11's result; 011 "The method" step 1, which now calls the script). `git diff --stat main` lists only the files in FR-010–FR-012, the project file, the two scripts, `Apps/macOS/Info.plist` (R9) and this feature's own folder (FR-013) |
