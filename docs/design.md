# Design

## Single-file bash script

bb-bash is one executable script (`bbb` on disk). Dependencies: `curl`, `jq`. No build step, no package manager.

## Sections

The script is divided into clearly-labeled sections (line numbers shift over time — refer by label):

1. **Usage docstring** — header comment doubles as inline help
2. **Helpers** — `die`, `resolve_script_dir`, `require_args`, `require_numeric`, `require_pipeline_scan` (validates `BB_BASH_PIPELINE_SCAN` and publishes the `PIPELINE_SCAN` global — must be called as a plain statement in the caller's shell, never in a subshell), `urlencode`, `resolve_workspace_repo`, `batch_action`, and the `JQ_NORM` jq prelude that normalizes Bitbucket state vocabularies for every renderer. `resolve_script_dir` is defined here (not in the top-level guard) so tests can source bbb and exercise it directly; it anchors `.env` discovery to the real script directory by following symlinks portably (no `readlink -f`).
3. **API helpers** — `api_get`, `api_get_paged`, `api_post` (GET/POST support `--soft`), `api_put`, `api_delete`
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

`api_get --soft`, `api_post --soft` and `api_put --soft` change the on-error behavior:

| Mode | HTTP <400 | HTTP >=400 |
|---|---|---|
| Default | echo body, exit 0 | extract `error.message`, call `die`, exit 1 |
| `--soft` | echo body, exit 0 | echo body, **return 1** (no die) |

Soft mode is used by:

- Batch commands (`pr approve`, `pr decline`, `pr request-changes`, `pr draft`, `pr ready`) — one failure shouldn't kill the whole loop. `pr draft` / `pr ready` are why `api_put` has a soft mode at all: they go through `batch_action --method=PUT`, and without it the first bad id would `die` and the remaining ids would never be called.
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

## Collection pagination

`api_get_paged <endpoint>` is the shared reader for Bitbucket collection responses. It calls `api_get` page by page and emits one JSON object whose `.values` array contains the merged values, preserving the ordinary API and transport-error contract.

Bitbucket's `.next` value is absolute. The helper follows it only when it begins with the current repository `BASE_URL` and its raw path exactly matches the initial collection path; it then strips the base prefix and gives the repository-relative endpoint back to `api_get`. A different host, repository, or collection path is fatal. Exact raw-path pinning rejects literal and percent-encoded traversal before curl can normalize it, preventing response-controlled pagination data from redirecting an authenticated request.

`BB_BASH_MAX_PAGES` bounds the loop (default 100, allowed 1-1000). Reaching the cap with a remaining `.next` preserves valid merged JSON on stdout and prints a truncation warning on stderr. A reader is therefore either complete or visibly partial.

Use complete pagination for normal user-facing collections (`pr list`, comments, commit statuses, and pipeline steps). Do not apply it to deliberately bounded views: pipeline discovery uses `BB_BASH_PIPELINE_SCAN`, and diffstat uses one 100-item page plus its existing truncation notice.

Comments are sorted only after all pages have been merged. Their public output order is newest-first across the whole result, never merely newest-first within each page.

## Error handling philosophy

- `die <msg>` — print to stderr with `Error:` prefix, `exit 1`
- API helpers `die` on HTTP >=400 by default (fail fast for single-PR commands)
- `--soft` flag opts into continue-on-error semantics (batch and optional endpoints)
- All command functions run under `set -euo pipefail`
- User-input-to-JSON always goes through `jq --arg` or `jq -Rs` (eliminates JSON-injection class of bugs)

## Draft state: a flag on the PR, not a state

Verified live against Bitbucket Cloud (bb-bash-smx, 2026-08-07). A draft PR is `state=OPEN` with `draft=true` — `draft` is a separate boolean on the PR object, present on `GET /pullrequests` (list) and `GET /pullrequests/<id>` alike. So `--state` keeps its existing vocabulary and gains no `draft` value: filtering by state would misrepresent the API and collide with `open|merged|declined|superseded|all`. `pr list` marks a draft with a `[draft]` token **after** the state bracket rather than replacing it, so anything parsing `[OPEN]` keeps working.

**A draft-only PUT needs no title; a destination-only PUT does.** This pair is the point — they look alike and behave oppositely. `cmd_pr_update` carries a read-back-and-resend workaround because Bitbucket rejects a `PUT {destination}` unless a `title` rides along (see the comment at its `dest_set` branch). `PUT {"draft":false}` has no such requirement: it succeeds alone, the title survives, and `description` and `reviewers` are untouched. Do not copy the `--destination` precedent into `cmd_pr_draft` — it would add a round trip for nothing.

Two more verified facts: setting `draft` to the value it already holds returns 200 with that value, so `pr draft` / `pr ready` are idempotent with no "nothing to do" arm to write (contrast `cmd_pr_unrequest_changes`, whose 404 arm exists precisely because DELETE could not distinguish "no changes-request" from "no such PR"). And `pr decline` on a draft leaves `state=DECLINED, draft=false` — declining clears the flag.

## Raw escape hatches: four verbs, not `--method=`

`raw` (GET), `raw-post`, `raw-put` and `raw-delete` are separate commands rather than one `raw --method=<verb>`. The API helpers they wrap do not have a common shape: `api_put` returns a response body, while `api_delete` returns only an HTTP status code (`curl -o /dev/null -w "%{http_code}"`). A single `--method=` command would have to branch on the method internally to decide whether to pipe through `jq`, and would need a conditional argument count, since PUT takes a payload and DELETE does not. Separate verbs keep `require_args` exact per command and make the output difference visible in the help text instead of hiding it. A future PATCH would be added the same way.

`raw-delete` **dies on HTTP >=400**, whereas `cmd_pr_delete_comment` prints `Failed to delete comment N (HTTP 404)` and exits `0`. Not an inconsistency to be flattened: `pr delete-comment` names a specific comment and can afford a friendly line, but the escape hatch has no domain context, and its callers — a shell script under `set -e`, or an agent reading the exit status rather than parsing stdout — need the failure in the exit code. (Whether `pr delete-comment` should also fail loudly is a separate question, deliberately left alone here.)

## Shared renderers

`render_diffstat <pr_id> [--totals]` is the single renderer for `/diffstat`, used by both `pr show` (file list) and `pr diff --stat` (totals + file list). It exists because the same rendering in two commands drifts: `pr show` already had the jq for it, and `--stat` would have been a second copy.

Two decisions ride in it. It fetches **once** and renders both the totals and the list from that body, so a caller wanting both does not pay for the endpoint twice. And it requests `pagelen=100` (Bitbucket's cap) with a `.next` check, because the endpoint's default page silently truncated wide PRs. For a file list that is merely incomplete; for `--stat` it would be a *wrong number*, so the count is rendered as `100+` when more exist rather than a flat, confidently incorrect `100`. Same reasoning as the pipeline scan-window hint: do not print a figure the data does not support.

## Known constraints

- **Token in process listings.** `curl -u email:token` puts credentials in process args, visible via `ps` on the same user. Acceptable for personal CLI; for shared systems use `curl --config -` pattern (deferred to `bb-bash-oja`).
- **`pr update --reviewers` uses usernames.** Bitbucket is deprecating username as a stable identifier. UUID/account_id migration tracked in bb-bash-oja.
- **`pr list --reviewer` not implemented.** BBQL doesn't support filtering on `reviewers.username` (only `reviewers.uuid`). Workaround: pipe `pr list --state=all` through `jq` for client-side filter.
- **Auto-detect requires git in PATH.** When falling back to env vars (step 4), git is not invoked.
