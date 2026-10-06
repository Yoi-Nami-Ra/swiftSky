# Contract: `Scripts/build-instrumented.sh`

```text
Usage: Scripts/build-instrumented.sh [ios|macos|both]
```

| Argument | Builds | Standard output on success |
|----------|--------|----------------------------|
| (none) or `both` | macOS app, then iOS simulator app | two lines: macOS app path, iOS app path |
| `macos` | macOS app | one line: macOS app path |
| `ios` | iOS simulator app | one line: iOS app path |

- Paths are absolute: `<repo>/.build/instrumented/Build/Products/Release/swiftSky.app` and
  `<repo>/.build/instrumented/Build/Products/Release-iphonesimulator/swiftSky.app`.
- Works from any working directory.
- Build: Release, with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION` and
  `GCC_PREPROCESSOR_DEFINITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION=1` and `CODE_SIGNING_ALLOWED=NO`
  (research R1). iOS destination `generic/platform=iOS Simulator`; macOS `platform=macOS`.
- Standard error: `xcodebuild -quiet` output (warnings, errors), and usage text on a usage error.
- Exit status: 0 when every requested build succeeded; `xcodebuild`'s non-zero status on the first
  failed build (nothing printed for it, and a later platform is not built); 64 on a usage error (unknown
  argument, or more than one), nothing built.

## `Scripts/verify.sh` additions

Section "Instrumented and Release builds (macOS)", two stages, both under the existing stage runner
(exit status + zero-warning gate):

1. `instrumented macOS build carries the instrumentation` — runs `Scripts/build-instrumented.sh macos`;
   passes only if `strings -a` on its executable finds `dropped=`.
2. `Release macOS build carries no instrumentation (001 check 27)` — builds Release into
   `.build/release-check/`; passes only if `strings -a` finds none of `skipped=`, `dropped=`, `worst=`,
   `SWIFTSKY_INSTRUMENTATION`.

Neither launches an app, boots a simulator or reads the log (FR-009).
