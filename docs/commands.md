# Commands Reference

Full reference for every `bbb` command. For setup, see [../README.md](../README.md).

All commands die with non-zero exit on API error (unless noted). Output is plain text — pipe through `jq` if you need structured data (most commands wrap `jq` already; for raw JSON use `bbb raw`).

---

## pr list

**Synopsis:** `bbb pr list [--state=open|merged|declined|superseded|all] [--author=<user>]`

**Description:** List PRs in the resolved repo. Defaults to open PRs.

**Required scopes:** `read:pullrequest:bitbucket`

**Flags:**
- `--state=<state>` — `open` (default), `merged`, `declined`, `superseded`, `all`
- `--author=<user>` — Bitbucket username
- `--reviewer=<user>` — **not yet supported** (BBQL limitation, see Known Limitations in CHANGELOG)

**Example:** `bbb pr list --state=merged --author=alice`

---

## pr create

**Synopsis:** `bbb pr create <target_branch> "title" [description]`

**Description:** Create a PR from the current git branch to `<target_branch>`.

**Required scopes:** `write:pullrequest:bitbucket`

**Notes:** must be run from inside a git repo; source branch = current branch.

---

## pr show

**Synopsis:** `bbb pr show <id>`

**Description:** PR details (title, author, branch, dates, description) + changed files diffstat.

**Required scopes:** `read:pullrequest:bitbucket`

---

## pr diff

**Synopsis:** `bbb pr diff <id>`

**Description:** Full unified diff. Output is plain text — pipe to `less` or `delta`.

**Required scopes:** `read:pullrequest:bitbucket`

---

## pr checks

**Synopsis:** `bbb pr checks <id>`

**Description:** Show PR-level statuses (external CI integrations) + Bitbucket Pipelines for the source branch. State vocabularies are normalized: `pass` / `running` / `fail` / `stopped`.

**Required scopes:** `read:pullrequest:bitbucket` (always); `read:pipeline:bitbucket` (for Pipelines portion — degrades gracefully if absent)

---

## pr open

**Synopsis:** `bbb pr open <id>`

**Description:** Open the PR in your default browser. macOS uses `open`, Linux uses `xdg-open`, other platforms print the URL.

**Required scopes:** `read:pullrequest:bitbucket`

---

## pr comments

**Synopsis:** `bbb pr comments <id>`

**Description:** List all comments (general + inline + replies). Excludes deleted comments.

**Required scopes:** `read:pullrequest:bitbucket`

---

## pr comment

**Synopsis:** `bbb pr comment <id> <text>`

**Description:** Add a general (non-inline) comment to the PR.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr inline

**Synopsis:** `bbb pr inline [--old] <id> <path> <line> <text>`

**Description:** Add an inline comment on a specific file:line. Omit `--old` for new/added code (default); include `--old` to comment on deleted/old-version code.

**Required scopes:** `write:pullrequest:bitbucket`

**Example:** `bbb pr inline --old 42 src/auth.ts 10 "why was this removed?"`

---

## pr reply

**Synopsis:** `bbb pr reply <pr_id> <comment_id> <text>`

**Description:** Reply to a comment in-thread.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr edit-comment

**Synopsis:** `bbb pr edit-comment <pr_id> <comment_id> <text>`

**Description:** Edit (replace) the body of an existing comment.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr delete-comment

**Synopsis:** `bbb pr delete-comment <pr_id> <comment_id>`

**Description:** Delete a comment. Use for cleaning up mistakes.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr approve

**Synopsis:** `bbb pr approve <id> [id ...]`

**Description:** Approve one or more PRs. In batch mode (>1 ID), continues on per-item failure with a status line per PR.

**Required scopes:** `write:pullrequest:bitbucket`

**Example:** `bbb pr approve 42 43 44`

---

## pr decline

**Synopsis:** `bbb pr decline <id> [id ...]`

**Description:** Decline (close without merging) one or more PRs. Batch-capable like `approve`.

**Required scopes:** `write:pullrequest:bitbucket`

---

## pr merge

**Synopsis:** `bbb pr merge <id> [--squash|--commit|--ff] [--delete-branch] [--message=<text>]`

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

**Synopsis:** `bbb pr update <id> [--title=<t>] [--description=<d>] [--reviewers=u1,u2]`

**Description:** Update PR metadata via PUT.

