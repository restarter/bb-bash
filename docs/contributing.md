# Contributing

## Local setup

```bash
brew install shellcheck bats-core jq         # macOS
sudo apt install shellcheck jq                # Debian/Ubuntu (note: apt 'bats' is the unmaintained 0.4 line)
# For bats-core 1.x on Linux, install from source:
#   git clone --depth 1 --branch v1.11.0 https://github.com/bats-core/bats-core.git /tmp/bats
#   sudo /tmp/bats/install.sh /usr/local
```

## Running tests

```bash
shellcheck bbb test/test_helper.bash scripts/install.sh
bats test/*.bats
```

### macOS bash 3.2

CI runs on ubuntu-24.04 (bash 5.x, GNU `readlink`). bbb and `scripts/install.sh` target macOS bash 3.2 too (BSD `readlink`, no `mapfile`, empty-array `set -u` quirks). Run the full bats suite locally on macOS before pushing — these bugs won't surface in CI:

```bash
/bin/bash --version   # confirm 3.2.x — the macOS system bash
bats test/*.bats
```

## Live-API tests (optional)

These hit a real Bitbucket repo. Use a sandbox, not production.

```bash
BB_BASH_TEST_LIVE=1 \
  BB_BASH_EMAIL=... BB_BASH_TOKEN=... \
  BB_BASH_TEST_WORKSPACE=ws BB_BASH_TEST_REPO=repo \
  bats test/test_live.bats
```

Skipped by default.

## Adding a new command

1. Add a `cmd_pr_<name>()` function in `bbb`, placed near related commands
2. Add a case to the router's `pr` subcommand block
3. Add a usage line to `usage()`
4. Update `README.md` Usage section + add a full entry in [`docs/commands.md`](commands.md)
5. Add bats tests in `test/test_pr_commands.bats` — **assert both** response parsing AND outbound payload (via `last_curl_call`)
6. Add a line to `CHANGELOG.md [Unreleased]`

## Code style

- `set -euo pipefail` at script top — never remove
- Function names lowercase_with_underscores; commands named `cmd_<group>_<action>`
- `die <msg>` for fatal errors; never bare `exit 1`
- `require_args <N> $# "Usage: ..."` for argument count checks
- Output: plain text, **no emojis** (consistency across all commands)
- All JSON parsing via `jq` — never grep/sed JSON
- All user input into JSON via `jq --arg` or `jq -Rs` (never naive concatenation)
- POSIX-portable bash (no bash-4-only features like `${var,,}` — script may run on macOS bash 3.2)

## Batch commands

Batch commands use the `batch_action` helper. Two-line wrapper:

```bash
cmd_pr_foo() {
    require_args 1 $# "Usage: bbb pr foo <id> [id ...]"
    batch_action "foo-ed" "/pullrequests/{id}/foo" '.state // "FOOED"' "$@"
}
```

`batch_action` handles: ID iteration, `api_post --soft` calls, per-PR status formatting, success/error branches, sleep between calls (configurable via `BB_BASH_BATCH_DELAY`).

## Testing pattern (REQUIRED)

Always capture outbound payload to catch wrong-field bugs. The `last_curl_call` helper returns the most recent curl invocation args:

```bash
@test "pr foo: sends correct field" {
    stub_curl '{"state":"FOOED"}' 200
    run cmd_pr_foo 42
    [ "$status" -eq 0 ]
    [[ "$(last_curl_call)" == *'"expected_field":"value"'* ]]
}
```

For multi-call commands (`pr checks` makes 3 API calls; `pr merge` may make 2) use `stub_curl_seq`:

```bash
stub_curl_seq \
    '{"first":"response"}|||200' \
    '{"second":"response"}|||200' \
    '{"error":{"message":"x"}}|||403'
```

## Coverage

bats has no native coverage tool. Approach is qualitative: one happy-path + one failure-path per command. Sufficient for a ~400-line script. If the suite ever grows past ~500 tests, consider `bashcov`.

## Commit convention

Conventional commits with `bb-bash-XXX` beads task ID as scope:

- `feat(bb-bash-XXX): add 'pr foo' command`
- `fix(bb-bash-XXX): handle empty response in pr bar`
- `docs(bb-bash-XXX): update commands.md for new flags`
- `test(bb-bash-XXX): cover edge case`
- `ci(bb-bash-XXX): bump action SHA`
- Breaking change: append `!` → `feat(bb-bash-XXX)!: ...` + describe migration in commit body

Pre-rename commits in git history use the older `bb-api-XXX` scope (immutable). The beads tasks themselves were renamed via `bd rename-prefix`, so `bd show bb-bash-XXX` resolves to the same issue.

## When to update docs

| Change | Update |
|---|---|
| New command / flag | README Usage + `docs/commands.md` + CHANGELOG `[Unreleased]` |
| Auto-detect logic | `docs/design.md` (authoritative) — README and CLAUDE.md link here |
| New env var | `docs/commands.md` Environment section + `.env.example` if applicable |
| Breaking change | CHANGELOG `### Changed` + `### Migration Notes` |
| New scope requirement | README setup section + per-command notes in `docs/commands.md` |

## scripts/

`scripts/install.sh` — the curl-pipe-bash installer. Shellchecked in CI alongside `bbb`. Pure-function helpers (`pick_install_dir`, `path_contains`, `extract_tag_name`, `_resolve_symlink_chain`, `find_bbb_on_path`) covered by `test/test_install_helpers.bats`. The `resolve_script_dir` helper in `bbb` (used at startup to anchor `.env` discovery through symlinks) is covered by `test/test_script_dir.bats`.

When bumping a release:

1. Land features on main under `[Unreleased]`.
2. Rename `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD` and open a fresh empty `[Unreleased]`.
3. `git tag -a vX.Y.Z -m "..." && git push origin vX.Y.Z`
4. Build release notes with `awk '/^## \[X\.Y\.Z\]/{p=1; next} /^## \[/{p=0} p' CHANGELOG.md > /tmp/notes.md`, validate non-empty (`[ -s /tmp/notes.md ]`), then `gh release create vX.Y.Z --notes-file /tmp/notes.md`.

Users picking up `curl ... | bash` get the new tag automatically — the installer queries `/releases/latest` and SemVer-whitelists the tag before fetching.

## A note on `.env`

bbb `source`s `.env` — any shell metacharacter executes on every invocation. Never put `$(...)`, backticks, or unmatched quotes in `.env` or `.env.example`. Switching bbb to a safe key=value parser is tracked as a follow-up.
