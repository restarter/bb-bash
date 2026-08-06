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
# Matching goes through bbb_text_mentions_command — the ONE definition of
# "mentions a command" (test_helper.bash). Every consumer that grew its own copy
# has so far got the prefix boundary wrong, so there is deliberately no second
# copy here.
assert_artifact_covers() {
    local rel="$1" artifact="$BB_BASH_ROOT/$1"
    [ -f "$artifact" ] || { echo "artifact missing: $rel" >&2; return 1; }

    local missing=() cmd
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        artifact_exempt "$cmd" && continue
        bbb_text_mentions_command "$cmd" < "$artifact" || missing+=("$cmd")
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

# ONE accounting guard, not four. Regressing the parser four ways — dropping the
# prefix filter, reverting alternation support, losing the top-level tier,
# renaming the router variable — this test fails on all four, while the
# per-property assertions it replaced each caught a strict subset and never fired
# alone. Guards are code that can be wrong too, and in this suite three of them
# were; fewer and sharper beats more.
@test "command surface: accounts for every arm the router declares" {
    # surface == arms - groups. Arms are counted at ANY depth, so anything the
    # surface cannot reach shows up as a shortfall rather than as quiet
    # under-coverage: an alternation arm the regex skips, a new command group,
    # a renamed dispatch variable, a reindented router.
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
        echo "  group prefixes  : $(bbb_router_group_prefixes | tr '\n' ' ')" >&2
        echo "" >&2
        echo "THE BUG IS IN THE PARSER, NOT IN THE ARTIFACTS. bbb_command_surface" >&2
        echo "in test/test_helper.bash cannot see some arm shape or nesting the" >&2
        echo "router now uses. If other tests in this file also failed naming" >&2
        echo "specific commands, fix this one first — those names are collateral." >&2
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
    #
    # Two mention shapes, because the artifacts use both: the runnable `bbb pr x`
    # form, and backticked prose (`pr decline`) — 20 of the latter today. Checking
    # only the first left exactly the rename scenario above passing green, with a
    # whole bullet in rule.md still explaining a command that no longer existed.
    # The prose pattern is built from the DERIVED group prefixes; a hard-coded
    # `pr|pipeline` here would be the third copy of that knowledge.
    local surface rel cand failed=0 groups
    surface=$(bbb_command_surface)
    groups=$(bbb_router_group_prefixes | paste -sd'|' -)
    while IFS= read -r rel; do
        while IFS= read -r cand; do
            [ -n "$cand" ] || continue
            artifact_prose_noise "$cand" && continue
            printf '%s\n' "$surface" | grep -qxF "$cand" || {
                echo "$rel documents 'bbb $cand', which the router does not define." >&2
                failed=1
            }
        done < <( { grep -oE 'bbb [a-z][a-z-]*( [a-z][a-z-]*)?' "$BB_BASH_ROOT/$rel" | sed 's/^bbb //'
                    grep -oE "\`(${groups}) [a-z][a-z-]*\`" "$BB_BASH_ROOT/$rel" | tr -d '`'
                  } | sort -u)
    done < <(artifact_files)
    [ "$failed" -eq 0 ]
}

@test "bbb help lists every command the router defines" {
    # The artifacts point at `bbb help` as the source of truth for which commands
    # the installed binary accepts — the answer to a frozen copy going stale.
    # That promise is only as good as usage(), which was itself kept in sync by
    # remembering step 3 of the checklist: the rule this suite replaces.
    #
    # Run from a copy so no .env sits beside it: bbb sources ${SCRIPT_DIR}/.env,
    # and this is the only non-live test that executes the real binary. Without
    # the copy a contributor's credentials file is sourced into the test, and a
    # bad one fails here with a message pointing nowhere near the cause.
    local cmd failed=0 out isolated="$BATS_TEST_TMPDIR/bbb"
    cp "$BB_BASH_SCRIPT" "$isolated"
    run "$isolated" help
    [ "$status" -eq 0 ] || { echo "bbb help exited $status" >&2; return 1; }
    out="$output"
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        printf '%s\n' "$out" | bbb_text_mentions_command "$cmd" || {
            echo "bbb help does not list 'bbb $cmd' — usage() is behind the router." >&2
            failed=1
        }
    done < <(bbb_command_surface)
    [ "$failed" -eq 0 ]
}

@test "bbb -h and --help are routed, not treated as unknown commands" {
    # docs/commands.md documents them as `help` synonyms. The auth short-circuit
    # already lists them; without a matching router arm they fell through to
    # `*) usage; exit 1` — printing the right text with the WRONG status, making
    # `bbb --help` indistinguishable from `bbb --hepl` to any caller under set -e.
    local isolated="$BATS_TEST_TMPDIR/bbb" flag
    cp "$BB_BASH_SCRIPT" "$isolated"
    for flag in -h --help; do
        run "$isolated" "$flag"
        [ "$status" -eq 0 ] || { echo "bbb $flag exited $status, expected 0" >&2; return 1; }
        contains "$output" '*Usage:*'
    done
}

@test "the header docstring lists every command the router defines" {
    # Step 3 of the checklist names two surfaces — usage() AND the header
    # docstring. Only one of them was checked, and the docstring was already
    # missing `bbb help` when the test for usage() landed.
    local cmd failed=0 doc
    doc=$(sed -n '1,60p' "$BB_BASH_SCRIPT")
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        printf '%s\n' "$doc" | bbb_text_mentions_command "$cmd" || {
            echo "the header docstring in bbb does not list 'bbb $cmd'." >&2
            failed=1
        }
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
