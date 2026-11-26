# CI runner

The `verify` workflow (`.github/workflows/verify.yml`) runs `./Scripts/verify.sh`, started **by hand from
the Actions tab** (`workflow_dispatch` only — the push and pull-request triggers are disabled in the
workflow file). It runs on a **self-hosted GitHub Actions runner on the
developer's Mac**, not on a GitHub-hosted machine: that Mac has the exact Xcode and Metal toolchain the
script needs, and it costs no build minutes. Design record: `specs/018-ci-verify-workflow/`.

| | |
|---|---|
| Registered to | the repository `Yoi-Nami-Ra/swiftSky` only, not to the account |
| Labels | `self-hosted`, `macOS`, `ARM64` (added by the runner), `xcode-27` (given at registration) |
| Workflow asks for | `self-hosted`, `macOS`, `xcode-27` |
| Folder | `~/actions-runner/swiftSky` |
| Name | `swiftsky-<short host name>` |
| Runs as | the developer's own macOS user, as a LaunchAgent started at login |

Because it runs as the developer's user, a job sees the same selected Xcode (`xcode-select -p`), the
Metal toolchain component and `/usr/bin/swift` as a local run. Nothing extra is installed for it.

## Merge rule

A pull request is merged only when its `verify / verify` check **passed for its current head**: not while
it is red, cancelled, queued or missing. Branch protection is not set up (spec 018 left it out), so this
rule is kept by hand.

## Install (once)

1. In the repository on GitHub: *Settings → Actions → Runners → New self-hosted runner*, choose
   **macOS** and **ARM64**. The page shows the current runner version, the download command with its
   SHA-256 check, and a registration token (single use, valid for one hour; never commit it).
2. In a normal login shell (the runner records this shell's `PATH` at configuration time):

   ```sh
   mkdir -p ~/actions-runner/swiftSky && cd ~/actions-runner/swiftSky
   # download, check and extract exactly as the GitHub page shows (curl -o …, shasum -a 256 -c, tar xzf …)
   ./config.sh --url https://github.com/Yoi-Nami-Ra/swiftSky \
       --token <registration token from the page> \
       --name swiftsky-$(hostname -s) \
       --labels xcode-27 \
       --unattended
   ```

3. Install and start it as a service. **Never with `sudo`**: it must run as your user.

   ```sh
   ./svc.sh install
   ./svc.sh start
   ./svc.sh status
   ```

4. Check that *Settings → Actions → Runners* lists the runner as **Idle** with all four labels.

## Start, stop, status

All from `~/actions-runner/swiftSky`:

```sh
./svc.sh start     # start now (it also starts at every login)
./svc.sh stop      # stop; jobs queue until it starts again
./svc.sh status    # loaded / running?
```

Fallback without the service: `./run.sh` in a terminal, Ctrl-C to stop. Do not run both at once.

## Is it online?

*Settings → Actions → Runners* shows **Idle** (online, waiting), **Active** (running a job) or
**Offline**. With `gh` signed in as the owning account:

```sh
gh api repos/Yoi-Nami-Ra/swiftSky/actions/runners --jq '.runners[] | {name, status, busy}'
```

## While the Mac is off (or no runner is registered)

CI runs only while the Mac is on, awake, and the runner is running. A dispatched run made meanwhile shows
**Queued**; it starts when the runner comes back. GitHub cancels a job that has waited 24 hours for a
runner: re-run it from the run's page (*Re-run jobs*). With no runner registered, every run queues until
one is installed as described above; check with `gh api repos/Yoi-Nami-Ra/swiftSky/actions/runners`.

## When Xcode changes

The `xcode-27` label is a promise that the Mac's selected Xcode is 27. When the Mac moves to another
Xcode, change both together, in one change:

- the runner's label: *Settings → Actions → Runners → the runner → labels* (labels cannot be removed
  with `config.sh`);
- `runs-on` in `.github/workflows/verify.yml`.

## Remove

```sh
cd ~/actions-runner/swiftSky
./svc.sh stop
./svc.sh uninstall
./config.sh remove --token <removal token from Settings → Actions → Runners → the runner>
```

## Public repository — runner safety

The repository is **public** (`gh repo view Yoi-Nami-Ra/swiftSky` reports `visibility: public`). A
self-hosted runner runs whatever code a workflow run checks out, on this Mac, as this user. That is
acceptable here only because the workflow is `workflow_dispatch`: a run can be started solely by a user
with write access to the repository, not by anyone who merely opens a pull request. **Never re-enable the
`push` or `pull_request` triggers in `verify.yml` while a self-hosted runner is attached to this public
repository** — a fork's pull request would then execute its code on this Mac as this user. If those
triggers are ever wanted, move the job to a GitHub-hosted runner instead.
