# AI agent integrations

bb-bash uses a low-context two-layer design:

- The compact rule or managed instruction is always loaded. It identifies `bbb`, activates the skill for non-trivial Bitbucket work, and states the essential trust and authorization boundaries.
- [`bb-bash-skill/SKILL.md`](bb-bash-skill/SKILL.md) is the canonical detailed workflow source. Claude Code and Codex load it only when Bitbucket work is requested. Codex users can also invoke it explicitly with `$bb-bash`.

Use `bbb help <command>` for current command syntax. [`docs/commands.md`](../commands.md) is the full reference; the skill intentionally does not duplicate it.

## Recommended presets

```bash
bbb install-agent --claude-code [--global]
bbb install-agent --codex [--global]
```

| Integration | Project scope | User scope |
|---|---|---|
| Claude compact rule | `.claude/rules/bb-bash-rule.md` | `$HOME/.claude/rules/bb-bash-rule.md` |
| Claude lazy skill | `.claude/skills/bb-bash/SKILL.md` | `$HOME/.claude/skills/bb-bash/SKILL.md` |
| Codex compact instruction | managed section in `AGENTS.md` | managed section in the effective global Codex AGENTS file |
| Codex lazy skill | `.agents/skills/bb-bash/SKILL.md` | `$HOME/.agents/skills/bb-bash/SKILL.md` |

For global Codex installation, the effective instruction destination is:

1. `${CODEX_HOME:-$HOME/.codex}/AGENTS.override.md` when it exists and is non-empty.
2. Otherwise `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`.

The installer prints the effective destination. `CODEX_HOME` never changes the global skill path: Codex discovers it at `$HOME/.agents/skills/bb-bash/SKILL.md`.

## Managed files and compatibility

Sections added to `AGENTS.md` or `CLAUDE.md` use these markers:

```markdown
<!-- bb-bash:start -->
<!-- bb-bash:end -->
```

Reinstallation updates that section in place and preserves unrelated content. A legacy unmarked bb-bash section is skipped with a migration message; `--force` migrates it when it is the trailing section. `--dry-run` reports every effective destination without writing.

The granular `--rule`, `--skill`, `--claude`, and `--agents` selectors remain supported and may be combined. Without selectors, project installation keeps the legacy interactive prompt.

See [README → For AI agents](../../README.md#for-ai-agents) for the overview and [commands.md → install-agent](../commands.md#install-agent) for all flags.
