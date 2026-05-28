## Bitbucket via bb-bash

**Tool:** `bbb` (project `bb-bash`, https://github.com/restarter/bb-bash)
**Install** (if not present):
```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/restarter/bb-bash/main/scripts/install.sh | bash
```
Auto-resolves through symlinks; `.env` lives next to the real script
(`~/.local/share/bb-bash/.env` after `install.sh`).

**Auto-detects** workspace/repo from this repo's bitbucket.org remote.
**Auth:** `BB_BASH_EMAIL` + `BB_BASH_TOKEN` in the `.env` file
(`~/.local/share/bb-bash/.env` for installed bbb, or the file next to
the script for manual installs — bbb resolves symlinks).

### Common workflows

```bash
# List PRs
bbb pr list                              # open PRs (default)
bbb pr list --state=merged --author=alice

# Inspect a PR
bbb pr show <id>
bbb pr diff <id>
bbb pr comments <id>
bbb pr checks <id>                       # CI + pipelines status

# Comment / review
bbb pr comment <id> "general comment"
bbb pr inline <id> path/to/file 42 "comment on new code"
bbb pr inline --old <id> path/to/file 10 "comment on deleted code"
bbb pr reply <pr_id> <comment_id> "reply text"

# Approve / decline / merge
bbb pr approve <id> [<id> ...]           # batch-capable
bbb pr decline <id> [<id> ...]           # batch-capable
bbb pr merge <id> [--squash|--commit|--ff] [--delete-branch]

# Create / update
bbb pr create <target_branch> "Title" "Description"
bbb pr update <id> --title="New title" --description="..."

# Browser escape hatch
bbb pr open <id>
```

### For AI agents (review patterns)

When reviewing a PR:
1. `bbb pr show <id>` — title, author, changed files
2. `bbb pr diff <id> | head -200` — read the diff
3. `bbb pr checks <id>` — confirm CI status before approving
4. `bbb pr inline <id> <path> <line> "feedback"` — inline review comments
5. `bbb pr approve <id>` or `bbb pr comment <id> "summary"` to wrap up

For batch operations (close stale PRs, approve multiple):

```bash
bbb pr decline 65 67 89
bbb pr approve 12 15 18
```

Full reference: see bb-bash repo's `docs/commands.md`.
