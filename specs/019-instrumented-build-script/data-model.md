# Data Model: Replace the Profiling Build with an Instrumented Build Script

No runtime data. The "entities" are the builds and the probes that tell them apart.

| Build | Configuration | Extra settings | Folder | Must contain | Must not contain |
|-------|---------------|----------------|--------|--------------|------------------|
| Debug (unchanged) | Debug | — (package defines the condition for debug) | Xcode default | instrumentation | — |
| Instrumented | Release | `SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION`, `GCC_PREPROCESSOR_DEFINITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION=1`, `CODE_SIGNING_ALLOWED=NO` | `.build/instrumented/` | `dropped=` (FR-008a) | — |
| Plain Release (check) | Release | `CODE_SIGNING_ALLOWED=NO` | `.build/release-check/` | — | `skipped=`, `dropped=`, `worst=`, `SWIFTSKY_INSTRUMENTATION` (FR-008b, 001 check 27) |

Built app paths (relative to the repository root):

- macOS: `<folder>/Build/Products/Release/swiftSky.app`, executable `Contents/MacOS/swiftSky`
- iOS simulator: `<folder>/Build/Products/Release-iphonesimulator/swiftSky.app`, executable `swiftSky`

Build configurations after the change: Debug, Release (project and both app targets).
