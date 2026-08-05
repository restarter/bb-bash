# Releasing

How a `bb-bash` release is cut. Written down because the process used to live only in the heads of whoever did the last one.

`main` is protected, so a release goes through a PR like any other change.

## What users actually receive

Worth understanding before the steps, because it explains why the tag matters more than it looks:

`scripts/install.sh` resolves `https://api.github.com/repos/restarter/bb-bash/releases/latest` to a tag, SemVer-whitelists it, then fetches **raw `<tag>/bbb` and raw `<tag>/.env.example`** from that tag.

So for those two files the tag is not decoration — it *is* the artifact. A fix to `bbb` that never reaches a tag never reaches a user, no matter how green `main` is. That is how the dead API-token URL in `.env.example` (`bb-bash-63m`) reached everyone who installed: it shipped from the tag.

**But not everything ships from the tag, and the difference matters.**

| Surface | Ships from |
|---|---|
| `bbb`, `.env.example` | the **tag** (`scripts/install.sh`) |
| `docs/agents/*` — the AI artifacts | **`main`**, via `${BB_BASH_REF:-main}` in `install-agent` (`bbb:375`, `bbb:404`) |
| `scripts/install.sh` itself | **`main`** (the documented curl-pipe URL) |

So an artifact edit is live for every new `bbb install-agent` the moment it merges — before any release, while its CHANGELOG entry still sits under `[Unreleased]`. Do not read "unreleased" as "not yet reaching users" for those files.

This is also why step 2 below matters: bumping the pinned `BB_BASH_REF` examples is what makes `BB_BASH_REF=vX.Y.Z bbb install-agent` hand someone a coherent set — binary and artifacts from the same tag — instead of a tagged binary with main-tracking artifacts.

## Choosing the number

Semver, pre-1.0:

- **Minor** (`0.3.0`) — new commands or flags. Any addition to the router or to `usage()`.
- **Patch** (`0.2.4`) — fixes only, no new surface.

The call is the maintainer's; when in doubt, ask rather than assume. `v0.3.0` was minor because it added `raw-put`, `raw-delete`, `pr request-changes`, `pr unrequest-changes`, `--destination` and `--stat`.

**The rule is forward-looking — the history does not follow it.** `v0.2.2` shipped `pr logs`, `pipeline log`, `raw --text` and `BB_BASH_PIPELINE_SCAN` under a *patch* bump; by the rule above that was a minor. `v0.2.1` also carried an `### Added` section, though docs-only. Cite `v0.3.0` as the precedent, not the 0.2.x line.

## Steps

### 1. Branch from an up-to-date `main`

```bash
git checkout main && git pull --ff-only
git checkout -b release/v0.3.0
```

### 2. Refresh the version examples

Several places show a pinned tag as an *example*, and nothing breaks when they fall behind — which is precisely why they do. They read as "the current release" to anyone skimming:

```bash
grep -rn 'BB_BASH_REF=v' bbb README.md docs/ --exclude=releasing.md
```

Bump each to the version being cut. There are six as of `v0.3.0` (`bbb` ×2, `README.md`, `docs/installation.md`, `docs/commands.md`, `docs/agents/README.md`); check rather than assume the count. The `--exclude` keeps this file's own recipe line out of the results.

### 3. Promote `[Unreleased]` in `CHANGELOG.md`

Insert a new version heading below `## [Unreleased]` and leave `[Unreleased]` in place, empty, for the next cycle:

```markdown
## [Unreleased]

## [0.3.0] - 2026-08-05
```

Entries themselves do not move — the heading is inserted above them. There are no link-reference footers to maintain in this file.

### 4. Commit

```bash
git add CHANGELOG.md bbb README.md docs/
git commit -m "chore(bb-bash-XXX): bump CHANGELOG for v0.3.0 release"
```

The body should say what is being promoted and why the number is minor or patch. See `5397231` for the shape.

The task-id scope is the repo convention (`docs/contributing.md` → Commit convention). History is split — `v0.2.0` and `v0.2.1` carry one, `v0.3.0` does not — so use it and keep the exception from spreading.

### 5. PR, wait for CI, merge

```bash
git push -u origin release/v0.3.0
gh pr create --base main --title "chore: v0.3.0 release" --body "..."
gh pr checks <N> --watch
gh pr merge <N> --merge --delete-branch
```

**`--merge`, never `--squash`.** Feature commits stay individually visible on `main`; squashing a release PR would also collapse the CHANGELOG commit into a merge with no useful history.

Do not merge on red CI. A release is the one place where "it is probably fine" costs the most, because the tag is immutable in practice once anyone has installed from it.

### 6. Tag the merge commit

```bash
git checkout main && git pull --ff-only
SHA=$(gh pr view <N> --json mergeCommit -q .mergeCommit.oid)
git tag -a v0.3.0 -m "v0.3.0 — short descriptor" "$SHA"
git push origin v0.3.0
```

Annotated (`-a`), on **the release PR's merge commit** — that is the commit whose tree contains the promoted CHANGELOG, and the tree the raw fetch above will serve.

Anchor to the PR, not to `HEAD`. If any other PR merges between the previous step and this one, `HEAD` has moved on and the tag would silently ship changes that were never part of this release — and step 8 below would still pass, because the new symbol it greps for is present either way.

### 7. Create the GitHub release

```bash
gh release create v0.3.0 --title "v0.3.0 — short descriptor" --notes "..."
```

Title convention: `vX.Y.Z — <what changed, in a few words>`.

Release notes are for **users**, not reviewers. Lead with what they can now do — one runnable command per feature, the output where it is not obvious, and a line on what it replaces. Rationale, trade-offs and API findings belong in the CHANGELOG and the PRs, which is where someone goes when they want the reasoning. If the notes read like a design document, they are wrong.

### 8. Verify what the installer will serve

Do not skip this. It is the only step that checks the thing users actually touch:

```bash
LATEST=$(curl -fsSL https://api.github.com/repos/restarter/bb-bash/releases/latest | jq -r .tag_name)
echo "$LATEST"                                                             # expect the new tag
curl -fsSL "https://raw.githubusercontent.com/restarter/bb-bash/${LATEST}/bbb" | grep -c 'raw-put)'
curl -fsSL "https://raw.githubusercontent.com/restarter/bb-bash/${LATEST}/.env.example" | head -20
```

Substitute a symbol that is genuinely new in this release for `raw-put)`. If it is missing, the tag is on the wrong commit.

## After the release

- `[Unreleased]` is empty and ready.
- The AI artifacts under `docs/agents/` are covered by `test/test_agent_artifacts.bats`, which fails when a router command is missing from any of them — so a release cannot quietly ship a command the artifacts do not mention. It does not check *wording*, only presence; a new caveat still has to be written by hand.
