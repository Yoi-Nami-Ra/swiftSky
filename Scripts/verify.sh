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
# Layer libraries — build for the host, which covers all three layer targets.
# ---------------------------------------------------------------------------
# --explicit-target-dependency-import-check=error is REQUIRED, not optional. Without it SwiftPM
# reports a forbidden cross-layer import as a warning and exits 0, which would make FR-013's boundary
# advisory instead of enforced. This flag is what makes SC-009 hold.
IMPORT_CHECK="--explicit-target-dependency-import-check=error"

section "Building layer libraries (macOS host, layer boundary enforced)"
if swift build $IMPORT_CHECK; then
    pass "swift build (layer boundary enforced)"
else
    fail "swift build (layer boundary enforced)"
fi

# ---------------------------------------------------------------------------
# Headless test suite — no GPU, no simulator, no app host (FR-017, SC-007).
# ---------------------------------------------------------------------------
section "Running headless test suite"
if swift test $IMPORT_CHECK; then
    pass "swift test"
else
    fail "swift test"
fi

# ---------------------------------------------------------------------------
# App targets. Present only once the Xcode project exists (T004).
#
# This stage is announced as PENDING rather than silently skipped: a verification script that reports
# success for work it never attempted is worse than one that admits the gap.
# ---------------------------------------------------------------------------
section "Building app targets (iOS + macOS)"
if [ -d swiftSky.xcodeproj ]; then
    build_app() {  # $1=scheme  $2=destination
        if xcodebuild build -project swiftSky.xcodeproj -scheme "$1" \
            -configuration Debug -destination "$2" \
            CODE_SIGNING_ALLOWED=NO -quiet; then
            pass "xcodebuild $1"
        else
            fail "xcodebuild $1"
        fi
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
