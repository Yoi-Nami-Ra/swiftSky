# Quickstart: CI Running the Verification Script

**Feature**: 018-ci-verify-workflow

Two kinds of check. **Local checks** (L) change nothing outside this clone and can be run by anyone,
including an agent. **Developer checks** (D) act on GitHub or install a service on this Mac: only the
developer runs them, by hand (FR-012). No agent pushes, opens pull requests, registers or starts the
runner, installs a LaunchAgent or changes GitHub settings.

Runner commands are in [`.github/RUNNER.md`](../../.github/RUNNER.md); the workflow's exact shape is in
[contracts/verify-workflow.md](./contracts/verify-workflow.md).

## Local checks

### L1 — The remote is in place (FR-001, SC-001)

```sh
git remote -v                          # origin → git@yoinamira-github:Yoi-Nami-Ra/swiftSky.git
git config --get remote.origin.url     # git@github.com:Yoi-Nami-Ra/swiftSky.git
git fetch --prune && git rev-parse main origin/main
```

Expected: both URLs as shown; before this feature, `main` and `origin/main` name the same commit.

**Result 2026-10-07 (T001)**: PASS. `origin` → `git@yoinamira-github:Yoi-Nami-Ra/swiftSky.git`, stored
URL `git@github.com:Yoi-Nami-Ra/swiftSky.git`; after `git fetch --prune`, `main` = `origin/main` =
`e4a3040` (`main` had moved on from this branch's base `cd2b055` through other merged work).

### L2 — The workflow is well formed and matches the contract (FR-002–FR-007a, SC-005)

```sh
actionlint .github/workflows/verify.yml
```

Expected: no output, exit 0. Then read the file against the contract: two triggers, `contents: read`,
the concurrency group, `runs-on: [self-hosted, macOS, xcode-27]`, `timeout-minutes: 30`, and exactly two
steps — checkout with `persist-credentials: false`, and `./Scripts/verify.sh`.

### L3 — The verification script is unchanged in behaviour (FR-005, SC-008)

```sh
git diff main -- Scripts/verify.sh     # comment lines only
time ./Scripts/verify.sh
```

Expected: the diff touches `#` comment lines only; the script ends `VERIFICATION PASSED`. Note the
`real` time for D3.

### L4 — No record of a missing remote or CI is left (FR-010, FR-011, SC-007)

```sh
grep -n -i "no remote\|no CI\|CI absence\|CI-absence\|once a remote" specs/001-metal-app-shell/plan.md CLAUDE.md
```

Expected: no line says the repository has no remote or no CI. (001's spec, FR-019a and specs 002–015 are
merged history and are not checked.)

## Developer checks

Do these in order. Tick each one in `tasks.md` as you go.

### D1 — Install and register the runner (FR-008a, FR-009)

Follow `.github/RUNNER.md` → *Install*. Expected: the repository's *Settings → Actions → Runners* lists
`swiftsky-<host>` as **Idle** with labels `self-hosted`, `macOS`, `ARM64`, `xcode-27`, and
`./svc.sh status` reports the service loaded and running.

### D2 — Push the branch and open its pull request (US2, SC-003)

```sh
git push -u origin 018-ci-verify-workflow
gh auth switch -u Yoi-Nami-Ra      # gh's active account cannot see the repository
gh pr create --base main --head 018-ci-verify-workflow
```

Expected: the pull request shows one `verify / verify` check; it runs on `swiftsky-<host>` (the run's
*Set up job* log names the runner) and passes. Its log shows checkout, then the script's sections
(Preflight … Summary) and `VERIFICATION PASSED`.

### D3 — Merge and see `main` verified (US1, SC-001, SC-002)

Merge the pull request once D2 is green (the merge rule, FR-014). Expected: the push to `main` starts one
`verify` run on the runner, and it passes; it finishes within the 30-minute limit. Record its duration next to L3's local time (the CI run
starts from a clean checkout, R5, so it may be longer). `git fetch && git rev-parse main origin/main` agree after pulling.

### D4 — A broken change turns the job red, on a throwaway pull request (US3, SC-004, FR-013)

```sh
git switch -c throwaway/ci-red-check main
cat > Tests/SwiftSkySimulationTests/CIMustFail.swift <<'SWIFT'
import Testing
@Test func ciMustFail() { #expect(Bool(false)) }
SWIFT
git add Tests/SwiftSkySimulationTests/CIMustFail.swift
git commit -m "Throwaway: deliberately failing test (do not merge)"
git push -u origin throwaway/ci-red-check
gh pr create --base main --title "Throwaway: CI red check (do not merge)" --body "Closes unmerged."
```

Expected: `verify / verify` fails; its log shows `FAIL swift test` with `ciMustFail` named. Do D5 now,
on this same pull request, then close it:

```sh
gh pr close --delete-branch throwaway/ci-red-check
git switch main && git branch -D throwaway/ci-red-check
```

`main` never contains the commit.

### D5 — A newer push cancels the older pull-request run (FR-007a, SC-001a)

On the throwaway pull request of D4, after its red run and before the close step there, push two empty
commits about ten seconds apart, so the second arrives while the first one's run is in progress:

```sh
git commit --allow-empty -m "Throwaway: push 1" && git push
sleep 10
git commit --allow-empty -m "Throwaway: push 2" && git push
```

Expected: the run for push 1 ends **cancelled**; the run for push 2 runs (and fails, as in D4). On
`main`, no run is ever cancelled by a later push (D3's run and any later ones each complete).

### D6 — Stop and start the runner from the written steps (US4, SC-006)

Follow `.github/RUNNER.md` → *Stop* and *Start*. Expected: after stop, the Settings page shows the runner
**Offline**; a pull request or push made now shows its run **Queued**. After start, the runner is **Idle**
again and the queued run starts.

## Evidence

Record dates, run URLs and the D3 duration under each check as you complete it.
