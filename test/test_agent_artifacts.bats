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

ARTIFACTS=(
    "docs/agents/bb-bash-rule.md"
    "docs/agents/bb-bash-snippet.md"
    "docs/agents/bb-bash-skill/SKILL.md"
)

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
assert_artifact_covers() {
    local rel="$1" artifact="$BB_BASH_ROOT/$1"
    [ -f "$artifact" ] || { echo "artifact missing: $rel" >&2; return 1; }

    local missing=() cmd
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        artifact_exempt "$cmd" && continue
        grep -qF -- "bbb $cmd" "$artifact" || missing+=("$cmd")
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

@test "agent artifacts: bb-bash-rule.md covers every router command" {
    assert_artifact_covers "docs/agents/bb-bash-rule.md"
}

@test "agent artifacts: bb-bash-snippet.md covers every router command" {
    assert_artifact_covers "docs/agents/bb-bash-snippet.md"
}

@test "agent artifacts: SKILL.md covers every router command" {
    assert_artifact_covers "docs/agents/bb-bash-skill/SKILL.md"
}

# The three tests above are only as good as the parser feeding them. If the
# router's indentation changes, bbb_command_surface silently returns a short
# list — or nothing — and they all pass while covering nothing. These pin that
# down, so a broken extractor fails loudly instead of going quietly green.
@test "command surface: the parser finds the commands it should" {
    run bbb_command_surface
    [ "$status" -eq 0 ]
    contains "$output" '*pr show*'
    contains "$output" '*pr request-changes*'
    contains "$output" '*pipeline log*'
    contains "$output" '*raw-delete*'
    contains "$output" '*install-agent*'
    # Group prefixes are not commands — their subcommands stand in for them.
    not_contains "$output" '*
pr
*'
}

@test "command surface: the parser returns a plausible number of commands" {
    # A wrong-but-nonzero count is the failure mode that would slip past the
    # spot checks above: a parser matching only part of the router still finds
    # `pr show`. bbb has had 20+ commands since v0.2.0 and only grows.
    local n
    n=$(bbb_command_surface | wc -l | tr -d ' ')
    [ "$n" -ge 20 ] || {
        echo "bbb_command_surface returned only $n commands — the router parser" >&2
        echo "in test_helper.bash is probably out of step with bbb's layout." >&2
        return 1
    }
}

@test "agent artifacts: every artifact points at bbb help for freshness" {
    # install-agent drops a COPY into someone else's project; they upgrade bbb
    # months later and that copy stays frozen. No discipline in this repo fixes
    # that — only a pointer to the live binary self-heals across version skew.
    local rel
    for rel in "${ARTIFACTS[@]}"; do
        grep -qF -- "bbb help" "$BB_BASH_ROOT/$rel" || {
            echo "$rel does not mention 'bbb help'." >&2
            echo "Each artifact needs it as the freshness check: a reader whose" >&2
            echo "installed bbb is newer than their copy has no other way to find out." >&2
            return 1
        }
    done
}
