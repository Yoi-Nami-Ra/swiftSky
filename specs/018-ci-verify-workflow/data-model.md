# Data Model: CI Running the Verification Script

**Feature**: 018-ci-verify-workflow

No application data changes. The entities are configuration and their states.

## Verification workflow (`.github/workflows/verify.yml`)

| Field | Value | Requirement |
|-------|-------|-------------|
| Triggers | push to `main`; pull request against `main` | FR-002 |
| Permissions | `contents: read` | FR-006 |
| Concurrency group | `verify-<run id>` on `main`, `verify-<ref>` otherwise; cancel in progress | FR-007a, R4 |
| Job `verify` runner | labels `self-hosted`, `macOS`, `xcode-27` | FR-003 |
| Job time limit | 30 minutes | FR-007 |
| Steps | checkout (`persist-credentials: false`), `./Scripts/verify.sh` | FR-004 |

Exact contract: [contracts/verify-workflow.md](./contracts/verify-workflow.md).

## Self-hosted runner

| Field | Value |
|-------|-------|
| Scope | repository `Yoi-Nami-Ra/swiftSky` only (FR-009) |
| Folder | `~/actions-runner/swiftSky` |
| Name | `swiftsky-<short host name>` |
| Labels | `self-hosted`, `macOS`, `ARM64` (automatic), `xcode-27` (given) |
| Runs as | the developer's macOS user, LaunchAgent, at login (FR-008a) |

States, as the host shows them: **Offline** (Mac off, asleep or service stopped) → **Idle** (online, no
job) → **Active** (running a job) → Idle. Jobs queue while no runner is Idle; the host cancels a job
queued for 24 hours.

## Verification job result

Per commit (push to `main`) or per pull request head: **queued → in progress → success | failure |
cancelled**. `failure` includes the 30-minute limit. `cancelled` happens to a pull-request run superseded
by a newer push, or to a run queued 24 hours. Only `success` permits a merge (FR-014).
