# Quickstart: validating the cargo hold

1. `swift test` for the three test targets, or `./Scripts/verify.sh` (the single gate): hold rules (add,
   remove, limit at/below/above, 0 t, negative, unknown commodity, overflow, generated-sequence invariants,
   rejection leaves the hold equal), list loading and each malformed case, snapshot and overlay text for
   empty/partial/full holds, `--no-debug-cargo` parsing, motion and autopilot tests unchanged.
2. Resource: `verify.sh` builds both app targets; confirm the macOS app bundle contains the simulation
   resource bundle with `commodities.json` (`find <app> -name commodities.json`).
3. By hand: `./Scripts/build-instrumented.sh macos`, `open -n <app>`: overlay shows `hold 0 / 20 t free 20`;
   again with `--no-debug-cargo`: no cargo line, other lines unchanged.
4. Allocation: with the instrumented build and cargo lines on, the frame summary still reports `allocs=0`
   (011 method).
5. Release: `verify.sh` strings check finds none of the cargo labels or `--no-debug-cargo`.

## Results (phase 4, SKY-52)

- Check 1: `swift test` passes (simulation 129, rendering 124, platform 78); `./Scripts/verify.sh` passes.
- Check 2: DONE. The instrumented macOS app contains `Contents/Resources/swiftSky_SwiftSkySimulation.bundle/Contents/Resources/commodities.json`.
- Check 3: NOT DONE. Needs a person to look at the overlay (`hold    0 / 20 t  free 20`, and its absence with `--no-debug-cargo`). The text itself is covered by DebugOverlayCargoTests and the argument by DebugCargoOptionTests; `--no-debug-cargo` and ` t  free ` are present in the instrumented executable's strings.
- Check 4: DONE for an empty hold. Instrumented build launched with `open -n`, frame summaries over 10 s read `allocs=0 allocframes=0` with the cargo lines on. A non-empty hold was not shown live (no way to add cargo from the app yet); the write path is the same allocation-free calls.
- Check 5: DONE. `verify.sh` Release strings check (now including `no-debug-cargo`, `hold    ` and ` t  free `) passes.
- FR-010 (no accessibility element on the overlay): not inspected by hand.
