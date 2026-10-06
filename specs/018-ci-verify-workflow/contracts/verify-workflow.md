# Contract: the `verify` workflow

**Feature**: 018-ci-verify-workflow | File: `.github/workflows/verify.yml`

The workflow MUST be equivalent to the following. Key order and comments may differ; no step, trigger,
input or permission may be added.

```yaml
name: verify

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read

concurrency:
  group: verify-${{ github.ref == 'refs/heads/main' && github.run_id || github.ref }}
  cancel-in-progress: true

jobs:
  verify:
    runs-on: [self-hosted, macOS, xcode-27]
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - run: ./Scripts/verify.sh
```

## Guarantees

- **G1**: A push to `main` and a pull request against `main` each start exactly one run.
- **G2**: The run only ever lands on a runner carrying all three required labels (`self-hosted`, `macOS`, `xcode-27`).
- **G3**: The job's result is the exit status of `./Scripts/verify.sh`; nothing else can fail or pass it
  (other than checkout failing, or the time limit).
- **G4**: A newer pull-request run cancels the older one for the same pull request; `main` runs are never
  cancelled by later pushes.
- **G5**: The job can read the repository and nothing more, and leaves no credentials in the work folder.

## Check name

The job is named `verify`, so it shows on commits and pull requests as `verify / verify`. The merge rule
(FR-014) and `.github/RUNNER.md` refer to it by that name.
