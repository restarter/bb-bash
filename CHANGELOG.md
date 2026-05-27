# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `pr decline <id> [id ...]` — close PR without merging; batch-capable
- `pr merge <id> [--squash|--commit|--ff] [--delete-branch] [--message=...]` — merge PR; default strategy is `merge_commit`
- `pr checks <id>` — show PR statuses + Bitbucket Pipelines for the source branch; degrades gracefully when token lacks `read:pipeline` scope
- `pr open <id>` — open PR in default browser (macOS `open`, Linux `xdg-open`, fallback prints URL)
- `pr update <id> [--title=...] [--description=...] [--reviewers=u1,u2]` — edit PR metadata
- `pr list` filters: `--state=open|merged|declined|all`, `--author=<user>` (default `--state=open` preserves prior behavior)
- Auto-detect Bitbucket workspace/repo from the git remote in the current directory; supports `BB_API_REMOTE` override and scans for any `bitbucket.org` remote (`origin`, `bb`, `upstream`, ...). URL parser normalizes trailing slash and `.git`, validates parsed slugs, uses anchored regex for host matching
- `--soft` mode for the internal `api_post` and `api_get` helpers (returns body + non-zero exit instead of dying)
- `batch_action` internal helper used by all batch commands
- Top-level execution guard in `bb-api` (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`) so the script can be sourced as a library by tests
- bats smoke tests for helpers, PR commands, and live-API skeleton (gated by `BB_API_TEST_LIVE=1`)
- GitHub Actions CI: SHA-pinned shellcheck + bats-core 1.11.0 on push/PR
- `docs/` folder: `commands.md`, `design.md`, `contributing.md`, `CLAUDE.md.example`
- Project `CLAUDE.md`: filled-in Build & Test, Architecture, Conventions sections

### Changed
- **BREAKING:** `pr approve <id>` now accepts 1+ IDs (batch); per-PR output line instead of single-line summary
- **BREAKING:** `pr inline-old` removed; use `pr inline --old <id> <path> <line> <text>` instead
- **BREAKING:** `BB_API_WORKSPACE` and `BB_API_REPO` no longer required at load time — auto-detected from git remote. Still accepted as env-var override for invocations outside a git repo (or to force a specific repo)
- `.env.example` slimmed to credentials (`BB_API_EMAIL`, `BB_API_TOKEN`) + optional `BB_API_REMOTE`

### Known limitations
- `pr list --reviewer=<user>` not implemented in this release: Bitbucket BBQL doesn't support `reviewers.username` filtering. Workaround: filter the output of `pr list` with `jq`. Tracked in bb-api-oja.
- `pr update --reviewers=u1,u2` passes Bitbucket usernames. Bitbucket has been deprecating username as a stable identifier — `account_id` / `uuid` migration tracked in bb-api-oja.

### Migration Notes
- If you relied on `bb-api pr inline-old ...`, rewrite as `bb-api pr inline --old ...`
- If you scripted `bb-api pr approve <id>` and parsed its single-line output, the format is now per-PR (`PR #<id> approved by <name>`)
- If your `.env` had `BB_API_WORKSPACE`/`BB_API_REPO`, you can remove them — auto-detect from git remote will resolve them. Keep them if your invocations happen outside a git repo
- Tokens now also need `read:pipeline:bitbucket` scope if you want `pr checks` to show Bitbucket Pipelines data (gracefully omitted if not granted)
