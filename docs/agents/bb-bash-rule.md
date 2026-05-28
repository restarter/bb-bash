# bb-bash: Bitbucket Cloud CLI

For any Bitbucket Cloud pull-request operation in this repo (list, show, diff, comment, inline review, approve, decline, merge, create, edit/delete own comments), use the `bbb` CLI rather than calling the REST API directly or asking the user to switch to the web UI.

## Tool

`bbb` — single-file bash script wrapping Bitbucket Cloud REST API 2.0 (project: `bb-bash`). Source: https://github.com/restarter/bb-bash

Install if not present on PATH:

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/restarter/bb-bash/main/scripts/install.sh | bash
```

Auto-detects workspace/repo from the current git remote (no env vars needed inside a bitbucket.org repo). Auth lives in `~/.local/share/bb-bash/.env` (`BB_BASH_EMAIL` + `BB_BASH_TOKEN`).

## Commands

```bash
# Read
bbb pr list                              # open PRs (default)
bbb pr list --state=merged --author=alice
bbb pr show <id>
bbb pr diff <id>
bbb pr comments <id>                     # general + inline
bbb pr checks <id>                       # CI statuses + Bitbucket Pipelines

# Comment / review
bbb pr comment <id> "general comment"
bbb pr inline <id> path/to/file 42 "comment on new code"
bbb pr inline --old <id> path/to/file 10 "comment on deleted code"
bbb pr reply <pr_id> <comment_id> "reply text"
bbb pr edit-comment <pr_id> <comment_id> "updated text"     # own comments only
bbb pr delete-comment <pr_id> <comment_id>                  # own comments only

# Approve / decline / merge
bbb pr approve <id> [<id> ...]           # batch-capable
bbb pr decline <id> [<id> ...]           # batch-capable
bbb pr merge <id> [--squash|--commit|--ff] [--delete-branch]

# Create / update
bbb pr create <target_branch> "Title" "Description"
bbb pr update <id> --title="..." --description="..." --reviewers=u1,u2

# Browser escape hatch
bbb pr open <id>
```

## Conventions

- **Line numbers** in `pr inline` refer to the actual file line numbers, not diff line numbers.
- **Inline mode** — use `pr inline` for new/modified code (`to:<line>` payload), `pr inline --old` for deleted/old code (`from:<line>` payload).
- **Multi-line content** — pass via heredoc to preserve newlines:

  ```bash
  bbb pr comment 42 "$(cat <<'EOF'
  Multi-line
  comment body
  EOF
  )"
  ```

- **Edit/delete** — Bitbucket only allows editing/deleting your own comments. Trying to touch another user's comment returns a 403.
- **Batch operations** — `pr approve` and `pr decline` accept multiple IDs and print one success line per PR.

## Review patterns

When asked to review a PR:

1. `bbb pr show <id>` — title, author, changed files, branch.
2. `bbb pr diff <id> | head -200` — read the diff.
3. `bbb pr checks <id>` — confirm CI passed before approving.
4. `bbb pr inline <id> <path> <line> "feedback"` — leave inline comments on specific lines.
5. Wrap up with either `bbb pr approve <id>` or `bbb pr comment <id> "summary of review"` depending on whether changes are requested.

When closing stale work in bulk:

```bash
bbb pr decline 65 67 89                  # close without merge
bbb pr approve 12 15 18                  # batch approve
```

## When NOT to use bb-bash

- GitHub PRs — use `gh` CLI instead.
- Bitbucket Server (self-hosted) — bb-bash targets Bitbucket **Cloud** only.
- Workspace administration (users, repos, permissions) — out of scope; use the Bitbucket web UI.

## References

- Full command reference: https://github.com/restarter/bb-bash/blob/main/docs/commands.md
- bb-bash repo: https://github.com/restarter/bb-bash
- Bitbucket Cloud REST API: https://developer.atlassian.com/cloud/bitbucket/rest/
