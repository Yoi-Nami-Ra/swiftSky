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

## Evidence

| # | Result | Notes |
|---|--------|-------|
| 1 | **PASS** 2026-10-18 | Before the fix (T012, phase 3): the 120° re-order read `flipping, braking, burning, flipping, braking, arrived`, the straight-behind one `braking, burning, flipping, braking, arrived`, and a speed of exactly `settleSpeed` read `flipping`. The leftover-velocity and fingerprint tests passed |
| 2 | **PASS** 2026-10-18 | After the fix: 120° `aligning, burning, flipping, braking, arrived`; straight behind `burning, flipping, braking, arrived`. Fresh `swift test --filter AutopilotRestPhase`: 5 tests in 1 suite passed. Full `swift test` after phase 3: 287 passed |
| 3 | **PASS** 2026-10-18 | The fingerprint tests pass with the pre-fix constants, unedited (committed in phase 2, 4f6f258, unchanged by the fix commit 71260a0) |
| 4 | **PASS** 2026-10-18 | Exactly `settleSpeed` turning against its velocity reads `aligning`; the next `Double` above reads `flipping` |
| 5 | **PASS** 2026-10-18 | `git diff main -- Tests/SwiftSkySimulationTests/AutopilotTests.swift Tests/SwiftSkySimulationTests/PlannedPathTests.swift` is empty; those suites pass in the full run |
| 6 | **PASS** 2026-10-18 | `./Scripts/verify.sh`: "VERIFICATION PASSED — all stages green", no `warning:` lines |
| 7 | **PASS** 2026-10-18 | Apple M1 Pro, `swiftc -O -wmo` over `Sources/SwiftSkySimulation/*.swift` plus a throwaway `main.swift` in the scratchpad (not committed); allocations counted through libmalloc's `malloc_logger` hook (control: 1,000 transient arrays counted as 1,000). 10,000,000 single-tick `Simulation.advance(_:ticks: 1)` calls with an order to (1,000,000; 700,000) being flown (it arrives and keeps station within the run). ns per call, 3 runs: `main` 32.34 / 30.48 / 30.63, branch 30.89 / 28.87 / 29.17. **0 allocations** in all six runs. Same cost within noise (the branch is not slower) |
