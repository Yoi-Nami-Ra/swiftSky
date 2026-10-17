# Quickstart: validating 020

## Prerequisites

The repository checked out, Xcode 27 command-line tools, and nothing else. All checks are headless.

## Checks

1. **Reproduction fails before the fix** (FR-005, FR-006). With the law unchanged, run
   `swift test --filter AutopilotRestPhase`. Expected: the phase-name tests fail. The 120° re-order starts
   `flipping` and the 180° one starts `braking`, as research R1 records. The leftover-velocity and
   fingerprint tests pass.
2. **Fix passes** (spec SC-001). After the change, run the same filter. Expected: all pass. The 120° re-order
   reads `aligning, burning, flipping, braking, arrived`, and the 180° one reads `burning, flipping, braking,
   arrived`.
3. **Inputs unchanged** (SC-002). Expected: the fingerprint tests pass with the constants recorded in
   check 1, unedited. `git diff` shows no change to those constants between the two commits.
4. **Boundary** (FR-005a). Expected: a speed of exactly 0.001 u/s turning against its velocity reads
   `aligning`, and the next `Double` above it reads `flipping`.
5. **Nothing else moves** (SC-003). `git diff main -- Tests/SwiftSkySimulationTests/AutopilotTests.swift
   Tests/SwiftSkySimulationTests/PlannedPathTests.swift` is empty, and those suites pass.
6. **Single command** (SC-004). `./Scripts/verify.sh` passes.
7. **Hot path before/after** (constitution III, FR-010). The method is the one in 010 quickstart check 9: a
   throwaway `swiftc -O -wmo` executable and 10,000,000 single-tick `advance` calls with an order flown, run 3
   times each on `main` and on the branch. Expected: ns per call the same within noise, and 0 allocations.

Optional, by hand (not required for done): in a Debug build, order the ship somewhere, wait for `arrived`,
then click or tap behind it and to the side. The debug overlay's order line reads `aligning` first (015's
check 5 no longer shows `flipping`).
