#!/usr/bin/env bats

load test_helper

compact_artifacts() {
    printf '%s\n' \
        'docs/agents/bb-bash-rule.md' \
        'docs/agents/bb-bash-snippet.md'
}

artifact_exempt() {
    case "$1" in
        install-agent) return 0 ;;
        *) return 1 ;;
    esac
}

@test "command surface: parser accounts for every router arm" {
    local surface arms groups expected
    surface=$(bbb_command_surface | wc -l | tr -d ' ')
    arms=$(bbb_router_arm_count)
    groups=$(bbb_router_group_count)
    expected=$((arms - groups))
    [ "$surface" -eq "$expected" ]
    contains "$(bbb_command_surface)" '*pr request-changes*'
    contains "$(bbb_command_surface)" '*pipeline log*'
    contains "$(bbb_command_surface)" '*install-agent*'
}

@test "always-loaded artifacts are at most 2 KiB each" {
    local rel bytes failed=0
    while IFS= read -r rel; do
        bytes=$(wc -c < "$BB_BASH_ROOT/$rel" | tr -d ' ')
        if [ "$bytes" -gt 2048 ]; then
            echo "$rel is $bytes bytes; maximum is 2048" >&2
            failed=1
        fi
    done < <(compact_artifacts)
    [ "$failed" -eq 0 ]
}

@test "compact artifacts carry activation, freshness, trust, and write-safety guidance" {
    local rel failed=0 term
    while IFS= read -r rel; do
        for term in 'bbb' 'bb-bash' 'bbb help' 'untrusted' 'authorization' 'request-changes' 'decline'; do
            grep -qiF -- "$term" "$BB_BASH_ROOT/$rel" || {
                echo "$rel misses required compact topic: $term" >&2
                failed=1
            }
        done
    done < <(compact_artifacts)
    [ "$failed" -eq 0 ]
}

@test "lazy skill carries the canonical non-trivial workflow topics" {
    local skill="$BB_BASH_ROOT/docs/agents/bb-bash-skill/SKILL.md" term failed=0
    for term in \
        'bbb help' 'docs/commands.md' 'pr show' 'pr diff' 'pr comments' \
        'pagination' 'pr checks' '--old' "<<'EOF'" 'request-changes' \
        'decline' 'authorization' 'readback' 'pipeline' '--destination' 'raw'; do
        grep -qiF -- "$term" "$skill" || {
            echo "skill misses required workflow topic: $term" >&2
            failed=1
        }
    done
    [ "$failed" -eq 0 ]
}

@test "every routed command has command-specific help without credentials" {
    local isolated="$BATS_TEST_TMPDIR/bbb" cmd failed=0 first
    cp "$BB_BASH_SCRIPT" "$isolated"
    while IFS= read -r cmd; do
        run "$isolated" help $cmd
        if [ "$status" -ne 0 ]; then
            echo "bbb help $cmd exited $status" >&2
            failed=1
            continue
        fi
        first=$(printf '%s\n' "$output" | sed -n '1p')
        case "$first" in
            "Usage: bbb $cmd"*) ;;
            *) echo "bbb help $cmd has no exact command usage; first line: $first" >&2; failed=1 ;;
        esac
    done < <(bbb_command_surface)
    [ "$failed" -eq 0 ]
}

doc_synopsis() {
    local cmd="$1"
    awk -v heading="## $cmd" '
        $0 == heading { found=1; next }
        found && /^## / { exit }
        found && /^\*\*Synopsis:\*\*/ {
            if (match($0, /`bbb [^`]+`/)) print substr($0, RSTART + 1, RLENGTH - 2)
            exit
        }
    ' "$BB_BASH_ROOT/docs/commands.md"
}

@test "router, command help, and docs command synopses stay aligned" {
    local isolated="$BATS_TEST_TMPDIR/bbb" cmd cli docs failed=0
    cp "$BB_BASH_SCRIPT" "$isolated"
    while IFS= read -r cmd; do
        cli=$("$isolated" help $cmd | sed -n 's/^Usage: //p' | head -n1)
        docs=$(doc_synopsis "$cmd")
        if [ -z "$docs" ] || [ "$cli" != "$docs" ]; then
            echo "synopsis drift for '$cmd': CLI='$cli' docs='$docs'" >&2
            failed=1
        fi
    done < <(bbb_command_surface)
    [ "$failed" -eq 0 ]
}

@test "bbb -h and --help remain successful global help aliases" {
    local isolated="$BATS_TEST_TMPDIR/bbb" flag
    cp "$BB_BASH_SCRIPT" "$isolated"
    for flag in -h --help; do
        run "$isolated" "$flag"
        [ "$status" -eq 0 ]
        contains "$output" '*Usage:*'
    done
}
