#!/usr/bin/env bats
#
# Guards the promise in docs/agents/README.md — "pick any one, each is fully
# self-contained" — and step 7 of CLAUDE.md, which requires every new command to
# reach all three AI artifacts.
#
# That rule already existed and was already being followed; what it lacked was
# anything that CHECKS it. A rule enforced only by remembering a step 7 out of
# eight fails the same way the thing it guards fails. This makes forgetting show
# up as a red suite instead of as a stale artifact nobody notices for a release
# or two.

load test_helper

# artifact_files — the shipped artifacts, DISCOVERED rather than listed: every
# .md under docs/agents/ except README.md, which is the index explaining them
# rather than one of them.
#
# Discovery so that a fourth artifact is covered the moment it lands. A literal
# list here would have been one more place to forget — the same failure this
# suite exists to catch, one level up from the artifacts themselves.
#
# Paths are repo-relative, as assert_artifact_covers and the messages expect.
artifact_files() {
    find "$BB_BASH_ROOT/docs/agents" -name '*.md' ! -name 'README.md' \
        | sed "s|^$BB_BASH_ROOT/||" | sort
}

# Deliberate exemptions. Every entry MUST carry its reason inline — an allowlist
# without reasons becomes the place drift hides, which would defeat the point.
artifact_exempt() {
    case "$1" in
        # The command that INSTALLS these artifacts. An agent reading one has it
        # already, so listing it there is noise rather than capability.
        install-agent) return 0 ;;
        *) return 1 ;;
    esac
}

# A mention ANYWHERE in the artifact counts — the command list, a workflow step,
# a caveat in prose. The goal is that a reader learns the command exists, and
# prose does that as well as a list does. Insisting it appear specifically in a
# fenced command block would need block parsing and would fail on commands that
# are legitimately only explained in context (`pr decline` in the review
# workflow, say).
#
# Consequence worth knowing before you write a negative test: deleting a command
# from the list does NOT fail while prose still names it. Delete every mention.
#
# The match is anchored at a word boundary, NOT a plain substring. Several
# commands are prefixes of others — `raw` of `raw-post`/`raw-put`/`raw-delete`,
# `pr comment` of `pr comments` — so a substring test reports `bbb raw` as
# present in a file that only ever mentions `bbb raw-post`. That blind spot sits
# exactly where a drift test has to be sharp, so the trailing character must not
# continue the command name.
assert_artifact_covers() {
    local rel="$1" artifact="$BB_BASH_ROOT/$1"
    [ -f "$artifact" ] || { echo "artifact missing: $rel" >&2; return 1; }

    local missing=() cmd
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        artifact_exempt "$cmd" && continue
        grep -qE -- "bbb ${cmd}([^a-z-]|\$)" "$artifact" || missing+=("$cmd")
    done < <(bbb_command_surface)

    if [ ${#missing[@]} -gt 0 ]; then
        {
            echo "$rel does not mention these commands from the bbb router:"
            printf '  bbb %s\n' "${missing[@]}"
            echo ""
            echo "Add them to that artifact, or — if the omission is deliberate —"
            echo "add an exemption WITH ITS REASON to artifact_exempt() in"
            echo "test/test_agent_artifacts.bats."
        } >&2
        return 1
    fi
}

@test "agent artifacts: every artifact covers every router command" {
    local rel failed=0
    while IFS= read -r rel; do
        assert_artifact_covers "$rel" || failed=1
    done < <(artifact_files)
    [ "$failed" -eq 0 ]
}

# The test above is only as good as the parser feeding it. If the router's
# indentation changes, bbb_command_surface silently returns a short list — or
# nothing — and it passes while covering nothing. The rest of this file pins the
# parser down, so a broken extractor fails loudly instead of going quietly green.
@test "command surface: the parser finds the commands it should" {
    run bbb_command_surface
    [ "$status" -eq 0 ]
    contains "$output" '*pr show*'
    contains "$output" '*pr request-changes*'
    contains "$output" '*pipeline log*'
    contains "$output" '*raw-delete*'
    contains "$output" '*install-agent*'
}

@test "command surface: group prefixes never leak in as commands" {
    # Matched per LINE, not as a glob over the joined output. The previous form
    # — not_contains "$output" '*\npr\n*' — could not fail: it needs a newline
    # BEFORE `pr`, and `pr)` is the FIRST arm in the router, so a regressed
    # filter puts `pr` on line 1 with nothing in front of it. `pipeline` was not
    # checked at all. not_contains fails open, exactly as test_helper.bash warns.
    local leaked
    leaked=$(bbb_command_surface | grep -cxE 'pr|pipeline' || true)
    [ "$leaked" -eq 0 ] || {
        echo "group prefixes leaked into the command surface ($leaked)" >&2
        echo "They are prefixes, not runnable commands — bare 'bbb pr' prints usage." >&2
        return 1
    }
}

@test "command surface: accounts for every arm the router declares" {
    # The invariant that closes the CLASS of parser bug: surface == arms - groups.
    # Arms are counted at ANY depth, so anything the surface cannot reach shows up
    # as a shortfall rather than as quiet under-coverage. Two real escapes it
    # catches: an alternation arm (`a|b)`) the surface regex once skipped, and a
    # third command group whose nested `case` the surface does not know about —
    # both of which previously left the whole suite green.
    local surface arms groups expected
    surface=$(bbb_command_surface | wc -l | tr -d ' ')
    arms=$(bbb_router_arm_count)
    groups=$(bbb_router_group_count)
    expected=$((arms - groups))
    [ "$surface" -eq "$expected" ] || {
        echo "command surface does not account for the router." >&2
        echo "  surface entries : $surface" >&2
        echo "  router arms     : $arms (any depth)" >&2
        echo "  command groups  : $groups (nested case blocks)" >&2
        echo "  expected        : $expected  (arms - groups)" >&2
        echo "" >&2
        echo "A shortfall means bbb_command_surface in test/test_helper.bash cannot" >&2
        echo "see some arm shape or nesting the router now uses — extend the parser." >&2
        echo "A new command group needs its own line there; without it, every one of" >&2
        echo "its subcommands is silently exempt from the artifact-drift check." >&2
        return 1
    }
}

@test "command surface: every tier is populated" {
    # A bare total hides a whole tier vanishing. The old `-ge 20` floor was the
    # exact residue of losing the top-level tier: 6 top + 19 pr + 1 pipeline = 26,
    # and 19 + 1 = 20 still passed it. Counted per tier, one cannot cover for
    # another.
    local top prs pipe
    top=$(bbb_command_surface | grep -cvE '^(pr|pipeline) ' || true)
    prs=$(bbb_command_surface | grep -cE '^pr ' || true)
    pipe=$(bbb_command_surface | grep -cE '^pipeline ' || true)
    [ "$top" -ge 5 ] && [ "$prs" -ge 15 ] && [ "$pipe" -ge 1 ] || {
        echo "a command tier looks empty or truncated: top=$top pr=$prs pipeline=$pipe" >&2
        return 1
    }
}

@test "agent artifacts: every artifact points at bbb help for freshness" {
    # install-agent drops a COPY into someone else's project; they upgrade bbb
    # months later and that copy stays frozen. No discipline in this repo fixes
    # that — only a pointer to the live binary self-heals across version skew.
    local rel failed=0
    while IFS= read -r rel; do
        grep -qF -- "bbb help" "$BB_BASH_ROOT/$rel" || {
            echo "$rel does not mention 'bbb help'." >&2
            echo "Each artifact needs it as the freshness check: a reader whose" >&2
            echo "installed bbb is newer than their copy has no other way to find out." >&2
            failed=1
        }
    done < <(artifact_files)
    [ "$failed" -eq 0 ]
}

# Prose that reads as a command to the extractor below. Kept tiny and explicit:
# if a new phrase lands here, prefer rewording the artifact over growing the list.
artifact_prose_noise() {
    case "$1" in
        "may have"|"not on") return 0 ;;
        *) return 1 ;;
    esac
}

