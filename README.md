# bb-bash (bbb)

> **Bitbucket Cloud CLI built for AI coding agents** — single-file bash with zero-config repo auto-detect, inline PR review, and native low-context Claude Code and Codex integrations.

`bbb` (the binary) wraps the Bitbucket Cloud REST API 2.0 so you and your AI agent can drive PR review, inline comments, approve, decline, merge, and create — all from chat or terminal, without leaving your editor. `cd` into any Bitbucket-Cloud-backed repo and run `bbb pr list` — workspace/repo are auto-detected from `git remote`, no per-project setup. No build step, no package manager: one bash script, two dependencies (`curl`, `jq`).

The native presets install compact always-on guidance and a shared lazy skill for Claude Code or Codex. Backward-compatible `CLAUDE.md` / `AGENTS.md` and granular artifact options remain available. See [For AI agents](#for-ai-agents).

## Install

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-bash/main/scripts/install.sh | bash
```

Re-run the same command to update; your `.env` is never touched.

Manual install, env-var overrides, and security-inspection one-liner: see [docs/installation.md](docs/installation.md).

## Setup

### 1. Create a Bitbucket API token

Go to https://id.atlassian.com/manage-profile/security/api-tokens. Required scopes:

- `read:repository:bitbucket`
- `read:pullrequest:bitbucket`
- `write:pullrequest:bitbucket`
- `read:pipeline:bitbucket` — *optional; `bbb pr checks` omits its Pipelines section gracefully without it, but `bbb pr logs` and `bbb pipeline log` require it*

### 2. Configure credentials

Edit `~/.local/share/bb-bash/.env`:

```bash
BB_BASH_EMAIL="you@example.com"
BB_BASH_TOKEN="<api-token>"
```

Workspace/repo are [auto-detected](#how-auto-detect-works) from `git remote`. Override with `BB_BASH_WORKSPACE` + `BB_BASH_REPO` (outside a git repo) or `BB_BASH_REMOTE=<name>` to pick a specific remote.

## For AI agents

Install a tiny always-on instruction plus a detailed, lazy-loaded skill. The instruction only tells the agent when to use `bbb` and when to activate the skill; review and write workflows stay out of session context until Bitbucket work is requested.

### Flags

| Flag | Purpose |
|---|---|
| `--claude-code` | Recommended Claude Code preset: compact rule + lazy skill |
| `--codex` | Recommended Codex preset: managed `AGENTS.md` section + lazy skill |
| `--rule` / `--skill` / `--claude` / `--agents` | Backward-compatible granular selectors |
| `--global` | Install the selected integration in user scope instead of project scope |
| `--dry-run` | Preview the writes without touching disk |
| `--force` | Overwrite an existing artifact (default is skip-if-exists) |

Pin to a release tag for reproducibility: `BB_BASH_REF=v0.3.1 bbb install-agent ...`. Full flag reference: [docs/commands.md#install-agent](docs/commands.md#install-agent).

### Examples

```bash
bbb install-agent --claude-code             # project Claude rule + skill
bbb install-agent --claude-code --global    # user Claude rule + skill
bbb install-agent --codex                   # project AGENTS section + skill
bbb install-agent --codex --global          # user Codex AGENTS section + skill
bbb install-agent --codex --global --dry-run
```

### What ships out of the box

The always-on files are deliberately compact (at most 2 KiB). The shared [`SKILL.md`](docs/agents/bb-bash-skill/SKILL.md) is the canonical source for non-trivial workflows and is installed into each tool's native skill directory.

| Type | Project install | Global (`--global`) | Loading | Best for |
|---|---|---|---|---|
| `CLAUDE.md` | `./CLAUDE.md` | `~/.claude/CLAUDE.md` | every turn | Claude / Cursor / Copilot via `CLAUDE.md` |
| Codex `AGENTS.md` section | `./AGENTS.md` | `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`* | every turn | compact activation and safety guidance |
| Rule | `./.claude/rules/bb-bash-rule.md` | `~/.claude/rules/bb-bash-rule.md` | session start | short always-on hint, "bbb exists, here's how" |
| Claude skill | `./.claude/skills/bb-bash/SKILL.md` | `~/.claude/skills/bb-bash/SKILL.md` | on-demand | full workflows |
| Codex skill | `./.agents/skills/bb-bash/SKILL.md` | `$HOME/.agents/skills/bb-bash/SKILL.md` | on-demand | full workflows; explicitly invoke with `$bb-bash` |

\* If the Codex root contains a non-empty `AGENTS.override.md`, the global managed section goes there instead. `CODEX_HOME` affects the instruction location; the global skill always stays under `$HOME/.agents/skills/`.

Browse the artifact sources directly: [`docs/agents/`](docs/agents/) ([README](docs/agents/README.md)).

### Then ask your agent things like

- "Review PR #42 — leave inline comments on anything risky, then summarize."
- "List open PRs by alice."
- "Approve PR #12 and merge with `--squash --delete-branch`."
- "Reply to comment 753926626 on PR #42 with: 'Good catch, fixed.'"

Mentioning Bitbucket work should activate the lazy skill implicitly. In Codex, `$bb-bash` activates it explicitly. Run `bbb help <command>` for authoritative syntax.

## Commands

```bash
# From inside any bitbucket.org repo:
bbb pr list                              # open PRs (default)
bbb pr list --state=merged --author=alice
bbb pr show 42                           # details + who reviewed and how
bbb pr diff 42 --stat                    # size only, no full diff fetched
bbb pr diff 42
bbb pr checks 42                         # CI + pipelines status
bbb pr logs 42                           # log of the newest pipeline for this PR
bbb pipeline log 137                     # log by pipeline build number
bbb pr comments 42                       # all general + inline comments, newest first

bbb pr comment 42 "general comment"
bbb pr inline 42 src/auth.ts 30 "consider extracting"
bbb pr inline --old 42 src/auth.ts 10 "this was important"
bbb pr reply 42 753926626 "Good point, fixed"
bbb pr edit-comment 42 753926626 "Updated text"
bbb pr delete-comment 42 753926626

bbb pr approve 42                        # single
bbb pr approve 42 43 44                  # batch
bbb pr request-changes 42                # Changes Requested, PR stays open
bbb pr unrequest-changes 42              # withdraw it once fixes land
bbb pr decline 99 100                    # batch close-without-merge (destructive)
bbb pr merge 42 --squash --delete-branch

bbb pr create main "Title" "Description"
bbb pr update 42 --title="New title"
bbb pr update 42 --destination=main       # retarget after the base PR merged
bbb pr open 42                           # opens in browser

bbb raw "/pullrequests"
bbb raw --text "/pipelines/%7B...%7D/steps/%7B...%7D/log"   # plain text, no jq
bbb raw-post "/pullrequests/42/comments" '{"content":{"raw":"test"}}'
bbb raw-put "/pullrequests/42" '{"title":"t","destination":{"branch":{"name":"main"}}}'
bbb raw-delete "/pullrequests/42/comments/99"               # non-zero exit on failure
```

Full command reference: [docs/commands.md](docs/commands.md).

## Inline comments

Two modes depending on which side of the diff you're commenting on:

| Command | `inline` field | Use case |
|---------|---------------|----------|
| `bbb pr inline <id> <path> <line> <text>` | `"to": <line>` | new / modified code |
| `bbb pr inline --old <id> <path> <line> <text>` | `"from": <line>` | deleted / old code |

Line numbers are real file line numbers, not diff line numbers.

## How auto-detect works

`bbb` resolves workspace/repo per invocation. See [docs/design.md](docs/design.md) for the authoritative precedence chain. tl;dr:

- Inside a `bitbucket.org` git repo → workspace/repo derived from `origin` (or first matching remote).
- Outside a git repo, or for one-off overrides → set env vars:

  ```bash
  BB_BASH_WORKSPACE=mycompany BB_BASH_REPO=myproject bbb pr list
  ```

- Override which remote auto-detect uses:

  ```bash
  BB_BASH_REMOTE=bb bbb pr list    # use 'bb' remote instead of 'origin'
  ```

## Limitations

- **Bitbucket Cloud only** — no Bitbucket Server / Data Center.
- **No pending / draft comments** — Bitbucket's "Start review" batching is web-UI only; the API publishes every comment immediately.
- **`pr list --reviewer=<user>` not supported** — Bitbucket BBQL doesn't expose `reviewers.username` filtering. Workaround: pipe `bbb pr list` through `jq`. Tracked in `bb-bash-oja`.
- **`pr update --reviewers=u1,u2` uses usernames** — Bitbucket has been deprecating usernames as stable identifiers. Migration to `account_id` / `uuid` tracked in `bb-bash-oja`.

## Authentication

Basic Auth with `email:api-token` (Bitbucket required this format since Sept 2025; old App Passwords disabled June 2026).

## Security

`bbb` sources `.env` directly, so shell metacharacters in values **execute on every invocation**. Keep `.env` to plain `KEY=value` lines — no backticks, no `$(...)`, no unmatched quotes. Switching to a safe parser is tracked as a follow-up.

For inspecting `install.sh` before running it, see [docs/installation.md#security-inspection](docs/installation.md#security-inspection).

## API reference

- Bitbucket REST API: https://developer.atlassian.com/cloud/bitbucket/rest/
- Pull Requests endpoint: https://developer.atlassian.com/cloud/bitbucket/rest/api-group-pullrequests/

## Contributing

See [docs/contributing.md](docs/contributing.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
