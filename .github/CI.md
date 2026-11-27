# CI and repository validation

All of it runs on GitHub-hosted runners, which are free for public repositories.

| Check | File | Runs on | When |
|---|---|---|---|
| `verify` (`./Scripts/verify.sh`) | `workflows/verify.yml` | `xcode-27`, Xcode 27.2 | push to `main`, pull request, by hand |
| CodeQL: `actions`, `c-cpp`, `swift` | `workflows/codeql.yml` | `actions` on `ubuntu-latest`; `c-cpp` and `swift` on `macos-26`, Xcode 26.5 | push to `main`, pull request, weekly, by hand |
| Dependency review | `workflows/dependency-review.yml` | `ubuntu-latest` | pull request |
| Dependabot version updates (actions) | `dependabot.yml` | GitHub | weekly |

`verify.yml` first makes sure the Metal toolchain is there, then runs the script.

CodeQL supports Swift up to 6.3, so its Swift job builds with Xcode 26. The `c-cpp` job traces the same
build, because the C code compiles only with `SWIFTSKY_INSTRUMENTATION` (set by the Debug build) and needs
Apple's headers. Both build only the macOS app, so **iOS-only code (`#if os(iOS)`) is not scanned**.

## Merge rule

A pull request is merged only when its checks **passed for its current head**: not while one is red,
cancelled, queued or missing. **This rule is kept by hand**: `main` has no branch protection or ruleset,
so GitHub does not enforce it. A ruleset added later should require `verify`, `analyze (actions)`,
`analyze (c-cpp)`, `analyze (swift)` and `dependency-review` by name (the combined `CodeQL` check is not
enough: it has shown success while `analyze (swift)` was still running).

## Never attach a self-hosted runner

The repository is **public** and these workflows run on pull requests, including pull requests from
forks. A self-hosted runner would run a stranger's code on that machine. Keep every `runs-on` on a
GitHub-hosted label. The self-hosted runner that spec 018 described is no longer used.

## When Xcode changes

Use only versions the chosen runner image lists (<https://github.com/actions/runner-images>).

- `verify.yml`: change `DEVELOPER_DIR`. For a new major Xcode, change `runs-on` too (the `xcode-27` label
  is tied to Xcode 27), and the label in `actionlint.yaml`.
- `codeql.yml`: change the `xcode-select` path, and the matrix `runner` of `c-cpp` and `swift` if that
  image does not list the version. Update the step name and comments that name Xcode 26.
- Update the versions written in this file and in `CLAUDE.md`.

CI's Xcode can differ from the one on a developer's Mac, so a result may differ between them.

## Checking locally

    ./Scripts/verify.sh
    actionlint
