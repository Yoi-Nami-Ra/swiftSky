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
