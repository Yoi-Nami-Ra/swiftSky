#!/bin/sh
# swiftSky instrumented build (019, SKY-36).
#
# Builds the app optimised (Release) with the frame instrumentation compiled into every layer: the
# frame summaries, the allocation counter and the debug overlay. This is the build every frame-time and
# allocation measurement is taken with (Principle III, 001 check 25, 011 "The method").
#
# Why a script and not a build configuration: SwiftPM knows only debug and release, so the package
# defines SWIFTSKY_INSTRUMENTATION for debug only, and Xcode builds every package target with its Release
# settings under any configuration other than Debug. A third configuration in the Xcode project (the
# former "Profiling") therefore reached the app module only and carried no instrumentation at all
# (011 research R1). Build settings given on the xcodebuild command line apply to every target, package
# targets included, so Release plus the two settings below is the optimised build with the
# instrumentation (011 research R12). Without the C one the allocation counter's functions do not exist
# and the app does not link.
#
# Usage:  ./Scripts/build-instrumented.sh [ios|macos|both]      (default: both)
#
# Builds into .build/instrumented/ (git-ignored), and prints the absolute path of each built app on
# standard output, macOS first; xcodebuild's own output goes to standard error. Stops at the first failed
# build with its exit status. The iOS app is built for the simulator. Nothing is signed. Contract:
# specs/019-instrumented-build-script/contracts/build-instrumented.md

set -eu

usage() {
    printf 'Usage: %s [ios|macos|both]   (default: both)\n' "$0" >&2
    exit 64
}

[ "$#" -le 1 ] || usage
platform=${1:-both}
case "$platform" in
    ios | macos | both) ;;
    *) usage ;;
esac

cd "$(dirname "$0")/.."
root=$(pwd)
derived="$root/.build/instrumented"

build() {  # $1=scheme  $2=destination  $3=products folder
    xcodebuild build -project swiftSky.xcodeproj -scheme "$1" -configuration Release \
        -destination "$2" -derivedDataPath "$derived" \
        'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION' \
        'GCC_PREPROCESSOR_DEFINITIONS=$(inherited) SWIFTSKY_INSTRUMENTATION=1' \
        CODE_SIGNING_ALLOWED=NO -quiet >&2
    printf '%s\n' "$derived/Build/Products/$3/swiftSky.app"
}

if [ "$platform" != ios ]; then
    build 'swiftSky (macOS)' 'platform=macOS' 'Release'
fi
if [ "$platform" != macos ]; then
    build 'swiftSky (iOS)' 'generic/platform=iOS Simulator' 'Release-iphonesimulator'
fi
