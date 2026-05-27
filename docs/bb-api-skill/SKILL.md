---
name: bb-api
description: Use this skill when the user asks about a Bitbucket Cloud pull request — listing PRs, reading diffs, posting comments, leaving inline review feedback, approving, declining, merging, or creating new PRs. Triggers on phrases like "review the PR", "comment on PR #N", "approve PR", "merge PR", "list open PRs", and on any mention of bitbucket.org URLs in a PR context. Does NOT apply to GitHub PRs (use gh) or Bitbucket Server self-hosted.
---

# bb-api: Bitbucket Cloud pull-request workflows

This skill drives the `bb-api` CLI — a single-file bash wrapper over Bitbucket Cloud REST API 2.0. Use it whenever a task involves operating on a Bitbucket Cloud pull request from the terminal.

## Preflight

Before the first `bb-api` call in a session, confirm the tool is installed and the current directory is inside a bitbucket.org repo:

```bash
command -v bb-api >/dev/null || echo "bb-api not on PATH"
git remote -v | grep -q bitbucket.org || echo "current repo has no bitbucket.org remote"
```

If `bb-api` is missing, suggest the one-liner install:

```bash
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/restarter/bb-api/main/scripts/install.sh | bash
```

If the user is outside a bitbucket.org repo, set `BB_API_WORKSPACE` + `BB_API_REPO` env vars for the invocation:

```bash
BB_API_WORKSPACE=myorg BB_API_REPO=myrepo bb-api pr list
```

## Command reference

### Read

```bash
bb-api pr list                              # open PRs (default state)
bb-api pr list --state=merged --author=alice
bb-api pr list --state=all
bb-api pr show <id>                         # title, branches, author, files
bb-api pr diff <id>                         # full unified diff
bb-api pr comments <id>                     # general + inline, with comment IDs
bb-api pr checks <id>                       # CI statuses + Pipelines (graceful-degrade if token lacks read:pipeline)
```

### Comment

```bash
bb-api pr comment <id> "general comment body"
bb-api pr inline <id> <path> <line> "comment on new code"      # to:<line> payload
bb-api pr inline --old <id> <path> <line> "comment on deleted code"  # from:<line> payload
bb-api pr reply <pr_id> <parent_comment_id> "reply body"
bb-api pr edit-comment <pr_id> <comment_id> "new body"          # only own comments
bb-api pr delete-comment <pr_id> <comment_id>                   # only own comments
```

### Approve / decline / merge

```bash
bb-api pr approve <id> [<id> ...]           # batch-capable
bb-api pr decline <id> [<id> ...]           # batch-capable
bb-api pr merge <id>                        # default merge_commit
bb-api pr merge <id> --squash --delete-branch
bb-api pr merge <id> --ff --message="Custom merge message"
```

### Create / update

```bash
bb-api pr create <target_branch> "Title" "Description"
bb-api pr update <id> --title="New title"
bb-api pr update <id> --description="New body"
bb-api pr update <id> --reviewers=alice,bob
```

### Escape hatch

```bash
bb-api pr open <id>                         # opens in default browser
bb-api raw "/pullrequests/<id>"             # arbitrary GET
bb-api raw-post "/pullrequests/<id>/comments" '{"content":{"raw":"..."}}'  # arbitrary POST
```

## Workflow: review a PR

When the user says "review PR #N" or similar:

1. Read the metadata and diff:
   ```bash
   bb-api pr show <N>
   bb-api pr diff <N>
   ```
2. Confirm CI is green:
   ```bash
   bb-api pr checks <N>
   ```
3. Leave inline comments on specific lines for concrete issues:
   ```bash
   bb-api pr inline <N> path/to/file 42 "consider extracting this branch"
   bb-api pr inline --old <N> path/to/file 17 "why was this guard removed?"
   ```
4. Wrap up with either approval or a summary comment:
   ```bash
   bb-api pr approve <N>
   # OR
   bb-api pr comment <N> "Summary of review: 3 inline notes, biggest concern is the removed guard at line 17"
   ```

## Workflow: respond to PR feedback

When the user says "reply to comment N on PR M":

1. List comments to find IDs:
   ```bash
   bb-api pr comments <M>
   ```
2. Reply in-thread:
   ```bash
   bb-api pr reply <M> <comment_id> "Good catch — fixed in the next commit."
   ```

## Workflow: edit / delete own comments

```bash
bb-api pr comments <pr_id>                              # find your comment ID
bb-api pr edit-comment <pr_id> <comment_id> "updated text"
bb-api pr delete-comment <pr_id> <comment_id>
```

Trying to edit/delete someone else's comment returns HTTP 403 from Bitbucket — surface the error, don't retry.

## Workflow: cleanup stale PRs

```bash
bb-api pr list --state=open --author=stalebot | jq -r '.values[].id'   # collect IDs
bb-api pr decline 65 67 89                                              # batch close
```

## Conventions

- **Line numbers**: `pr inline` takes actual file line numbers, NOT diff line numbers.
- **Multi-line bodies**: pass through a heredoc so newlines survive shell quoting:
  ```bash
  bb-api pr comment 42 "$(cat <<'EOF'
  Paragraph one.

  Paragraph two with **markdown**.
  EOF
  )"
  ```
- **Auto-detect**: workspace/repo are inferred from the bitbucket.org remote of the current directory. No env vars needed inside a Bitbucket repo. Override with `BB_API_REMOTE=<name>` when there are multiple remotes.
- **Output**: plain text, no JSON wrapping unless using `bb-api raw`. Parse with `jq` only when calling `bb-api raw`.
- **Token scopes**: `read:repository:bitbucket`, `read:pullrequest:bitbucket`, `write:pullrequest:bitbucket`. Optional: `read:pipeline:bitbucket` for `pr checks` to show Pipelines.

## When NOT to use this skill

- GitHub PRs → use `gh` CLI.
- Bitbucket Server (self-hosted) → bb-api is Cloud-only.
- Repo / workspace / user administration → out of scope; web UI.
- Pending / draft / "Start review" batched comments → Bitbucket API publishes immediately; web UI only.

## References

- Full command reference: https://github.com/restarter/bb-api/blob/main/docs/commands.md
- bb-api repo: https://github.com/restarter/bb-api
- Bitbucket Cloud REST API: https://developer.atlassian.com/cloud/bitbucket/rest/
