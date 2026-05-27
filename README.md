# bb-api - Bitbucket Cloud API CLI

Shell wrapper for Bitbucket Cloud REST API 2.0.

## Install

```bash
git clone https://github.com/restarter/bb-api ~/code/bb-api
ln -s ~/code/bb-api/bb-api ~/.local/bin/bb-api    # add to PATH
# On macOS, ~/.local/bin is NOT in PATH by default. Add to ~/.zshrc:
#   export PATH="$HOME/.local/bin:$PATH"
# Or symlink to /usr/local/bin (already in PATH on macOS/Linux) using sudo.

cp ~/code/bb-api/.env.example ~/code/bb-api/.env
chmod 600 ~/code/bb-api/.env                       # protect API token
# then edit .env with your credentials
```

Dependencies: `curl`, `jq` (`brew install jq` / `apt install jq`).

## Setup

### 1. Create Bitbucket API Token

Go to: https://bitbucket.org/account/settings/api-tokens/

Required scopes:
- `read:repository:bitbucket`
- `read:pullrequest:bitbucket`
- `write:pullrequest:bitbucket`
- `read:pipeline:bitbucket` (only for `pr checks` to show Bitbucket Pipelines; gracefully omitted if not granted)

### 2. Configure credentials

Edit `.env` next to the script:

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

Drop [docs/CLAUDE.md.example](docs/CLAUDE.md.example) into your project's `CLAUDE.md` so Claude / Cursor / etc. know how to use bb-api.

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
