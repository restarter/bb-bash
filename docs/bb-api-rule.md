# bb-api: Bitbucket Cloud CLI

For any Bitbucket Cloud pull-request operation in this repo (list, show, diff, comment, inline review, approve, decline, merge, create, edit/delete own comments), use the `bb-api` CLI rather than calling the REST API directly or asking the user to switch to the web UI.

## Tool

`bb-api` — single-file bash script wrapping Bitbucket Cloud REST API 2.0. Source: https://github.com/restarter/bb-api

Install if not present on PATH:

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/restarter/bb-api/main/scripts/install.sh | bash
```

Auto-detects workspace/repo from the current git remote (no env vars needed inside a bitbucket.org repo). Auth lives in `~/.local/share/bb-api/.env` (`BB_API_EMAIL` + `BB_API_TOKEN`).

## Commands

```bash
# Read
bb-api pr list                              # open PRs (default)
bb-api pr list --state=merged --author=alice
bb-api pr show <id>
bb-api pr diff <id>
bb-api pr comments <id>                     # general + inline
bb-api pr checks <id>                       # CI statuses + Bitbucket Pipelines

# Comment / review
bb-api pr comment <id> "general comment"
bb-api pr inline <id> path/to/file 42 "comment on new code"
bb-api pr inline --old <id> path/to/file 10 "comment on deleted code"
bb-api pr reply <pr_id> <comment_id> "reply text"
bb-api pr edit-comment <pr_id> <comment_id> "updated text"     # own comments only
bb-api pr delete-comment <pr_id> <comment_id>                  # own comments only

# Approve / decline / merge
bb-api pr approve <id> [<id> ...]           # batch-capable
bb-api pr decline <id> [<id> ...]           # batch-capable
bb-api pr merge <id> [--squash|--commit|--ff] [--delete-branch]

# Create / update
bb-api pr create <target_branch> "Title" "Description"
bb-api pr update <id> --title="..." --description="..." --reviewers=u1,u2

# Browser escape hatch
bb-api pr open <id>
```

## Conventions

- **Line numbers** in `pr inline` refer to the actual file line numbers, not diff line numbers.
- **Inline mode** — use `pr inline` for new/modified code (`to:<line>` payload), `pr inline --old` for deleted/old code (`from:<line>` payload).
- **Multi-line content** — pass via heredoc to preserve newlines:

  ```bash
  bb-api pr comment 42 "$(cat <<'EOF'
  Multi-line
  comment body
  EOF
  )"
  ```

- **Edit/delete** — Bitbucket only allows editing/deleting your own comments. Trying to touch another user's comment returns a 403.
- **Batch operations** — `pr approve` and `pr decline` accept multiple IDs and print one success line per PR.

## Review patterns

When asked to review a PR:

1. `bb-api pr show <id>` — title, author, changed files, branch.
2. `bb-api pr diff <id> | head -200` — read the diff.
3. `bb-api pr checks <id>` — confirm CI passed before approving.
4. `bb-api pr inline <id> <path> <line> "feedback"` — leave inline comments on specific lines.
5. Wrap up with either `bb-api pr approve <id>` or `bb-api pr comment <id> "summary of review"` depending on whether changes are requested.

When closing stale work in bulk:

```bash
bb-api pr decline 65 67 89                  # close without merge
bb-api pr approve 12 15 18                  # batch approve
```

## When NOT to use bb-api

- GitHub PRs — use `gh` CLI instead.
- Bitbucket Server (self-hosted) — bb-api targets Bitbucket **Cloud** only.
- Workspace administration (users, repos, permissions) — out of scope; use the Bitbucket web UI.

## Full reference

`bb-api` help: `bb-api help`. Full command reference: https://github.com/restarter/bb-api/blob/main/docs/commands.md.
