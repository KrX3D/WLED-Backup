# Driving WLED-Backup PRs to green

Repo-specific notes for an agent driving this repo's PRs to a mergeable state.

## Fast local checks (run before every push)

- `shellcheck backup-scripts/*.sh` — must be clean. Both scripts run under
  `set -euo pipefail`; keep them ShellCheck-clean rather than suppressing
  warnings.
- `docker build -f DOCKERFILE .` — the image must still build.
- There is no application test suite. These two checks are the whole local
  gate.

## CI layout

- `.github/workflows/ci.yml` builds and pushes `ghcr.io/krx3d/wled-backup`
  on `push` to `main` and on `v*.*.*` tags. It does **not** run on pull
  requests, and it has `packages: write` — never trigger or extend it from
  a PR context.
- `.github/workflows/pr-checks.yml` is what actually runs on PRs: ShellCheck
  over `backup-scripts/` and a Docker build with `push: false`. Treat these
  as the PR's required checks.
- A `v*.*.*` tag push must produce an image tagged with that version, not
  just `:latest` (see `docker/metadata-action` usage in `ci.yml`) — don't
  regress this when touching the workflow.

## Merge conflicts

No lockfiles or generated files exist in this repo, so a conflict is a
plain content conflict — resolve it directly, no regeneration step needed.

## Scope

This is a small, single-purpose backup tool (two bash scripts, a
Dockerfile, one CI workflow). Keep fixes minimal and match the existing
style (plain bash, `LOG` helper, no external bash frameworks) rather than
introducing new tooling or abstractions.
