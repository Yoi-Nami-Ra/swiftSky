# CI and repository validation

All of it runs on GitHub-hosted runners, which are free for public repositories.

| Check | File | Runs on | When |
|---|---|---|---|
| `verify` (`./Scripts/verify.sh`) | `workflows/verify.yml` | `xcode-27`, Xcode 27.2 | push to `main`, pull request, by hand |
| CodeQL: `actions`, `c-cpp`, `swift` | `workflows/codeql.yml` | `ubuntu-latest`; Swift on `macos-26`, Xcode 26.5 | push to `main`, pull request, weekly, by hand |
| Dependency review | `workflows/dependency-review.yml` | `ubuntu-latest` | pull request |
| Dependabot version updates (actions) | `dependabot.yml` | GitHub | weekly |

CodeQL supports Swift up to 6.3, so its Swift job builds with Xcode 26.

## Merge rule

A pull request is merged only when its checks **passed for its current head**: not while one is red,
cancelled, queued or missing.

## Never attach a self-hosted runner

The repository is **public** and these workflows run on pull requests, including pull requests from
forks. A self-hosted runner would run a stranger's code on that machine. Keep every `runs-on` on a
GitHub-hosted label. The self-hosted runner that spec 018 described is no longer used.

## When Xcode changes

Change `DEVELOPER_DIR` in `verify.yml`, or the `xcode-select` path in `codeql.yml`, to a version the
runner image lists (<https://github.com/actions/runner-images>). CI's Xcode can differ from the one on a
developer's Mac, so a result may differ between them.

## Checking locally

    ./Scripts/verify.sh
    actionlint
