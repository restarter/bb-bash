# bb-bash

Shell wrapper for the Bitbucket Cloud REST API 2.0. Single-file bash script, no build step. The on-disk binary is `bbb`.

Ships with drop-in integration artifacts (Claude Code rule, skill, `CLAUDE.md` / `AGENTS.md` snippets) so any AI coding agent you already use can drive it without extra wiring — see [For AI agents](#for-ai-agents) below.

## Install

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-bash/main/scripts/install.sh | bash
```

Installs the latest tagged release into `~/.local/share/bb-bash/` and symlinks it into your PATH (`/usr/local/bin/bbb` if writable, else `~/.local/bin/bbb`). On first install, `.env` is created from `.env.example` (chmod 600). **Re-run the same command to update**; your `.env` is never touched.

Useful env vars:
- `BB_BASH_USER_ONLY=1` — force install into `~/.local/bin` (skip `/usr/local/bin` even if writable).
- `BB_BASH_FORCE=1` — overwrite a pre-existing non-symlink at the target PATH location.

### Manual install

```bash
git clone https://github.com/restarter/bb-bash ~/.local/share/bb-bash
ln -s ~/.local/share/bb-bash/bbb ~/.local/bin/bbb    # or /usr/local/bin
cp ~/.local/share/bb-bash/.env.example ~/.local/share/bb-bash/.env
chmod 600 ~/.local/share/bb-bash/.env
# then edit .env with your credentials
```

### Dependencies

`curl`, `jq` (`brew install jq` / `apt install jq`).

## Setup

### 1. Create a Bitbucket API token

Go to https://bitbucket.org/account/settings/api-tokens/. Required scopes:

- `read:repository:bitbucket`
- `read:pullrequest:bitbucket`
- `write:pullrequest:bitbucket`
- `read:pipeline:bitbucket` — *optional, only for `bbb pr checks` to show Bitbucket Pipelines; gracefully omitted otherwise*

### 2. Configure credentials

Edit `~/.local/share/bb-bash/.env`:

```bash
BB_BASH_EMAIL="you@example.com"
BB_BASH_TOKEN="<api-token>"
```

Workspace/repo are auto-detected from `git remote`. Override with `BB_BASH_WORKSPACE` + `BB_BASH_REPO` (outside a git repo) or `BB_BASH_REMOTE=<name>` to pick a specific remote.

## For AI agents

`bbb install-agent` drops integration artifacts so the AI agents you already use (Claude Code, Cursor, Copilot Chat, Codex, Aider, …) know how to call bb-bash without extra prompting.

```bash
bbb install-agent --rule --skill --claude --agents   # drop all four
bbb install-agent --claude --dry-run                  # preview without writing
bbb install-agent --rule --force                        # overwrite existing
```

Idempotent — re-run is safe; pin a release with `BB_BASH_REF=v0.2.0 bbb install-agent ...`.

### What ships out of the box

| Type | Lands at | Loading | Best for |
|---|---|---|---|
| **CLAUDE** | `CLAUDE.md` in project root | every turn | Claude / Cursor / Copilot via `CLAUDE.md` |
| **AGENTS** | `AGENTS.md` in project root | every turn | cross-tool agents (OpenAI Codex, Aider, Continue, …) |
| **Rule** | `.claude/rules/bb-bash-rule.md` | session start | short always-on hint, "bbb exists, here's how" |
| **Skill** | `.claude/skills/bb-bash/SKILL.md` | on-demand | full workflows (review, respond, batch cleanup); zero context cost until invoked |

Pick what fits your stack — `install-agent` accepts any combination of `--rule --skill --claude --agents`.

### Then ask your agent things like

- "Review PR #42 — leave inline comments on anything risky, then summarize."
- "List open PRs by alice."
- "Approve PR #12 and merge with `--squash --delete-branch`."
- "Reply to comment 753926626 on PR #42 with: 'Good catch, fixed.'"

The agent already knows the commands because the install dropped a rule + skill into `.claude/`, plus a `## Bitbucket via bb-bash` section into your `CLAUDE.md` / `AGENTS.md`.

## Usage

```bash
# From inside any bitbucket.org repo:
bbb pr list                              # open PRs (default)
bbb pr list --state=merged --author=alice
bbb pr show 42
bbb pr diff 42
bbb pr checks 42                         # CI + pipelines status
bbb pr comments 42                       # general + inline comments

bbb pr comment 42 "general comment"
bbb pr inline 42 src/auth.ts 30 "consider extracting"
bbb pr inline --old 42 src/auth.ts 10 "this was important"
bbb pr reply 42 753926626 "Good point, fixed"
bbb pr edit-comment 42 753926626 "Updated text"
bbb pr delete-comment 42 753926626

bbb pr approve 42                        # single
bbb pr approve 42 43 44                  # batch
bbb pr decline 99 100                    # batch close-without-merge
bbb pr merge 42 --squash --delete-branch

bbb pr create main "Title" "Description"
bbb pr update 42 --title="New title"
bbb pr open 42                           # opens in browser

bbb raw "/pullrequests"
bbb raw-post "/pullrequests/42/comments" '{"content":{"raw":"test"}}'
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

bbb resolves workspace/repo per invocation. See [docs/design.md](docs/design.md) for the authoritative precedence chain. tl;dr:

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

The `curl ... | bash` installer relies on HTTPS for transport integrity — there's no SHA pinning on `install.sh` or downloaded `bbb`. Same applies to `bbb install-agent` (fetches from `raw.githubusercontent.com`).

If your threat model requires offline review, download first and inspect:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-bash/main/scripts/install.sh -o install.sh
less install.sh   # review
bash install.sh
```

## API reference

- Bitbucket REST API: https://developer.atlassian.com/cloud/bitbucket/rest/
- Pull Requests endpoint: https://developer.atlassian.com/cloud/bitbucket/rest/api-group-pullrequests/

## Contributing

See [docs/contributing.md](docs/contributing.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
