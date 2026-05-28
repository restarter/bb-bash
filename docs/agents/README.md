# AI agent integration artifacts

Four drop-in artifacts that teach your AI coding agent how to drive `bbb` (the bb-bash binary). **Pick any one — each is fully self-contained.** Your agent gets the same end result: install hint, auth, commands, conventions, workflows.

| Artifact | Lands at | Loading | Best for |
|---|---|---|---|
| [`bb-bash-snippet.md`](bb-bash-snippet.md) | `CLAUDE.md` or `AGENTS.md` in project root | every turn | Claude / Cursor / Copilot via `CLAUDE.md`; OpenAI Codex / Aider / Continue via `AGENTS.md` |
| [`bb-bash-rule.md`](bb-bash-rule.md) | `.claude/rules/bb-bash-rule.md` | session start | Claude Code, short always-on hint |
| [`bb-bash-skill/SKILL.md`](bb-bash-skill/SKILL.md) | `.claude/skills/bb-bash/SKILL.md` | on-demand | Claude Code, full workflows (review / respond / cleanup); zero context cost until invoked |

Re-running with no flags makes `bbb install-agent` prompt interactively. Combine flags freely:

```bash
bbb install-agent                                # interactive (project)
bbb install-agent --claude                       # append snippet to CLAUDE.md
bbb install-agent --agents                       # append snippet to AGENTS.md
bbb install-agent --rule                         # drop the Claude Code rule
bbb install-agent --skill                        # drop the Claude Code skill
bbb install-agent --rule --skill                 # Claude Code-native pair (project)
bbb install-agent --rule --dry-run               # preview without writing
bbb install-agent --rule --force                 # overwrite existing
```

### Install globally (every project)

Pass `--global` to write into `$HOME/.claude/` instead of the current project. Claude Code auto-loads from there for all projects:

```bash
bbb install-agent --rule --global                # → ~/.claude/rules/bb-bash-rule.md
bbb install-agent --skill --global               # → ~/.claude/skills/bb-bash/SKILL.md
bbb install-agent --claude --global              # → ~/.claude/CLAUDE.md (append snippet)
bbb install-agent --rule --skill --global        # both, globally
```

`--agents --global` is intentionally an error — `AGENTS.md` has no widely-adopted global path; install it per-project instead.

### Pin to a release tag

```bash
BB_BASH_REF=v0.2.0 bbb install-agent --rule --skill
```

See [README → For AI agents](../../README.md#for-ai-agents) for the high-level overview, or [commands.md → install-agent](../commands.md#install-agent) for the full flag reference.