@test "agent artifacts: no artifact teaches a command that does not exist" {
    # Drift runs both ways. The coverage test above is router -> artifact; without
    # this one, renaming a command and adding the new name leaves every artifact
    # still teaching the old one, suite green. For a file whose whole job is
    # telling an agent what to run, a confidently documented dead command is worse
    # than a missing one — the agent will not consult `bbb help`, because it
    # already has a plan that looks like it works.
    local surface rel cand failed=0
    surface=$(bbb_command_surface)
    while IFS= read -r rel; do
        while IFS= read -r cand; do
            [ -n "$cand" ] || continue
            artifact_prose_noise "$cand" && continue
            printf '%s\n' "$surface" | grep -qxF "$cand" || {
                echo "$rel documents 'bbb $cand', which the router does not define." >&2
                failed=1
            }
        done < <(grep -oE 'bbb [a-z][a-z-]*( [a-z][a-z-]*)?' "$BB_BASH_ROOT/$rel" \
                   | sed 's/^bbb //' | sort -u)
    done < <(artifact_files)
    [ "$failed" -eq 0 ]
}

@test "bbb help lists every command the router defines" {
    # The artifacts now point at `bbb help` as the source of truth for what the
    # installed binary accepts — the answer to a frozen copy going stale. That
    # promise is only as good as usage(), which was itself kept in sync by
    # remembering step 3 of the checklist: the same rule this suite replaces.
    local cmd failed=0 out
    out=$("$BB_BASH_SCRIPT" help 2>&1)
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        case "$out" in
            *"bbb $cmd"*) ;;
            *) echo "bbb help does not list 'bbb $cmd' — usage() is behind the router." >&2; failed=1 ;;
        esac
    done < <(bbb_command_surface)
    [ "$failed" -eq 0 ]
}

# Discovery is now load-bearing for both tests above: if artifact_files stops
# finding things — moved directory, renamed files — they pass while checking
# nothing at all.
@test "agent artifacts: discovery finds the artifacts that actually ship" {
    run artifact_files
    [ "$status" -eq 0 ]
    contains "$output" '*docs/agents/bb-bash-rule.md*'
    contains "$output" '*docs/agents/bb-bash-snippet.md*'
    contains "$output" '*docs/agents/bb-bash-skill/SKILL.md*'
    # README.md is the index that explains the artifacts, not one of them.
    not_contains "$output" '*README*'
    local n
    n=$(artifact_files | wc -l | tr -d ' ')
    [ "$n" -ge 3 ] || { echo "discovery returned only $n artifacts" >&2; return 1; }
}
