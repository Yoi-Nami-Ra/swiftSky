# CI runner

The `verify` workflow (`.github/workflows/verify.yml`) runs `./Scripts/verify.sh` on every push to `main`
and on every pull request against `main`. It runs on a **self-hosted GitHub Actions runner on the
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

## While the Mac is off

CI runs only while the Mac is on, awake, and the runner is running. A push or pull request made
meanwhile shows its run **Queued**; it starts when the runner comes back. GitHub cancels a job that has
waited 24 hours for a runner: re-run it from the run's page (*Re-run jobs*).

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

## Private repositories only

A self-hosted runner runs whatever code a workflow run checks out, on this Mac, as this user. That is
acceptable only because the repository is private. Never attach this runner to a public repository, and
do not make this repository public while the runner is registered.