**Required scopes:** `write:pullrequest:bitbucket`

**Important:** `--reviewers` performs **full replacement** (not append) — Bitbucket API has no PATCH semantics for the reviewers array. Existing reviewers not in the new list are removed. Reviewers passed as Bitbucket usernames (UUID migration tracked in bb-api-oja).

---

## raw / raw-post

**Synopsis:**
- `bbb raw <endpoint>` — GET request
- `bbb raw-post <endpoint> <json>` — POST request

**Description:** Direct API access for endpoints not wrapped. Endpoint is relative to `/repositories/{ws}/{repo}`. Output is raw JSON (pretty-printed via `jq`).

**Example:** `bbb raw "/branch-restrictions"`

---

## install-agent

**Synopsis:**
- `bbb install-agent [--rule] [--skill] [--claudemd] [--agents] [--dry-run] [--force]`

**Description:** Drop AI-agent integration artifacts into the current directory. Combine any subset of `--rule`, `--skill`, `--claudemd`, `--agents`. Without flags, prompts interactively for letter codes (`rsca`). Unlike `pr` and `raw`, this command does NOT require `.env` credentials or a Bitbucket-repo CWD — it runs from any directory.

**Flags:**

| Flag | Destination | Behavior |
|------|-------------|----------|
| `--rule` | `./.claude/rules/bb-bash-rule.md` | Claude Code-only, auto-loaded into every context |
| `--skill` | `./.claude/skills/bb-bash/SKILL.md` | Claude Code-only, lazy-loaded when invoked |
| `--claudemd` | `./CLAUDE.md` | Append `## Bitbucket via bb-bash` section (create file if missing) |
| `--agents` | `./AGENTS.md` | Same section, written to `AGENTS.md` (cross-tool standard) |
| `--dry-run` | — | Print actions, write nothing to disk |
| `--force` | — | Overwrite existing files / re-append section even if marker is present |

**Idempotency:** by default skips any artifact that already exists. For `CLAUDE.md` / `AGENTS.md` the check is marker-based (`## Bitbucket via bb-bash`) — file may exist for other reasons without skipping. Re-running is safe.

**Source:** artifacts are fetched from `https://raw.githubusercontent.com/restarter/bb-bash/${BB_BASH_REF:-main}/docs/`. Pin to a release tag for reproducibility:

```bash
BB_BASH_REF=v0.1.2 bbb install-agent --rule --skill --claudemd --agents
```

**Examples:**

```bash
bbb install-agent                                        # interactive
bbb install-agent --rule --skill                         # Claude Code-native pair
bbb install-agent --rule --skill --claudemd --agents     # everything
bbb install-agent --claudemd --dry-run                   # preview without writing
bbb install-agent --rule --force                         # overwrite existing rule
```

**Interactive mode:** prints status of each artifact (present/missing/no-section), then reads letter codes. `rsca` = all four; `rs` = rule+skill; `q` (or empty input) = quit. Invalid characters in the input are rejected; whitelist is `r`/`s`/`c`/`a`. Refuses to run interactively when stdin is not a TTY (`bbb install-agent < /dev/null` or CI contexts) — pass explicit flags instead.

---

## Environment overrides

- `BB_BASH_REMOTE=<name>` — force a specific git remote for workspace/repo resolution
- `BB_BASH_WORKSPACE=<ws>` + `BB_BASH_REPO=<repo>` — bypass git remote auto-detect entirely
- `BB_BASH_BATCH_DELAY=<seconds>` — delay between batch API calls (default `0.3`; set `0` in tests)
- `BB_BASH_EMAIL` / `BB_BASH_TOKEN` — credentials (loaded from `.env` next to script by default)
- `BB_BASH_USER_ONLY=1` — installer-only; force `~/.local/bin` (see [`../scripts/install.sh`](../scripts/install.sh))
- `BB_BASH_FORCE=1` — installer-only; override non-symlink overwrite refusal (see [`../scripts/install.sh`](../scripts/install.sh))
- `BB_BASH_REF=<git-ref>` — `install-agent` only; ref to fetch agent artifacts from (default `main`)

See [design.md](design.md) for the full env precedence and auto-detect chain.

## Installation

See [`scripts/install.sh`](../scripts/install.sh) and the README install section for the one-line curl-pipe-bash installer.
