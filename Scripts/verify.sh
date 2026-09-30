#!/bin/sh
# swiftSky verification (FR-019a).
#
# Builds every destination and runs the headless test suite. Takes no arguments and needs no setup
# beyond a clean clone. Exits non-zero if any stage fails, so this file can become a CI job body
# verbatim once the repository has a remote — which is exactly what constitution v1.1.0's Principle II
# requires as the substitute for CI until then.
#
# Usage:  ./Scripts/verify.sh

set -eu

cd "$(dirname "$0")/.."

status=0
pending=""

section() {
    printf '\n\033[1m==> %s\033[0m\n' "$1"
}

fail() {
    printf '\033[31mFAIL\033[0m %s\n' "$1"
    status=1
}

pass() {
    printf '\033[32mPASS\033[0m %s\n' "$1"
}

# ---------------------------------------------------------------------------
# Stage runner. A stage passes only if it exits 0 AND emits no `warning:` line.
#
# The warning gate is what enforces SC-015's "zero strict-concurrency warnings". It lives here rather
# than as `.treatAllWarnings(as: .error)` in Package.swift because that setting cannot coexist with the
# `-suppress-warnings` Xcode passes to package targets — it broke both app builds outright and, in
# doing so, hid the very concurrency violations it was added to catch. See the SC-015 note in
# Package.swift. This gate covers the SwiftPM and xcodebuild paths alike, which that setting could not.
#
# Matching is case-sensitive on purpose: compiler diagnostics are lowercase `warning:`, while
# xcodebuild's own operational chatter ("WARNING: Using the first of multiple matching destinations")
# is uppercase and is not a code defect.
#
# ONE build-system diagnostic is exempt, matched as a whole line and for this bundle only:
#
#   warning: missing creator for mutated node: ('<repo>/.build/out/Products/<config>/swiftSky_SwiftSkyRendering.bundle/Contents/MacOS')
#
# It comes from swiftbuild (Xcode 27.0 RC 27A266a, Swift 6.4), not the compiler, and it is not a code
# defect. A resource bundle whose Sources phase compiles `.metal` is treated as a binary-bearing product,
# so its CodeSign task declares $(EXECUTABLE_FOLDER_PATH) — Contents/MacOS — as a node it mutates. A
# resource bundle has no executable, so no task creates that folder, and swiftbuild warns. It is not
# caused by how Package.swift declares the resource: a minimal package with one `.metal` resource warns
# identically whether the file is implicit or `.process`-ed, and one with a `.txt` resource does not.
# The only source-level ways to avoid it change the shader pipeline itself (ship a precompiled
# .metallib, or compile shader source at runtime), which is not worth trading for a build-log line.
# Upstream fix swiftlang/swift-build#1789 was closed unmerged. Delete this exemption once a toolchain
# builds clean without it. See quickstart.md check 28.
KNOWN_BUILD_SYSTEM_WARNING="^warning: missing creator for mutated node: \('[^']*/swiftSky_SwiftSkyRendering\.bundle/Contents/MacOS'\)\$"

run_stage() {
    label=$1
    shift
    log=$(mktemp)
    if "$@" >"$log" 2>&1; then
        warnings=$(grep 'warning:' "$log" | grep -Ev "$KNOWN_BUILD_SYSTEM_WARNING" || true)
        if [ -n "$warnings" ]; then
            fail "$label — exited 0 but emitted warnings (SC-015 requires zero)"
            printf '%s\n' "$warnings" | sort -u | sed 's/^/       /'
        else
            pass "$label"
        fi
    else
        fail "$label"
        sed 's/^/       /' "$log"
    fi
    rm -f "$log"
}

# ---------------------------------------------------------------------------
# Preflight — the Metal toolchain.
#
# Xcode 26 ships the Metal compiler as a separately downloadable component, so a machine can have a
# complete Xcode and a clean clone and still not have `metal`. That is the one prerequisite this
# script cannot satisfy for itself, so it is checked first and named plainly.
#
# It is checked at all because the resulting failure is actively misleading. With no Metal compiler,
# SwiftPM stops treating Shaders.metal as a compilable resource ("found 1 file(s) which are
# unhandled"), so it emits no resource bundle, so `Bundle.module` is never synthesised — and the build
# dies in Renderer.swift with "type 'Bundle' has no member 'module'". Every stage below fails, and the
# first error points at a source file that is not wrong.
#
# `xcrun -f metal` is NOT sufficient here: the shim resolves to a path even when the toolchain behind
# it is absent. The tool has to actually be executed.
# ---------------------------------------------------------------------------
section "Preflight: Metal toolchain"
if xcrun metal --version >/dev/null 2>&1; then
    pass "metal compiler available"
