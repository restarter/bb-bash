# Commands Reference

Full reference for every `bb-api` command. For setup, see [../README.md](../README.md).

All commands die with non-zero exit on API error (unless noted). Output is plain text — pipe through `jq` if you need structured data (most commands wrap `jq` already; for raw JSON use `bb-api raw`).

---

## pr list

**Synopsis:** `bb-api pr list [--state=open|merged|declined|superseded|all] [--author=<user>]`

**Description:** List PRs in the resolved repo. Defaults to open PRs.

**Required scopes:** `read:pullrequest:bitbucket`

**Flags:**
- `--state=<state>` — `open` (default), `merged`, `declined`, `superseded`, `all`
- `--author=<user>` — Bitbucket username
- `--reviewer=<user>` — **not yet supported** (BBQL limitation, see Known Limitations in CHANGELOG)

**Example:** `bb-api pr list --state=merged --author=alice`

---

## pr create

**Synopsis:** `bb-api pr create <target_branch> "title" [description]`

**Description:** Create a PR from the current git branch to `<target_branch>`.

**Required scopes:** `write:pullrequest:bitbucket`

**Notes:** must be run from inside a git repo; source branch = current branch.

---

## pr show

**Synopsis:** `bb-api pr show <id>`

**Description:** PR details (title, author, branch, dates, description) + changed files diffstat.

**Required scopes:** `read:pullrequest:bitbucket`

---

## pr diff

**Synopsis:** `bb-api pr diff <id>`

**Description:** Full unified diff. Output is plain text — pipe to `less` or `delta`.

**Required scopes:** `read:pullrequest:bitbucket`

---

## pr checks

**Synopsis:** `bb-api pr checks <id>`

**Description:** Show PR-level statuses (external CI integrations) + Bitbucket Pipelines for the source branch. State vocabularies are normalized: `pass` / `running` / `fail` / `stopped`.

**Required scopes:** `read:pullrequest:bitbucket` (always); `read:pipeline:bitbucket` (for Pipelines portion — degrades gracefully if absent)

---

## pr open

**Synopsis:** `bb-api pr open <id>`

**Description:** Open the PR in your default browser. macOS uses `open`, Linux uses `xdg-open`, other platforms print the URL.

**Required scopes:** `read:pullrequest:bitbucket`

---

## pr comments

**Synopsis:** `bb-api pr comments <id>`

**Description:** List all comments (general + inline + replies). Excludes deleted comments.

**Required scopes:** `read:pullrequest:bitbucket`

---

## pr comment

**Synopsis:** `bb-api pr comment <id> <text>`

**Description:** Add a general (non-inline) comment to the PR.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr inline

**Synopsis:** `bb-api pr inline [--old] <id> <path> <line> <text>`

**Description:** Add an inline comment on a specific file:line. Omit `--old` for new/added code (default); include `--old` to comment on deleted/old-version code.

**Required scopes:** `write:pullrequest:bitbucket`

**Example:** `bb-api pr inline --old 42 src/auth.ts 10 "why was this removed?"`

---

## pr reply

**Synopsis:** `bb-api pr reply <pr_id> <comment_id> <text>`

**Description:** Reply to a comment in-thread.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr edit-comment

**Synopsis:** `bb-api pr edit-comment <pr_id> <comment_id> <text>`

**Description:** Edit (replace) the body of an existing comment.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr delete-comment

**Synopsis:** `bb-api pr delete-comment <pr_id> <comment_id>`

**Description:** Delete a comment. Use for cleaning up mistakes.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr approve

**Synopsis:** `bb-api pr approve <id> [id ...]`

**Description:** Approve one or more PRs. In batch mode (>1 ID), continues on per-item failure with a status line per PR.

**Required scopes:** `write:pullrequest:bitbucket`

**Example:** `bb-api pr approve 42 43 44`

---

## pr decline

**Synopsis:** `bb-api pr decline <id> [id ...]`

**Description:** Decline (close without merging) one or more PRs. Batch-capable like `approve`.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr merge

**Synopsis:** `bb-api pr merge <id> [--squash|--commit|--ff] [--delete-branch] [--message=<text>]`

**Description:** Merge a PR. Default strategy: `merge_commit`.

**Flags:**
- `--squash` — squash all commits into one
- `--commit` — explicit `merge_commit` (default)
- `--ff` — fast-forward only (fails if not possible)
- `--delete-branch` — delete source branch after merge (`close_source_branch: true`)
- `--message=<text>` — merge commit message (squash strategy)

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr update

**Synopsis:** `bb-api pr update <id> [--title=<t>] [--description=<d>] [--reviewers=u1,u2]`

**Description:** Update PR metadata via PUT.

**Required scopes:** `write:pullrequest:bitbucket`

**Important:** `--reviewers` performs **full replacement** (not append) — Bitbucket API has no PATCH semantics for the reviewers array. Existing reviewers not in the new list are removed. Reviewers passed as Bitbucket usernames (UUID migration tracked in bb-api-oja).

---

## raw / raw-post

**Synopsis:**
- `bb-api raw <endpoint>` — GET request
- `bb-api raw-post <endpoint> <json>` — POST request

**Description:** Direct API access for endpoints not wrapped. Endpoint is relative to `/repositories/{ws}/{repo}`. Output is raw JSON (pretty-printed via `jq`).

**Example:** `bb-api raw "/branch-restrictions"`

---

## Environment overrides

- `BB_API_REMOTE=<name>` — force a specific git remote for workspace/repo resolution
- `BB_API_WORKSPACE=<ws>` + `BB_API_REPO=<repo>` — bypass git remote auto-detect entirely
- `BB_API_BATCH_DELAY=<seconds>` — delay between batch API calls (default `0.3`; set `0` in tests)
- `BB_API_EMAIL` / `BB_API_TOKEN` — credentials (loaded from `.env` next to script by default)

See [design.md](design.md) for the full env precedence and auto-detect chain.
