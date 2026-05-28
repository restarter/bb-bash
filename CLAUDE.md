# Project Instructions for AI Agents

This file provides instructions and context for AI coding agents working on this project.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->


## Build & Test

No build step. Single bash script.

```bash
# Lint
shellcheck bbb test/test_helper.bash scripts/install.sh

# Tests (bats-core 1.x — install via 'brew install bats-core' or build from source)
bats test/*.bats

# Live API tests (optional, hits real Bitbucket — see docs/contributing.md)
BB_BASH_TEST_LIVE=1 ... bats test/test_live.bats
```

CI: see `.github/workflows/ci.yml` — runs shellcheck + bats on push/PR (SHA-pinned actions, bats-core installed from upstream).

## Architecture Overview

Single-file bash script (`bbb`), divided into clearly-labeled sections. See [docs/design.md](docs/design.md) for full details. Quick map:

1. Usage docstring (header comment)
2. Helpers (`die`, `resolve_script_dir`, `require_args`, `resolve_workspace_repo`, `batch_action`)
3. API helpers (`api_get`, `api_post` with `--soft`; `api_put`, `api_delete`)
4. Commands (`cmd_pr_*`, `cmd_raw*`)
5. `usage()`
6. `main()` router
7. Top-level guard (`[[ "${BASH_SOURCE[0]}" == "${0}" ]]`) so imperative setup runs only on direct invocation

Auto-detect precedence and URL parsing live in [docs/design.md](docs/design.md) (authoritative).

## Conventions & Patterns

- `set -euo pipefail` at script top — never remove
- All function names lowercase_with_underscores; commands named `cmd_<group>_<action>`
- `die <msg>` for fatal errors (never bare `exit 1`)
- `require_args <N> $# "Usage: ..."` for argument count checks
- Output: plain text, **no emojis** (consistency across commands)
- All JSON parsing via `jq` — never grep/sed
- All user input into JSON via `jq --arg` or `jq -Rs` (never naive concatenation)
- POSIX-portable bash (no bash-4-only features — script may run on macOS bash 3.2)
- Batch commands use `batch_action` helper (see [docs/contributing.md](docs/contributing.md))
- Tests assert both response parsing AND outbound payload (via `last_curl_call`)

### Adding a new command

1. Add `cmd_pr_<name>()` function near related commands
2. Add to router's `pr` subcommand `case` block
3. Add to `usage()` help text
4. Update README usage + add full entry in `docs/commands.md`
5. Add bats test in `test/test_pr_commands.bats` (with payload assertion)
6. Add line to `CHANGELOG.md [Unreleased]`

Full contributing guide: [docs/contributing.md](docs/contributing.md).
