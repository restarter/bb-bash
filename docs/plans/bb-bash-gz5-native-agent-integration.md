# bb-bash-gz5: Native Claude Code and Codex integration

## Status and scope

This is the approved execution plan for beads issue `bb-bash-gz5`. Beads remains the task tracker; this file defines the implementation contract and verification evidence.

The work is isolated on `feature/bb-bash-gz5-native-agent-integration`, based on `origin/main` after the merge of pagination prerequisite `bb-bash-z8f` in PR #27.

## Goals

Provide native, independently usable integration for Claude Code and Codex:

- a self-contained always-loaded instruction for zero-friction use in selected projects;
- a self-contained lazy `bbb` skill for clean-context and manual-invocation users;
- project and user scopes for both products;
- current command-specific CLI help as the syntax authority;
- idempotent managed sections that preserve unrelated user content;
- backward-compatible granular installer flags.

## Content architecture

Keep `docs/agents/bb-bash-rule.md` and `docs/agents/bb-bash-snippet.md` concise, but make each independently sufficient to review and operate on a Bitbucket PR safely. Do not impose a byte limit before workflow correctness. Avoid a full command inventory and use current command help for syntax.

Keep `docs/agents/bb-bash-skill/SKILL.md` as the canonical downloadable source, but expose it publicly as the `bbb` skill (`name: bbb`) and install it into native `.../skills/bbb/SKILL.md` directories. It is independently usable through automatic context activation, Claude Code `/bbb`, or Codex `$bbb`.

All three artifacts cover complete review preflight, all paginated comments, inline placement and `--old`, review verdict semantics, authorization and post-write readback, pipelines, retargeting, and raw API safety. They also carry a short comment-writing contract: quoted heredocs, column-one delimiters and intentional indentation, literal shell-sensitive text, Python-Markdown blank-line rules, no HTML, immediate publication, and full-body comment edits. The rule/snippet and skill may duplicate this safety-critical workflow by design.

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

The artifacts are tested for self-contained workflow and comment-writing invariants, not for a hard byte limit or full router inventory.

## Installer presets and destinations

Add native presets:

```text
bbb install-agent --claude-code [--global]
bbb install-agent --codex [--global]
```

`--claude-code` installs the self-contained rule and lazy skill:

| Scope | Instruction | Skill |
|---|---|---|
| Project | `.claude/rules/bb-bash-rule.md` | `.claude/skills/bbb/SKILL.md` |
| User | `$HOME/.claude/rules/bb-bash-rule.md` | `$HOME/.claude/skills/bbb/SKILL.md` |

`--codex` installs the managed AGENTS section and lazy skill:

| Scope | Instruction | Skill |
|---|---|---|
| Project | `AGENTS.md` | `.agents/skills/bbb/SKILL.md` |
| User | effective global Codex AGENTS file | `$HOME/.agents/skills/bbb/SKILL.md` |

The effective user-scope Codex instruction destination is:

1. `${CODEX_HOME:-$HOME/.codex}/AGENTS.override.md` when it exists and is non-empty;
2. otherwise `${CODEX_HOME:-$HOME/.codex}/AGENTS.md`.

The installer prints that effective destination. `CODEX_HOME` never changes the global skill path.

Preserve legacy granular semantics:

- `--rule` and `--skill` continue to select the self-contained Claude rule/skill;
- new `--codex-skill` selects only the Codex-native `bbb` skill, enabling a clean-context/manual `$bbb` installation;
- `--claude` continues to select the CLAUDE.md managed snippet;
- `--agents` continues to select the AGENTS.md managed snippet;
- `--agents --global` now uses the official effective Codex global AGENTS destination instead of failing;
- presets and granular selectors combine as a union without silently changing unrelated targets;
- when a legacy `.../skills/bb-bash/SKILL.md` exists, report the migration to `.../skills/bbb/SKILL.md` without deleting user files silently.

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

First rewrite/add failing tests for self-contained artifact and comment-writing coverage, then command-help/router/docs consistency.

Next add failing installer tests for Claude and Codex presets at project and user scope, including custom `CODEX_HOME`, non-empty override precedence, empty override fallback, exact Codex skill paths, missing directories, paths with spaces, preservation of unrelated content, repeated installation, force, dry-run, canonical skill equality, and legacy flags.

Implement help and installer internals only after the intended RED cases are demonstrated. Keep Bash 3.2 compatibility and avoid associative arrays.

Update `README.md`, `docs/agents/README.md`, and `docs/commands.md` to describe the independent modes, `bbb` invocation, destinations, and migration behavior.

## Verification

Required completion evidence:

- planted RED for a missing self-contained workflow or comment-writing invariant;
- planted RED for a routed command missing CLI help or docs;
- planted RED for duplicate/damaged managed sections;
- preset destination and `CODEX_HOME` precedence tests;
- dry-run proves no writes;
- fresh installed skill byte-matches the canonical repository artifact;
- full Bats suite passes;
- ShellCheck passes;
- system Bash 3.2 syntax passes;
- `git diff --check` passes;
- no unresolved merge blocker remains after an adversarial diff review.

Commit, push, PR creation, and merge remain separate publication gates.
