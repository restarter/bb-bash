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

1. Add a `cmd_<group>_<name>()` function in `bbb`, placed near related commands
2. Add a case to the router (a new top-level group, like `pipeline`, needs its own nested `case` block)
3. Add a usage line to `usage()` and to the header docstring
4. Update `README.md` Usage section + add a full entry in [`docs/commands.md`](commands.md)
5. Add bats tests in `test/test_pr_commands.bats` — **assert both** response parsing AND outbound payload (via `last_curl_call`)
6. Add a line to `CHANGELOG.md [Unreleased]`
7. Reflect the command and any new caveat in **all three** AI artifacts — [`bb-bash-rule.md`](agents/bb-bash-rule.md), [`bb-bash-snippet.md`](agents/bb-bash-snippet.md), [`bb-bash-skill/SKILL.md`](agents/bb-bash-skill/SKILL.md). They are deliberately kept at factual parity so a user can pick any one; see [`agents/README.md`](agents/README.md)

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

**`batch_action` is POST-only.** It calls `api_post --soft` and formats the response body with the jq expression you pass. A batch command whose verb is `DELETE` cannot use it: `api_delete` sends no body and returns only the HTTP status code, so there is nothing for the jq expression to read. Such a command hand-rolls the same loop shape instead — per-id `require_numeric`, continue on failure, the same `BB_BASH_BATCH_DELAY` between calls — and branches on the status code. `cmd_pr_unrequest_changes` is the reference example. Keep the loop shape identical so the two read alike; in particular use a plain `if` for the inter-call sleep, never `[[ cond ]] && sleep …`, which returns 1 as the loop body's last command and fails the function under `set -e` on every single-id call.

## Renderers shared by two commands

When two commands print the same API data, extract the rendering rather than copying the jq. `render_diffstat <pr_id> [--totals]` is the reference: `pr show` calls it for the file list, `pr diff --stat` calls it with `--totals` for the summary line as well.

Shape to copy:

```bash
render_foo() {
    local id="$1" extra=0
    [[ "${2:-}" == "--extra" ]] && extra=1
    local body
    body=$(api_get "/foo/${id}?pagelen=100")     # fetch ONCE, render many
    [[ $extra -eq 1 ]] && echo "$body" | jq -r '<summary>'
    echo "$body" | jq -r '<list>'
}
```

Two rules the reference follows. **One fetch per call** — a caller that needs both a summary and a list must not pay for the endpoint twice, so the body is captured into a variable and each renderer reads that. And **the optional part is opt-in, not the default**: adding the totals line to `pr show` would have changed the output of a shipped command for no reason, so the extra line belongs to the caller that asked for it.

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

For multi-call commands (`pr checks` makes 3 API calls; `pr logs` makes 4; `pr merge` may make 2) use `stub_curl_seq`. Queue depth is itself an assertion — the stub exits 99 when a command asks for more responses than were queued, so an under-queued sequence fails loudly rather than silently returning empty:

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
