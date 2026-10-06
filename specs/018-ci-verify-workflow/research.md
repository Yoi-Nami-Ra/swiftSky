# Research: CI Running the Verification Script

**Feature**: 018-ci-verify-workflow | **Date**: 2026-10-07

Sources: GitHub Actions documentation, the `actions/checkout` README and the `actions/runner` repository
(fetched through Context7 on 2026-10-07), and this Mac's own state (Xcode 27.0 27A266a selected at
`/Applications/Xcode-27.0.0-Release.Candidate.app`, Apple silicon, `swift` and `xcodebuild` resolving to
`/usr/bin`, `actionlint` installed through Homebrew).

## R1 — The remote and the push are already done

**Decision**: No work. `origin` is `git@github.com:Yoi-Nami-Ra/swiftSky.git` (rewritten locally to the
`yoinamira-github` ssh alias), and `origin/main` equalled local `main` (`cd2b055`) when this feature
started. The quickstart re-checks it (FR-001, SC-001).

**Rationale**: The ticket was written before the repository was created; CLAUDE.md records the remote.

**Alternatives considered**: Re-creating the repository under another account — rejected, the owning
account is settled.

## R2 — Workflow triggers

**Decision**: `push` with `branches: [main]` and `pull_request` with `branches: [main]`. Pushes to other
branches do not trigger a run on their own; a branch is verified through its pull request.

**Rationale**: FR-002 names exactly these two events. Adding `push` on every branch would run a pull
request's head twice (once for the push, once for the pull request) on the only runner.

