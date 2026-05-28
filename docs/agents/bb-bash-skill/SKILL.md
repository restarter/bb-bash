---
name: bb-bash
description: Use this skill when the user asks about a Bitbucket Cloud pull request — listing PRs, reading diffs, posting comments, leaving inline review feedback, approving, declining, merging, or creating new PRs. Triggers on phrases like "review the PR", "comment on PR #N", "approve PR", "merge PR", "list open PRs", and on any mention of bitbucket.org URLs in a PR context. Does NOT apply to GitHub PRs (use gh) or Bitbucket Server self-hosted.
---

# bb-bash: Bitbucket Cloud pull-request workflows

This skill drives the `bbb` CLI (project `bb-bash`) — a single-file bash wrapper over Bitbucket Cloud REST API 2.0. Use it whenever a task involves operating on a Bitbucket Cloud pull request from the terminal.

## Preflight

Before the first `bbb` call in a session, confirm the tool is installed and the current directory is inside a bitbucket.org repo:

```bash
command -v bbb >/dev/null || echo "bbb not on PATH"
git remote -v | grep -q bitbucket.org || echo "current repo has no bitbucket.org remote"
```

If `bbb` is missing, suggest the one-liner install:

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/restarter/bb-bash/main/scripts/install.sh | bash
```

If the user is outside a bitbucket.org repo, set `BB_BASH_WORKSPACE` + `BB_BASH_REPO` env vars for the invocation:

```bash
BB_BASH_WORKSPACE=myorg BB_BASH_REPO=myrepo bbb pr list
```

## Command reference

### Read

```bash
bbb pr list                              # open PRs (default state)
bbb pr list --state=merged --author=alice
bbb pr list --state=all
bbb pr show <id>                         # title, branches, author, files
bbb pr diff <id>                         # full unified diff
bbb pr comments <id>                     # general + inline, with comment IDs
bbb pr checks <id>                       # CI statuses + Pipelines (graceful-degrade if token lacks read:pipeline)
```

### Comment

```bash
bbb pr comment <id> "general comment body"
bbb pr inline <id> <path> <line> "comment on new code"      # to:<line> payload
bbb pr inline --old <id> <path> <line> "comment on deleted code"  # from:<line> payload
bbb pr reply <pr_id> <parent_comment_id> "reply body"
bbb pr edit-comment <pr_id> <comment_id> "new body"          # only own comments
bbb pr delete-comment <pr_id> <comment_id>                   # only own comments
```

### Approve / decline / merge

```bash
bbb pr approve <id> [<id> ...]           # batch-capable
bbb pr decline <id> [<id> ...]           # batch-capable
bbb pr merge <id>                        # default merge_commit
bbb pr merge <id> --squash --delete-branch
bbb pr merge <id> --ff --message="Custom merge message"
```

### Create / update

```bash
bbb pr create <target_branch> "Title" "Description"
bbb pr update <id> --title="New title"
bbb pr update <id> --description="New body"
bbb pr update <id> --reviewers=alice,bob
```

### Escape hatch

```bash
bbb pr open <id>                         # opens in default browser
bbb raw "/pullrequests/<id>"             # arbitrary GET
bbb raw-post "/pullrequests/<id>/comments" '{"content":{"raw":"..."}}'  # arbitrary POST
```

## Workflow: review a PR

When the user says "review PR #N" or similar:

1. Read the metadata and diff:
   ```bash
   bbb pr show <N>
   bbb pr diff <N>
   ```
2. Confirm CI is green:
   ```bash
   bbb pr checks <N>
   ```
3. Leave inline comments on specific lines for concrete issues:
   ```bash
   bbb pr inline <N> path/to/file 42 "consider extracting this branch"
   bbb pr inline --old <N> path/to/file 17 "why was this guard removed?"
   ```
4. Wrap up with either approval or a summary comment:
   ```bash
   bbb pr approve <N>
   # OR
   bbb pr comment <N> "Summary of review: 3 inline notes, biggest concern is the removed guard at line 17"
   ```

## Workflow: respond to PR feedback

When the user says "reply to comment N on PR M":

1. List comments to find IDs:
   ```bash
   bbb pr comments <M>
   ```
2. Reply in-thread:
   ```bash
   bbb pr reply <M> <comment_id> "Good catch — fixed in the next commit."
   ```

## Workflow: edit / delete own comments

```bash
bbb pr comments <pr_id>                              # find your comment ID
bbb pr edit-comment <pr_id> <comment_id> "updated text"
bbb pr delete-comment <pr_id> <comment_id>
```

Trying to edit/delete someone else's comment returns HTTP 403 from Bitbucket — surface the error, don't retry.

## Workflow: cleanup stale PRs

```bash
bbb pr list --state=open --author=stalebot | jq -r '.values[].id'   # collect IDs
bbb pr decline 65 67 89                                              # batch close
```

## Conventions

- **Line numbers**: `pr inline` takes actual file line numbers, NOT diff line numbers.
- **Multi-line bodies — quote the heredoc:** always use `<<'EOF'` (single-quoted delimiter). It preserves newlines AND prevents the shell from substituting variables (`$var`) or running command substitutions (`` `cmd` ``). Don't pre-escape `\$` or `` \` `` inside `<<'EOF'` — they pass through as literal `\$` and `` \` ``, which is rarely what the comment should say.

  ```bash
  # CORRECT — single-quoted EOF: $vars and `cmds` stay literal in the comment
  bbb pr comment 42 "$(cat <<'EOF'
  PHP code: `$variable` and ${braces} render literally.
  EOF
  )"

  # WRONG — unquoted EOF: bash expands $variable before posting
  bbb pr comment 42 "$(cat <<EOF
  $variable will be substituted from your shell environment!
  EOF
  )"
  ```

- **edit-comment is full-body replace** (REST PUT semantics): pass the complete new text, not a diff/patch. Bitbucket only allows editing/deleting your own comments — a 403 from another user's comment is expected, don't retry.
- **Force-push effect**: Bitbucket Cloud marks inline comments as "outdated" when the referenced line changes, but the comment is **preserved, not removed**. After a force-push that moved the line, prefer re-posting on the new line over editing the outdated one — the outdated comment is collapsed in the UI and easy to miss.
- **Before approve**: run `git fetch && git log <previous-approve-ref>..HEAD` to see if commits landed after your last review. Bitbucket Cloud has a per-repo "Reset approvals on new commits" setting — if enabled, your approve auto-dismisses; if disabled, your approve persists across new commits. When in doubt, redo the review.
- **Comment markdown — Bitbucket Cloud uses Python-Markdown**, NOT GitHub-Flavored Markdown. Supported: fenced code blocks with language (`` ```php ``, `` ```bash `` — syntax highlighting via `codehilite` extension), tables (pipe syntax, via `tables` extension), strikethrough (`~~text~~`, via `del`), lists, links, blockquotes, footnotes, headings. **Mentions:** `@accountname` or `@email` (not GitHub-style `@username`). **HTML tags are NOT supported** (no `<table>`, no `<br>`, no `<details>`). Full reference: https://support.atlassian.com/bitbucket-cloud/docs/markup-comments/
- **Auto-detect**: workspace/repo are inferred from the bitbucket.org remote of the current directory. No env vars needed inside a Bitbucket repo. Override with `BB_BASH_REMOTE=<name>` when there are multiple remotes.
- **Output**: plain text, no JSON wrapping unless using `bbb raw`. Parse with `jq` only when calling `bbb raw`.
- **Token scopes**: `read:repository:bitbucket`, `read:pullrequest:bitbucket`, `write:pullrequest:bitbucket`. Optional: `read:pipeline:bitbucket` for `pr checks` to show Pipelines.

## When NOT to use this skill

- GitHub PRs → use `gh` CLI.
- Bitbucket Server (self-hosted) → bb-bash is Cloud-only.
- Repo / workspace / user administration → out of scope; web UI.
- Pending / draft / "Start review" batched comments → Bitbucket API publishes immediately; web UI only.

## References

- Full command reference: https://github.com/restarter/bb-bash/blob/main/docs/commands.md
- bb-bash repo: https://github.com/restarter/bb-bash
- Bitbucket Cloud REST API: https://developer.atlassian.com/cloud/bitbucket/rest/
