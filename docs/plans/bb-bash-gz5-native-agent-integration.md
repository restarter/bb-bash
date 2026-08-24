# bb-bash-gz5: Native Claude Code and Codex integration

## Status and scope

This is the approved execution plan for beads issue `bb-bash-gz5`. Beads remains the task tracker; this file defines the implementation contract and verification evidence.

The work is isolated on `feature/bb-bash-gz5-native-agent-integration`, based on `origin/main` after the merge of pagination prerequisite `bb-bash-z8f` in PR #27.

## Goals

Provide native low-context integration for Claude Code and Codex:

- an always-loaded instruction of at most 2 KiB per artifact;
- one canonical lazy `bb-bash` skill for detailed workflows;
- project and user scopes for both products;
- current command-specific CLI help as the syntax authority;
- idempotent managed sections that preserve unrelated user content;
- backward-compatible granular installer flags.

## Content architecture

Reduce `docs/agents/bb-bash-rule.md` and `docs/agents/bb-bash-snippet.md` to the required compact safety and activation guidance. Neither file carries a command inventory or long workflow examples.

Keep `docs/agents/bb-bash-skill/SKILL.md` as the canonical workflow source. It covers complete review preflight, all paginated comments, inline placement and `--old`, multiline bodies, review verdict semantics, authorization and post-write readback, pipelines, retargeting, and raw API safety. It links to current CLI help and `docs/commands.md` instead of duplicating the full reference.

## Command-specific help

Implement `bbb help <command>` with multi-token commands such as:

```text
bbb help pr show
bbb help pr inline
bbb help pipeline log
bbb help raw
bbb help install-agent
```

Help works without credentials and outside a Bitbucket repository. Every routed command has an authoritative synopsis and concise flag/semantic guidance.

Replace the existing artifact-parity test with three-way drift protection:

- every router command has command-specific help;
- every router command has a matching `docs/commands.md` entry;
- CLI and documentation synopses match.

The compact artifacts are tested for their required safety/activation content and the 2 KiB limit, not for full router coverage.

## Installer presets and destinations

Add native presets:

```text
bbb install-agent --claude-code [--global]
bbb install-agent --codex [--global]
```

`--claude-code` installs the compact rule and lazy skill:

| Scope | Instruction | Skill |
|---|---|---|
| Project | `.claude/rules/bb-bash-rule.md` | `.claude/skills/bb-bash/SKILL.md` |
| User | `$HOME/.claude/rules/bb-bash-rule.md` | `$HOME/.claude/skills/bb-bash/SKILL.md` |

`--codex` installs the managed AGENTS section and lazy skill:

| Scope | Instruction | Skill |
|---|---|---|
| Project | `AGENTS.md` | `.agents/skills/bb-bash/SKILL.md` |
| User | effective global Codex AGENTS file | `$HOME/.agents/skills/bb-bash/SKILL.md` |

The effective user-scope Codex instruction destination is:

1. `${CODEX_HOME:-$HOME/.codex}/AGENTS.override.md` when it exists and is non-empty;
2. otherwise `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`.

The installer prints that effective destination. `CODEX_HOME` never changes the global skill path.

Preserve legacy granular semantics:

- `--rule` and `--skill` continue to select Claude rule/skill destinations;
- `--claude` continues to select the CLAUDE.md managed snippet;
- `--agents` continues to select the AGENTS.md managed snippet;
- `--agents --global` now uses the official effective Codex global AGENTS destination instead of failing;
- presets and granular selectors combine as a union without silently changing unrelated targets.

## Managed sections

Use exact markers for `AGENTS.md` and `CLAUDE.md`:

```text
<!-- bb-bash:start -->
<!-- bb-bash:end -->
```

The installer creates a missing file, appends one marked section to unrelated content, replaces an existing marked section in place, and skips when the installed section is already identical. Reinstallation never duplicates a managed section. `--force` forces artifact replacement or managed-section refresh, never duplication.

Legacy unmarked `## Bitbucket via bb-bash` sections are not silently rewritten because they have no reliable end boundary. Default behavior skips with a migration message; `--force` may migrate the legacy trailing section, with that behavior documented and tested.

`--dry-run` performs no destination writes or downloads. It reports every effective destination and whether the action would create, update, or skip it. All path handling remains quoted and works with spaces and missing parent directories.

## Test-first execution order

First rewrite/add failing tests for compact artifact limits and topic coverage, then command-help/router/docs consistency.

Next add failing installer tests for Claude and Codex presets at project and user scope, including custom `CODEX_HOME`, non-empty override precedence, empty override fallback, exact Codex skill paths, missing directories, paths with spaces, preservation of unrelated content, repeated installation, force, dry-run, canonical skill equality, and legacy flags.

Implement help and installer internals only after the intended RED cases are demonstrated. Keep Bash 3.2 compatibility and avoid associative arrays.

Update `README.md`, `docs/agents/README.md`, `docs/commands.md`, `docs/contributing.md`, project agent instructions, and `CHANGELOG.md` to describe the new architecture and contributor drift rules.

## Verification

Required completion evidence:

- planted RED for an oversized compact artifact;
- planted RED for a routed command missing CLI help or docs;
- planted RED for duplicate/damaged managed sections;
- preset destination and `CODEX_HOME` precedence tests;
- dry-run proves no writes;
- fresh installed skill byte-matches the canonical repository artifact;
- full Bats suite passes;
- ShellCheck passes;
- system Bash 3.2 syntax passes;
- `git diff --check` passes;
- independent adversarial reviews report no unresolved merge blocker.

Commit, push, PR creation, and merge remain separate publication gates.