**Alternatives considered**: `push` on all branches — doubles the work; `workflow_dispatch` — not asked
for (YAGNI; a run can be re-run from the host's page).

## R3 — The job: runner selection, steps, limits

**Decision**:
- `runs-on: [self-hosted, macOS, xcode-27]` (FR-003). `self-hosted` and `macOS` are labels the runner
  adds itself (with `ARM64`); `xcode-27` is the one custom label given at registration.
- Two steps (FR-004): `actions/checkout@v7`, then `run: ./Scripts/verify.sh`. v7 is the current major
  version per the action's README.
- `persist-credentials: false` on checkout: the job never pushes, and on a persistent machine the token
  would otherwise sit in the work folder's `.git/config` until the post-job step. It is an input of the
  checkout step, not an extra step.
- `timeout-minutes: 30` on the job (FR-007, clarification).
- `permissions: contents: read` at workflow level (FR-006).

**Rationale**: The ticket and FR-004 forbid anything beyond checkout and the script. The script already
checks the Metal toolchain, builds, tests and fails on warnings; any step added here would be a second
definition of verification.

**Alternatives considered**: A step printing `xcodebuild -version` for the log — rejected by FR-004; the
script's output already shows the toolchain through its build logs on failure. A matrix per platform —
the script builds both apps itself.

## R4 — Superseded runs

**Decision**:

```yaml
concurrency:
  group: verify-${{ github.ref == 'refs/heads/main' && github.run_id || github.ref }}
  cancel-in-progress: true
```

On a pull request, `github.ref` is `refs/pull/<n>/merge`, so all runs of one pull request share a group
and a newer one cancels the older (FR-007a). On `main`, each run gets its own group (its `run_id`), so
nothing on `main` is ever cancelled or replaced.

**Rationale**: A concurrency group allows one running and one pending run, and a new pending run cancels
the previous pending one even with `cancel-in-progress: false`. A single shared `main` group would
therefore drop intermediate `main` commits when pushes come faster than the job, which the clarification
forbids. Per-run groups on `main` avoid that; the single runner still serialises the jobs.

**Alternatives considered**: No `concurrency` at all — every superseded pull-request run would occupy the
only runner to completion; `cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}` with a shared
group — drops pending `main` runs as described.

## R5 — Clean workspace on a persistent runner

**Decision**: Keep checkout's default `clean: true` (`git clean -ffdx && git reset --hard HEAD` before
fetching). Each run therefore starts with no `.build/` folder, which matches what `verify.sh` promises: it
"needs no setup beyond a clean clone". Xcode's derived data lives outside the work folder
(`~/Library/Developer/Xcode/DerivedData`, shared with the developer's own builds, keyed by project path,
so the runner's checkout path gets its own entry).

**Rationale**: A stale `.build/` could hide a clean-build failure. Run time is the cost; SC-002 measures
it against a local clean run.

**Alternatives considered**: `clean: false` for faster incremental runs — rejected for the reason above;
caching (`actions/cache`) — out of scope.

## R6 — Runner installation and service

**Decision**:
- Folder: `~/actions-runner/swiftSky` (one runner per repository; the name leaves room for others).
- Download and checksum: from the repository's *Settings → Actions → Runners → New self-hosted runner*
  page (macOS, ARM64), which shows the current version, the download command and its SHA-256. Nothing
  is pinned in the repository, because the runner updates itself.
- Registration: `./config.sh --url https://github.com/Yoi-Nami-Ra/swiftSky --token <token from that page>
  --name swiftsky-<short host name> --labels xcode-27 --unattended`. Registered to the repository, not the
  account (FR-009). The token is single-use and expires after an hour; it is never written to the
  repository.
- Service (FR-008a): `./svc.sh install`, then `./svc.sh start`; `./svc.sh status` and `./svc.sh stop`;
  `./svc.sh uninstall` to remove. On macOS the script writes a LaunchAgent plist to
  `~/Library/LaunchAgents` and must not be run with `sudo`, so the runner runs as the developer's own user
  and starts at login. Fallback: `./run.sh` in a terminal, stopped with Ctrl-C.
- Removal: `./svc.sh uninstall`, then `./config.sh remove --token <removal token from the same page>`.
- Online check: the runner list on the same Settings page (Idle / Active / Offline), or, with the owning
  account's `gh`, `gh api repos/Yoi-Nami-Ra/swiftSky/actions/runners`.

**Rationale**: The runner's own service script is the supported way to keep it running without a
terminal; running as the developer's user gives it the selected Xcode, the Metal toolchain component and
`/usr/bin/swift` exactly as a local run sees them. The runner records `PATH` at configuration time
(`.path`), so it must be configured from a normal login shell.

**Alternatives considered**: A system-wide LaunchDaemon as another user — needs its own Xcode setup and
Metal toolchain, contrary to "nothing is installed for the runner"; a hosted runner — out of scope.

## R7 — Queued jobs and an offline Mac

**Decision**: Document, do not engineer. A job with no online matching runner waits; GitHub cancels a
job that has waited 24 hours for a self-hosted runner. `.github/RUNNER.md` says to re-run it from the
run's page.

## R8 — Merge gate without branch protection

**Decision**: A written rule (FR-014) in `.github/RUNNER.md` and CLAUDE.md: a pull request is not merged
unless its `verify` job passed for its current head (not while red, cancelled, queued or missing). Recorded in this plan's Complexity Tracking as a
procedural gate where Principle II asks for a gate.

**Rationale**: The ticket puts branch protection out of scope. Branch protection and rulesets on a
private repository also depend on the account's plan, which this feature does not change.

**Alternatives considered**: Branch protection requiring the `verify` check — the enforced form, left
for a later ticket; amending the constitution to accept a procedural gate — not needed while the gap is
recorded as the constitution asks for exceptions.

## R9 — Local validation of the workflow file

**Decision**: `actionlint .github/workflows/verify.yml` before pushing, as a quickstart check. It is not
added to `verify.sh` (FR-005, and `actionlint` is not part of a clean macOS + Xcode setup).
`.github/actionlint.yaml` declares the custom runner label `xcode-27` (`self-hosted-runner.labels`);
without it actionlint rejects `runs-on` as an unknown label (found during implementation, T005).

## R10 — Records of the gap

**Decision**:
- `specs/001-metal-app-shell/plan.md`: remove the "No CI pipeline" row and the "plus the CI-absence
  record…" clause of the note above the table; rewrite the two Principle II rows to cite the workflow
  (018). Lines near 61, 73, 159–160 and 167.
- `CLAUDE.md`: the description of Principle II says "wired into CI once a remote exists"; it becomes
  "wired into CI (`.github/workflows/verify.yml`, a self-hosted runner on this Mac, 018)", and a new
  Key-locations entry names the workflow, `.github/RUNNER.md` and the merge rule. The "Built so far" list
  gains 018.
- `Scripts/verify.sh`: its header comment says the file "can become a CI job body verbatim once the
  repository has a remote"; it becomes a statement that it is the CI job body. Comment only (FR-005).
- Specs 002–015 stay as they are (ticket). The constitution's v1.1.0 Sync Impact Report keeps its
  "Follow-up TODOs" line: it is a dated record, and changing it would be an amendment with a version bump
  for no change in principle.
