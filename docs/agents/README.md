# AI agent integrations

bb-bash supports two independent usage styles:

- The self-contained rule or managed instruction is always loaded, making a plain “review this PR” request sufficient in projects where permanent context is preferred.
- The self-contained [`bbb` skill](bb-bash-skill/SKILL.md) loads only for Bitbucket work and can be invoked explicitly as `/bbb` in Claude Code or `$bbb` in Codex.

Presets install both for convenience, but neither artifact depends on the other. Granular flags support instruction-only and skill-only installations.

Use `bbb help <command>` for current command syntax. [`docs/commands.md`](../commands.md) is the full reference; the skill intentionally does not duplicate it.

## Recommended presets

```bash
bbb install-agent --claude-code [--global]
bbb install-agent --codex [--global]
```

Independent modes:

```bash
bbb install-agent --rule [--global]          # Claude always-on only
bbb install-agent --skill [--global]         # Claude /bbb skill only
bbb install-agent --agents [--global]        # Codex always-on only
bbb install-agent --codex-skill [--global]   # Codex $bbb skill only
```

| Integration | Project scope | User scope |
|---|---|---|
| Claude self-contained rule | `.claude/rules/bb-bash-rule.md` | `$HOME/.claude/rules/bb-bash-rule.md` |
| Claude lazy `bbb` skill | `.claude/skills/bbb/SKILL.md` | `$HOME/.claude/skills/bbb/SKILL.md` |
| Codex self-contained instruction | managed section in `AGENTS.md` | managed section in the effective global Codex AGENTS file |
| Codex lazy `bbb` skill | `.agents/skills/bbb/SKILL.md` | `$HOME/.agents/skills/bbb/SKILL.md` |

For global Codex installation, the effective instruction destination is:

1. `${CODEX_HOME:-$HOME/.codex}/AGENTS.override.md` when it exists and is non-empty.
2. Otherwise `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`.

The installer prints the effective destination. `CODEX_HOME` never changes the global skill path: Codex discovers it at `$HOME/.agents/skills/bbb/SKILL.md`.

## Managed files and compatibility

Sections added to `AGENTS.md` or `CLAUDE.md` use these markers:

```markdown
<!-- bb-bash:start -->
<!-- bb-bash:end -->
```

Reinstallation updates that section in place and preserves unrelated content. A legacy unmarked bb-bash section is skipped with a migration message; `--force` migrates it when it is the trailing section. `--dry-run` reports every effective destination without writing.

The granular `--rule`, `--skill`, `--claude`, and `--agents` selectors remain supported and may be combined. `--codex-skill` installs the Codex skill without touching `AGENTS.md`. When an older `.../skills/bb-bash/SKILL.md` exists, the installer reports it but does not silently delete it. Without selectors, project installation keeps the legacy interactive prompt.

See [README → For AI agents](../../README.md#for-ai-agents) for the overview and [commands.md → install-agent](../commands.md#install-agent) for all flags.
