# bb-api

> **Bitbucket Cloud CLI built for AI coding agents.**
>
> Tell your agent "set up bb-api in this project" — done in under a minute. Then ask it to review PRs, leave inline comments, approve, merge, all from chat.

`bb-api` is a single-file bash wrapper around the Bitbucket Cloud REST API 2.0. It ships with drop-in integration artifacts (Claude Code rule, skill, `CLAUDE.md` snippet, `AGENTS.md` snippet) so the agents you already use know how to call it — without you wiring anything up.

## Quick start — let your agent do it

Paste this prompt into Claude Code / Cursor / Copilot Chat / any AI coding agent with terminal access:

````text
Install bb-api in this project (https://github.com/restarter/bb-api):

1. Run the installer:
   curl --proto '=https' --tlsv1.2 -fsSL \
       https://raw.githubusercontent.com/restarter/bb-api/main/scripts/install.sh | bash

2. Drop the AI-agent integration artifacts into this project:
   bb-api install-agent --rule --skill --claudemd --agents

3. Ask me for my Bitbucket email and API token. Write them into
   ~/.local/share/bb-api/.env (keep chmod 600). The token is created
   at https://bitbucket.org/account/settings/api-tokens/ with scopes:
     read:repository:bitbucket
     read:pullrequest:bitbucket
     write:pullrequest:bitbucket
     read:pipeline:bitbucket  (optional, for `bb-api pr checks`)

4. After install-agent finishes, tell me to restart this session so
   the .claude/rules/ and .claude/skills/ artifacts load. CLAUDE.md
   and AGENTS.md are picked up automatically.

5. Confirm: run `bb-api help`. Then if I'm inside a Bitbucket repo,
   also run `bb-api pr list`.
````

When it's done, ask the agent things like:

- "Review PR #42 — leave inline comments on anything risky, then summarize."
- "List open PRs by alice."
- "Approve PR #12 and merge with `--squash --delete-branch`."
- "Reply to comment 753926626 on PR #42 with: 'Good catch, fixed.'"

The agent already knows the commands because the install dropped a rule + skill into `.claude/`, plus a `## Bitbucket via bb-api` section in your `CLAUDE.md` / `AGENTS.md`.

## What ships out of the box

| Artifact | Destination | Loading | Best for |
|---|---|---|---|
| `CLAUDE.md` snippet | project root | every turn | Claude / Cursor / Copilot via `CLAUDE.md` |
| `AGENTS.md` snippet | project root | every turn | cross-tool agents (OpenAI Codex, Aider, Continue, ...) |
| `.claude/rules/bb-api-rule.md` | Claude Code project | session start | short always-on hint, "bb-api exists, here's how" |
| `.claude/skills/bb-api/SKILL.md` | Claude Code project | on-demand | full workflows (review, respond, batch cleanup); zero context cost until invoked |

Pick what fits your stack. `bb-api install-agent` accepts any combination of `--rule --skill --claudemd --agents`. Idempotent — re-run is safe; `--force` overwrites; `--dry-run` previews.

## What bb-api can do

- **Read:** `pr list`, `pr show`, `pr diff`, `pr comments`, `pr checks` (CI + Pipelines)
- **Comment:** `pr comment`, `pr inline [--old]` (new/deleted code), `pr reply`, `pr edit-comment`, `pr delete-comment`
- **Decide:** `pr approve` (batch), `pr decline` (batch), `pr merge [--squash|--commit|--ff] [--delete-branch]`
- **Create / update:** `pr create`, `pr update --title/--description/--reviewers`
- **Escape hatches:** `pr open` (browser), `raw` / `raw-post` (direct API access)

All commands auto-detect workspace and repo from your git remote — no env vars needed inside a bitbucket.org repo. Full reference: [docs/commands.md](docs/commands.md).

## Manual install (no agent)

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-api/main/scripts/install.sh | bash

bb-api install-agent --rule --skill --claudemd --agents   # drop integration artifacts

$EDITOR ~/.local/share/bb-api/.env                         # add BB_API_EMAIL + BB_API_TOKEN
```

Installer notes:

- Installs to `/usr/local/bin/bb-api` if writable, otherwise `~/.local/bin/bb-api`.
- First run creates `.env` (chmod 600) from `.env.example`. **Re-run to update**; `.env` is never touched.
- `BB_API_USER_ONLY=1` forces `~/.local/bin` even when `/usr/local/bin` is writable.
- `BB_API_FORCE=1` overrides the refusal to overwrite a non-symlink at the PATH target.

For a clone-and-symlink install, see [docs/contributing.md](docs/contributing.md).

## Bitbucket token

Create at https://bitbucket.org/account/settings/api-tokens/. Required scopes:

- `read:repository:bitbucket`
- `read:pullrequest:bitbucket`
- `write:pullrequest:bitbucket`
- `read:pipeline:bitbucket` — *optional, only needed for `bb-api pr checks` to show Pipelines; gracefully omitted otherwise*

Then put your email and token in `~/.local/share/bb-api/.env`:

```bash
BB_API_EMAIL="you@example.com"
BB_API_TOKEN="<api-token>"
```

Workspace and repo slug are auto-detected from `git remote`. Override with `BB_API_WORKSPACE` + `BB_API_REPO` env vars (for use outside a git repo), or `BB_API_REMOTE=<name>` to pick a specific remote.

## Inline comments — two modes

| Command | `inline` field | Use case |
|---------|---------------|----------|
| `bb-api pr inline <id> <path> <line> <text>` | `"to": <line>` | new / modified code |
| `bb-api pr inline --old <id> <path> <line> <text>` | `"from": <line>` | deleted / old code |

Line numbers are real file line numbers, not diff line numbers.

## Limitations

- **Bitbucket Cloud only** — no Bitbucket Server / Data Center.
- **No pending / draft comments** — Bitbucket's "Start review" batching is web-UI only; the API publishes every comment immediately.
- **`pr list --reviewer=<user>` not supported** — Bitbucket BBQL doesn't expose `reviewers.username` filtering. Workaround: pipe `bb-api pr list` through `jq`. Tracked in `bb-api-oja`.
- **`pr update --reviewers=u1,u2` uses usernames** — Bitbucket has been deprecating usernames as stable identifiers. Migration to `account_id` / `uuid` tracked in `bb-api-oja`.

## Authentication notes

Basic Auth with `email:api-token` (Bitbucket required this format since Sept 2025; old App Passwords disabled June 2026).

## Security

`bb-api` sources `.env` directly, so shell metacharacters in values **execute on every invocation**. Keep `.env` to plain `KEY=value` lines — no backticks, no `$(...)`, no unmatched quotes. Switching to a safe parser is tracked as a follow-up.

The `curl ... | bash` installer relies on HTTPS for transport integrity — there's no SHA pinning on `install.sh` or downloaded `bb-api`. Same applies to `bb-api install-agent` (fetches from `raw.githubusercontent.com`). Pin a release tag for reproducibility:

```bash
BB_API_REF=v0.1.2 bb-api install-agent --rule --skill --claudemd --agents
```

If your threat model requires offline review, download first and inspect:

```bash
curl --proto '=https' --tlsv1.2 -fsSL \
    https://raw.githubusercontent.com/restarter/bb-api/main/scripts/install.sh -o install.sh
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
