# bb-api - Bitbucket Cloud API CLI

Bitbucket Cloud CLI built for AI coding agents. Single-file bash wrapper over the REST API 2.0, with CLAUDE.md snippet, Claude Code rule, and Claude Code skill bundled out of the box.

## Install

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-api/main/scripts/install.sh | bash
```

Installs the latest tagged release into `~/.local/share/bb-api/` and symlinks it into your PATH (`/usr/local/bin/bb-api` if writable, else `~/.local/bin/bb-api`). On first install, `.env` is created from `.env.example` (chmod 600). **Re-run the same command to update**; your `.env` is never touched.

Useful env vars:
- `BB_API_USER_ONLY=1` — force install into `~/.local/bin` (skip `/usr/local/bin` even if writable).
- `BB_API_FORCE=1` — overwrite a pre-existing non-symlink at the target PATH location.

### Manual install

```bash
git clone https://github.com/restarter/bb-api ~/.local/share/bb-api
ln -s ~/.local/share/bb-api/bb-api ~/.local/bin/bb-api    # or /usr/local/bin
cp ~/.local/share/bb-api/.env.example ~/.local/share/bb-api/.env
chmod 600 ~/.local/share/bb-api/.env
# then edit .env with your credentials
```

### Security note

bb-api `source`s the `.env` file directly, so shell metacharacters in values execute on every invocation. Keep `.env` to plain `KEY=value` lines — no backticks, no `$(...)`, no unmatched quotes. (Switching to a safe key=value parser is tracked as a follow-up.)

Curl-pipe-bash relies on TLS for transport integrity. There's no SHA pinning of `install.sh` or the downloaded `bb-api`. If your threat model requires offline verification, download first and inspect:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-api/main/scripts/install.sh -o install.sh
less install.sh
bash install.sh
```

### Dependencies

`curl`, `jq` (`brew install jq` / `apt install jq`).

## Setup

### 1. Create Bitbucket API Token

Go to: https://bitbucket.org/account/settings/api-tokens/

Required scopes:
- `read:repository:bitbucket`
- `read:pullrequest:bitbucket`
- `write:pullrequest:bitbucket`
- `read:pipeline:bitbucket` (only for `pr checks` to show Bitbucket Pipelines; gracefully omitted if not granted)

### 2. Configure credentials

Edit `~/.local/share/bb-api/.env`:

```bash
BB_API_EMAIL="your-email@example.com"
BB_API_TOKEN="your-app-password-here"
```

Workspace/repo are auto-detected from your git remote — no setup needed.

## Usage

```bash
# From inside any bitbucket.org repo:
bb-api pr list                              # open PRs (default)
bb-api pr list --state=merged --author=alice
bb-api pr show 42
bb-api pr diff 42
bb-api pr checks 42                         # CI + pipelines status
bb-api pr comments 42                       # list comments (general + inline)

bb-api pr comment 42 "general comment"
bb-api pr inline 42 src/auth.ts 30 "consider extracting"
bb-api pr inline --old 42 src/auth.ts 10 "this was important"
bb-api pr reply 42 753926626 "Good point, fixed"
bb-api pr edit-comment 42 753926626 "Updated text"
bb-api pr delete-comment 42 753926626

bb-api pr approve 42                         # single
bb-api pr approve 42 43 44                   # batch
bb-api pr decline 99 100                     # batch close-without-merge
bb-api pr merge 42 --squash --delete-branch

bb-api pr create main "Title" "Description"
bb-api pr update 42 --title="New title"
bb-api pr open 42                            # opens in browser

bb-api raw "/pullrequests"
bb-api raw-post "/pullrequests/42/comments" '{"content":{"raw":"test"}}'
```

Full command reference: [docs/commands.md](docs/commands.md).

## Inline Comments

Two modes depending on which side of the diff you're commenting on:

| Command | `inline` field | Use case |
|---------|---------------|----------|
| `pr inline` | `"to": <line>` | Comment on new/modified code |
| `pr inline --old` | `"from": <line>` | Comment on deleted/old code |

Line numbers correspond to the actual file line numbers, not diff line numbers.

## How auto-detect works

bb-api resolves workspace/repo per invocation. See [docs/design.md](docs/design.md) for the authoritative precedence chain. tl;dr:

- Inside a `bitbucket.org` git repo → workspace/repo derived from `origin` (or first matching remote)
- Outside a git repo, or for one-off overrides → set env vars:

```bash
BB_API_WORKSPACE=mycompany BB_API_REPO=myproject bb-api pr list
```

Override which remote auto-detect uses:

```bash
BB_API_REMOTE=bb bb-api pr list    # use 'bb' remote instead of 'origin'
```

## For AI agents

Three drop-in integrations, pick what fits your stack:

| Artifact | Where it goes | Loading | Best for |
|---|---|---|---|
| [`docs/CLAUDE.md.example`](docs/CLAUDE.md.example) | paste into project's `CLAUDE.md` | always in context | Cursor, Copilot, mixed-tool teams, any agent that reads CLAUDE.md |
| [`docs/bb-api-rule.md`](docs/bb-api-rule.md) | copy to `.claude/rules/bb-api-rule.md` | auto-loaded by Claude Code | short always-on hint for Claude Code-native projects |
| [`docs/bb-api-skill/SKILL.md`](docs/bb-api-skill/SKILL.md) | copy to `.claude/skills/bb-api/SKILL.md` | lazy-loaded on Claude Code skill invocation | full workflow guide with zero context cost until invoked |

### One-shot install

If you already have `bb-api` on your PATH (after running the install one-liner above), run this from inside any project:

```bash
bb-api install-agent                                       # interactive — pick which artifacts
bb-api install-agent --rule --skill --claudemd --agents    # all four at once
bb-api install-agent --rule --dry-run                      # preview, no writes
```

Idempotent — re-run is safe (skips existing files). Use `--force` to overwrite existing artifacts or re-append to `CLAUDE.md`/`AGENTS.md`. Use `BB_API_REF=v0.1.2 bb-api install-agent ...` to pin artifacts to a release tag instead of fetching from `main`.

### Manual install (without bb-api on PATH)

Quick install of the Claude Code rule into the current project:

```bash
mkdir -p .claude/rules
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-api/main/docs/bb-api-rule.md \
    -o .claude/rules/bb-api-rule.md
```

Quick install of the skill:

```bash
mkdir -p .claude/skills/bb-api
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-api/main/docs/bb-api-skill/SKILL.md \
    -o .claude/skills/bb-api/SKILL.md
```

Rule + skill can coexist — the rule tells the agent bb-api exists; the skill loads the full command reference only when needed.

## Authentication notes

- Basic Auth with `email:api-token` (Bitbucket requirement since Sept 2025)
- Old App Passwords deprecated, disabled June 2026

## API Reference

- Base URL: `https://api.bitbucket.org/2.0/repositories/{workspace}/{repo}`
- [Bitbucket REST API docs](https://developer.atlassian.com/cloud/bitbucket/rest/)
- [Pull Requests API](https://developer.atlassian.com/cloud/bitbucket/rest/api-group-pullrequests/)

## Limitations

- **No pending/draft comments** - all comments are published immediately via API. Bitbucket's "Start review" batching only works in the web UI.

## Contributing

See [docs/contributing.md](docs/contributing.md).

## Changelog

See [CHANGELOG.md](CHANGELOG.md).
