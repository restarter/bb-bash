# bb-bash-z8f: Complete pagination for PR readers

## Status and ownership

This document is the approved execution plan for beads issue `bb-bash-z8f`. Beads remains the task tracker; this file records the technical contract, implementation order, and verification evidence expected before the issue is closed.

The work is isolated on `feature/bb-bash-z8f-pagination`, based on `main`. It is a prerequisite of `bb-bash-gz5`, the native Claude Code and Codex integration work.

## Problem

Several Bitbucket collection endpoints return a first page plus an absolute `.next` URL. Current routed readers render only `.values` from that first page. Most importantly, `bbb pr comments` can silently omit the newest review comments because Bitbucket returns comment pages oldest-first.

The result must never look complete when it is truncated.

## Output contracts

`bbb pr comments <id>` fetches every available page up to a documented safety limit, excludes deleted comments as before, and renders the merged result newest-first. The first rendered comment is the newest; each subsequent comment is older.

Single-page output keeps its existing formatting. Pagination must not duplicate or drop values at page boundaries.

If the safety limit is reached while `.next` is still present, the command returns the values fetched so far and prints an explicit truncation warning. It must not silently claim completeness.

Other routed collection readers covered by this change either use the same complete pagination path or preserve an intentional bounded-window contract with an explicit truncation/scan notice:

- `pr list` paginates completely;
- PR commit statuses used by `pr checks` paginate completely;
- pipeline steps used by log selection paginate completely;
- diffstat retains its existing 100-file cap and explicit truncation notice;
- pipeline discovery retains `BB_BASH_PIPELINE_SCAN` and its existing bounded-window notices.

## Design

Add one Bash 3.2-compatible pagination helper beside the API helpers. It accepts an initial repository-relative endpoint, calls the existing `api_get` for every page, and merges each page's `.values` array without changing the API error contract.

Bitbucket returns `.next` as an absolute URL. Before following it, the helper must verify both that the URL begins with the current repository `BASE_URL` and that its raw path exactly matches the initial collection path, strip the base prefix, and pass only the resulting repository-relative endpoint back to `api_get`. Pinning the raw path rejects literal and percent-encoded traversal before curl can normalize it. An unexpected host, repository, or collection path is fatal so authenticated requests cannot be redirected by response data.

Use a finite page safety limit with a low test override. Validate the override before the first request. When the limit is reached and more pages remain, emit a warning to stderr while leaving stdout as valid merged JSON for existing jq renderers.

For comments, filter deleted records and sort the fully merged collection by creation time and comment id descending. Sorting happens after pagination so the order is global, not page-local.

Do not alter write commands, pipeline scan semantics, diffstat semantics, credentials, or general output formatting in this issue.

## Test-first execution order

First add failing tests for a two-page comments response. The test proves both page URLs were requested, comments from both pages appear exactly once, and newer comment ids render before older ones even when the API pages arrive oldest-first.

Then add failing pagination-helper coverage for off-origin and repository-traversal `.next` URLs, a transport/API failure on a later page, overflowing limit input, and a deliberately low safety limit that prints a truncation warning while returning the fetched values.

Next add focused multi-page tests for `pr list`, PR statuses in `pr checks`, and pipeline steps. Existing single-page fixtures remain regression coverage for unchanged rendering.

Implement the shared helper and route the selected readers through it only after the RED cases demonstrate the intended failures.

Finally update `docs/commands.md`, `docs/design.md`, `docs/contributing.md`, and `CHANGELOG.md` with the complete-vs-bounded pagination decision and the newest-first comments contract.

## Verification

Run the focused pagination and PR command tests first, then the complete Bats suite. Run ShellCheck over `bbb`, the test helper, and the installer script. Review the final diff for Bash 3.2 compatibility, quoted paths, preserved `set -euo pipefail` behavior, and absence of credential-bearing diagnostic output.

Completion evidence must include:

- a planted RED showing the old single-page implementation misses later comments;
- GREEN multi-page output ordered newest-first;
- GREEN safety-cap warning;
- GREEN off-origin rejection;
- all repository tests passing;
- ShellCheck passing.

Commit and publication are separate gates. Do not push or open the PR until the implementation diff and verification evidence have been reviewed and publication is authorized.