else
    fail "metal compiler unavailable"
    printf '\n'
    printf '  The Metal toolchain is not installed, so Shaders.metal cannot be compiled.\n'
    printf '  Stopping here: every stage below would fail, and the first error would\n'
    printf '  misleadingly name Sources/SwiftSkyRendering/Renderer.swift.\n\n'
    printf '  Install it, then re-run this script:\n\n'
    printf '      xcodebuild -downloadComponent MetalToolchain\n\n'
    printf '\033[31mVERIFICATION FAILED\033[0m\n'
    exit 1
fi

# ---------------------------------------------------------------------------
# The ship image (007 FR-002, SC-008a). design/sprites/ship.png is the source of truth; the rendering
# layer ships a copy because SwiftPM resources must live inside the target's directory. A copy that
# drifts from the design is a failure. To fix it, copy the design file over the bundled one:
#
#     cp design/sprites/ship.png Sources/SwiftSkyRendering/Resources/ship.png
# ---------------------------------------------------------------------------
section "Ship image matches the design file"
ship_image_matches() {
    cmp -s design/sprites/ship.png Sources/SwiftSkyRendering/Resources/ship.png
}
run_stage "Sources/SwiftSkyRendering/Resources/ship.png is byte-identical to design/sprites/ship.png" \
    ship_image_matches

# ---------------------------------------------------------------------------
# Layer libraries — build for the host, which covers all three layer targets.
# ---------------------------------------------------------------------------
# --explicit-target-dependency-import-check=error is REQUIRED, not optional. Without it SwiftPM
# reports a forbidden cross-layer import as a warning and exits 0, which would make FR-013's boundary
# advisory instead of enforced. This flag is what makes SC-009 hold.
IMPORT_CHECK="--explicit-target-dependency-import-check=error"

# --build-system swiftbuild is REQUIRED, not a preference. SwiftPM's default `native` build system does
# not compile `.metal` sources: it reports Shaders.metal as an unhandled file, emits no resource bundle,
# and so `Bundle.module` is never synthesised — the build then dies in Renderer.swift with "type
# 'Bundle' has no member 'module'", naming a file that is not wrong. `swiftbuild` (the same build system
# Xcode drives) compiles it correctly. research.md R1's verification of SwiftPM `.metal` support holds
# for this build system only.
BUILD_SYSTEM="--build-system swiftbuild"

section "Building layer libraries (macOS host, layer boundary enforced)"
run_stage "swift build (layer boundary enforced)" \
    swift build $BUILD_SYSTEM $IMPORT_CHECK

# ---------------------------------------------------------------------------
# Headless test suite — no GPU, no simulator, no app host (FR-017, SC-007).
# ---------------------------------------------------------------------------
section "Running headless test suite"

# "Headless" is checked here rather than trusted (002 research.md R7). The rendering tests link
# Metal, which is fine, but a test that creates a device, queue, buffer or texture needs a GPU and
# would quietly pass on a developer's Mac while being meaningless — or failing — on a GPU-less
# runner. Any such call anywhere under Tests/ fails the run, and the offending lines are printed.
headless_guard() {
    # Method calls only (a leading `.`), so a test helper that happens to share a name cannot trip it.
    if grep -rnE 'MTLCreateSystemDefaultDevice|\.makeCommandQueue\(|\.makeBuffer\(|\.makeTexture\(' Tests/; then
        return 1
    fi
    return 0
}
run_stage "tests create no Metal device, queue, buffer or texture" headless_guard

run_stage "swift test" \
    swift test $BUILD_SYSTEM $IMPORT_CHECK

# ---------------------------------------------------------------------------
# App targets. Present only once the Xcode project exists (T004).
#
# This stage is announced as PENDING rather than silently skipped: a verification script that reports
# success for work it never attempted is worse than one that admits the gap.
# ---------------------------------------------------------------------------
section "Building app targets (iOS + macOS)"
if [ -d swiftSky.xcodeproj ]; then
    build_app() {  # $1=scheme  $2=destination
        run_stage "xcodebuild $1" \
            xcodebuild build -project swiftSky.xcodeproj -scheme "$1" \
            -configuration Debug -destination "$2" \
            CODE_SIGNING_ALLOWED=NO -quiet
    }
    build_app 'swiftSky (macOS)' 'platform=macOS'
    build_app 'swiftSky (iOS)' 'generic/platform=iOS Simulator'
else
    printf '\033[33mPENDING\033[0m swiftSky.xcodeproj does not exist yet (task T004).\n'
    printf '        App-target builds are NOT covered by this run.\n'
    pending="app-targets"
fi

# ---------------------------------------------------------------------------
section "Summary"
if [ "$status" -ne 0 ]; then
    printf '\033[31mVERIFICATION FAILED\033[0m\n'
    exit 1
fi

if [ -n "$pending" ]; then
    printf '\033[33mVERIFICATION INCOMPLETE\033[0m — everything runnable passed, but: %s\n' "$pending"
    printf 'Exiting 0 because no executed stage failed. Re-run once T004 lands for full coverage.\n'
    exit 0
fi

printf '\033[32mVERIFICATION PASSED\033[0m — all stages green.\n'
exit 0
