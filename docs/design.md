# Design

## Single-file bash script

bb-bash is one executable script (`bbb` on disk). Dependencies: `curl`, `jq`. No build step, no package manager.

## Sections

The script is divided into clearly-labeled sections (line numbers shift over time — refer by label):

1. **Usage docstring** — header comment doubles as inline help
2. **Helpers** — `die`, `resolve_script_dir`, `require_args`, `require_numeric`, `require_pipeline_scan` (validates `BB_BASH_PIPELINE_SCAN` and publishes the `PIPELINE_SCAN` global — must be called as a plain statement in the caller's shell, never in a subshell), `urlencode`, `resolve_workspace_repo`, `batch_action`, and the `JQ_NORM` jq prelude that normalizes Bitbucket state vocabularies for every renderer. `resolve_script_dir` is defined here (not in the top-level guard) so tests can source bbb and exercise it directly; it anchors `.env` discovery to the real script directory by following symlinks portably (no `readlink -f`).
3. **API helpers** — `api_get`, `api_post` (both with `--soft`), `api_put`, `api_delete`
4. **Commands** — `cmd_pr_*`, `cmd_pipeline_*`, `cmd_raw*` functions, plus the shared `pipelines_for_pr` / `pipeline_step_log` helpers they build on
5. **`usage()`** — printed help text
6. **`main()` router** — `case` dispatch for `pr <subcmd>`, `pipeline <subcmd>`, `raw`, `raw-post`
7. **Top-level guard** — `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` so the script can be sourced by tests as a library; imperative setup (resolve, BASE_URL, AUTH, main "$@") runs only on direct invocation

## Auto-detect precedence (authoritative)

When `resolve_workspace_repo` runs at script start, it resolves `WORKSPACE` and `REPO` in this order:

1. **`BB_BASH_REMOTE=<name>` env var** — use this exact remote's URL
2. **`origin` remote** if its URL matches `(^|@|/)bitbucket\.org[:/]`
3. **First remote** whose URL matches `(^|@|/)bitbucket\.org[:/]` (covers `bb`, `bitbucket`, `upstream`, ...)
4. **Fallback** to `BB_BASH_WORKSPACE` + `BB_BASH_REPO` env vars
5. **Error** with a multi-line help message listing the four resolution sources attempted

Each step short-circuits as soon as it produces a parseable URL.

## URL parsing

Two formats supported:

- SSH: `git@bitbucket.org:workspace/repo.git`
- HTTPS: `https://[user@]bitbucket.org/workspace/repo.git`

Normalization order (per source URL):

1. Strip trailing `/`
2. Strip `.git` suffix
3. Strip trailing `/` again (catches `.git/`)
4. Drop everything up to and including `bitbucket.org[:/]`
5. `WORKSPACE` = first path segment; `REPO` = second path segment (additional path segments dropped)
6. Validate both against `^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,99}$`

## Host-match safety

The check `[[ "$url" =~ (^|@|/)bitbucket\.org[:/] ]]` uses anchored regex to reject false positives like:

- `git@evil.bitbucket.org.attacker.com:foo/bar.git` (the literal `bitbucket.org` appears but not in the host position)
- `https://example.com?ref=bitbucket.org/...` (in query, not host)

## Env precedence (full)

| Source | Purpose | Precedence |
|---|---|---|
| `.env` next to the real script (symlinks resolved via `resolve_script_dir`) | email/token (rarely changes) | Loaded first if file exists |
| Shell env vars | Override for one-off invocations | Overrides `.env` |
| `git remote` URLs (via `resolve_workspace_repo`) | Workspace/repo per cwd | Last resort, only if no env override |

## `--soft` mode

`api_get --soft` and `api_post --soft` change the on-error behavior:

| Mode | HTTP <400 | HTTP >=400 |
|---|---|---|
| Default | echo body, exit 0 | extract `error.message`, call `die`, exit 1 |
| `--soft` | echo body, exit 0 | echo body, **return 1** (no die) |

Soft mode is used by:

- Batch commands (`pr approve`, `pr decline`, `pr request-changes`) — one failure shouldn't kill the whole loop
- Optional endpoints (`pr checks` pipelines) — degrade gracefully when token lacks scope. `pr logs` / `pipeline log` use `--soft` only to give a readable message before dying: the scope is mandatory for them, there is nothing to degrade to.

Note that `--soft` governs only HTTP status, not the `curl` invocation itself: every `api_*` helper `die`s on a non-zero `curl` exit (a DNS/TLS/connection failure), soft mode or not, so a transport error is never mistaken for an empty successful response.

Callers under `set -e` (which the script enables at top) SHOULD use the `if … then … else … fi` form when invoking `--soft`. A bare `x=$(api_get --soft …) || …` is safe **only** when the assignment stands alone (a separate `local x` declaration first): `local x=$(…) || …` masks the exit status because `local` itself succeeds. `pipelines_for_pr` uses the `if` form; the `|| return 1` sites in it keep the declaration separate.

```bash
if resp=$(api_post --soft "$endpoint" "{}"); then
    # success branch
else
    # failure branch — see the subshell caveat below
fi
```

**The `$( )` swallows the transport `die`.** The guarantee above holds inside the helper, not at the call site: `die` runs in the command substitution's subshell, so it exits *that* subshell, prints to stderr, and hands the caller nothing but a non-zero status — indistinguishable from the `--soft` HTTP-error return. The failure branch then parses an empty body, and `jq`'s `// "unknown error"` fallback does not fire on empty input (it falls through on `null`/`false`, and there is no input value at all), so the caller reports a blank error and carries on. `batch_action` shipped exactly that bug: a dead network printed `error:` with no message for every id and the batch still exited `0`.

So in the failure branch, **an empty body is not an HTTP error** — it means the helper died. Treat it as fatal:

```bash
else
    if [[ -z "$resp" ]]; then
        die "empty response from Bitbucket at PR #${id} (network failure, or an empty error body) - batch aborted"
    fi
    # real HTTP error: parse the body
fi
```

## Error handling philosophy

- `die <msg>` — print to stderr with `Error:` prefix, `exit 1`
- API helpers `die` on HTTP >=400 by default (fail fast for single-PR commands)
- `--soft` flag opts into continue-on-error semantics (batch and optional endpoints)
- All command functions run under `set -euo pipefail`
- User-input-to-JSON always goes through `jq --arg` or `jq -Rs` (eliminates JSON-injection class of bugs)

## Known constraints

- **Token in process listings.** `curl -u email:token` puts credentials in process args, visible via `ps` on the same user. Acceptable for personal CLI; for shared systems use `curl --config -` pattern (deferred to `bb-bash-oja`).
- **`pr update --reviewers` uses usernames.** Bitbucket is deprecating username as a stable identifier. UUID/account_id migration tracked in bb-bash-oja.
- **`pr list --reviewer` not implemented.** BBQL doesn't support filtering on `reviewers.username` (only `reviewers.uuid`). Workaround: pipe `pr list --state=all` through `jq` for client-side filter.
- **Auto-detect requires git in PATH.** When falling back to env vars (step 4), git is not invoked.
