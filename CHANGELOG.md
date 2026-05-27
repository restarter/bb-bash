# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `docs/bb-api-rule.md` — drop-in Claude Code rule (`.claude/rules/bb-api-rule.md`) so AI agents auto-discover bb-api as the canonical Bitbucket-PR tool. Short, always-on hint. (bb-api-k9i)
- `docs/bb-api-skill/SKILL.md` — drop-in Claude Code skill (`.claude/skills/bb-api/SKILL.md`) with full command reference + review/respond/cleanup workflows. Lazy-loaded — zero context cost until invoked. (bb-api-k9i)
- `bb-api install-agent` subcommand — drops AI-agent integration artifacts into `$PWD` with combinable flags (`--rule`, `--skill`, `--claudemd`, `--agents`). Interactive prompt when no flag is given. `--dry-run` previews without writing; `--force` overwrites/re-appends. `BB_API_REF` env var pins the ref (default `main`). Top-level guard skips auth/repo resolution for this subcommand so it runs without `.env` or outside a Bitbucket repo. (bb-api-k9i)
- `docs/bb-api-agent-snippet.md` — clean, no-wrapper version of the bb-api CLAUDE.md section. Used by `install-agent --claudemd` / `--agents` as the canonical source. (bb-api-k9i)
- `stub_curl_download` helper in `test/test_helper.bash` — bats stub for `curl ... -o file` style download (complement to existing `stub_curl` API-call stub). (bb-api-k9i)
- README "For AI agents" section now lists three integration paths (CLAUDE.md snippet, rule, skill) with copy-paste curl one-liners for the rule and skill, plus a new "One-shot install" section showcasing `bb-api install-agent`.

### Changed
- README fully reframed around the AI-agent use case. Lead promises "tell your agent → done in a minute"; Quick Start is now a ready-to-paste prompt that walks an AI coding agent through running the installer, dropping integration artifacts, and prompting the user for credentials. Adds a "What ships out of the box" table contrasting CLAUDE.md / AGENTS.md / rule / skill, surfaces the session-restart caveat for rule/skill loading, and moves Security / Limitations / Authentication below the agent flow. Cross-tool focus broadened beyond Claude Code (Cursor, Copilot, Codex, Aider). (bb-api-k9i)
- `docs/CLAUDE.md.example` refactored from embedded code-fence wrapper into a short pointer document. The canonical snippet now lives in `docs/bb-api-agent-snippet.md`. Cross-links to all three artifact files + recommends `bb-api install-agent`. (bb-api-k9i)
- `bb-api` top-level guard now short-circuits auth/repo resolution for `install-agent` / `help` subcommands so they run without `.env` or a Bitbucket-repo CWD. `usage()` uses defensive defaults (`${WORKSPACE:-<workspace>}`) so it renders correctly through the short-circuit path. (bb-api-k9i)

## [0.1.1] - 2026-05-27

### Fixed
- `scripts/install.sh` failed under `curl --proto '=https' --tlsv1.2 -fsSL ... | bash` with `BASH_SOURCE[0]: unbound variable` because the entry-point guard dereferenced an empty array under `set -u`. Replaced `${BASH_SOURCE[0]}` with `${BASH_SOURCE[0]:-$0}` so the guard works in both direct-invoke and stdin-pipe modes. Added a bats regression test (`test/test_install_helpers.bats`) that feeds the script via stdin and asserts the guard does not trip `set -u`. (bb-api-bhf)

### Added
- `scripts/install.sh` — one-line curl-pipe-bash installer:
  `curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/restarter/bb-api/main/scripts/install.sh | bash`
  Installs the latest tagged release into `~/.local/share/bb-api/` and symlinks it into `/usr/local/bin/` (writable) or `~/.local/bin/`. On first install creates `.env` from `.env.example` (chmod 600 via `umask 077`); never overwrites `.env` on update. Refreshes `.env.example` (chmod 644) each run so users can diff for new variables. Writes a `VERSION` marker for skip-if-same-tag fast path. Hardened curl flags (`--proto =https --tlsv1.2 --max-redirs 5`); fetches from `/releases/latest`; SemVer-whitelists the tag before interpolating into download URLs.
- `BB_API_USER_ONLY=1` env var — force `~/.local/bin` install regardless of `/usr/local/bin` writability.
- `BB_API_FORCE=1` env var — override the refusal to overwrite a pre-existing non-symlink at the target PATH location.

## [0.1.0] - 2026-05-27

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
- `resolve_script_dir()` helper in `bb-api` — portable, cycle-safe symlink resolution (macOS bash 3.2 compatible; no `readlink -f` / `realpath` needed). Refuses cycles via a 40-hop cap; dies with a contextual message on broken symlinks; uses logical `pwd` so symlinks in the parent directory chain are preserved.

### Changed
- **BREAKING:** `pr approve <id>` now accepts 1+ IDs (batch); per-PR output line instead of single-line summary
- **BREAKING:** `pr inline-old` removed; use `pr inline --old <id> <path> <line> <text>` instead
- **BREAKING:** `BB_API_WORKSPACE` and `BB_API_REPO` no longer required at load time — auto-detected from git remote. Still accepted as env-var override for invocations outside a git repo (or to force a specific repo)
- `.env.example` slimmed to credentials (`BB_API_EMAIL`, `BB_API_TOKEN`) + optional `BB_API_REMOTE`
- `bb-api` `SCRIPT_DIR` now resolves symlinks before computing the script's directory, so `.env` discovery works when bb-api is invoked through a symlink (e.g. `/usr/local/bin/bb-api -> ~/.local/share/bb-api/bb-api`). Existing direct invocations (cloned-into-place install, tests sourcing bb-api) behave identically — only the symlink path changes.

### Known limitations
- `pr list --reviewer=<user>` not implemented in this release: Bitbucket BBQL doesn't support `reviewers.username` filtering. Workaround: filter the output of `pr list` with `jq`. Tracked in bb-api-oja.
- `pr update --reviewers=u1,u2` passes Bitbucket usernames. Bitbucket has been deprecating username as a stable identifier — `account_id` / `uuid` migration tracked in bb-api-oja.

### Migration Notes
- If you relied on `bb-api pr inline-old ...`, rewrite as `bb-api pr inline --old ...`
- If you scripted `bb-api pr approve <id>` and parsed its single-line output, the format is now per-PR (`PR #<id> approved by <name>`)
- If your `.env` had `BB_API_WORKSPACE`/`BB_API_REPO`, you can remove them — auto-detect from git remote will resolve them. Keep them if your invocations happen outside a git repo
- Tokens now also need `read:pipeline:bitbucket` scope if you want `pr checks` to show Bitbucket Pipelines data (gracefully omitted if not granted)
