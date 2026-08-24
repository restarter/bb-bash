#!/usr/bin/env bats

load test_helper

agent_artifacts() {
    printf '%s\n' \
        'docs/agents/bb-bash-rule.md' \
        'docs/agents/bb-bash-snippet.md' \
        'docs/agents/bb-bash-skill/SKILL.md'
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

@test "every agent artifact is independently usable for complete safe PR workflows" {
    local rel failed=0 term
    while IFS= read -r rel; do
        for term in \
            'bbb help' 'pr show' 'pr diff' 'pr comments' 'pagination' 'newest-first' \
            'pr checks' 'pipeline' '--old' 'request-changes' 'decline' 'authorization' \
            'read the remote state back' '--destination' 'raw' 'untrusted'; do
            grep -qiF -- "$term" "$BB_BASH_ROOT/$rel" || {
                echo "$rel misses required standalone workflow topic: $term" >&2
                failed=1
            }
        done
        grep -q '^EOF$' "$BB_BASH_ROOT/$rel" || {
            echo "$rel does not keep the heredoc terminator at column 1" >&2
            failed=1
        }
        if grep -Eq '^[[:space:]]+EOF$' "$BB_BASH_ROOT/$rel"; then
            echo "$rel contains an indented heredoc terminator" >&2
            failed=1
        fi
        awk '
            $0 == "**Findings:**" { heading = NR }
            $0 == "- First issue." && NR == heading + 2 { separated = 1 }
            END { exit separated ? 0 : 1 }
        ' "$BB_BASH_ROOT/$rel" || {
            echo "$rel example has no blank line before its Markdown list" >&2
            failed=1
        }
    done < <(agent_artifacts)
    [ "$failed" -eq 0 ]
}

@test "every agent artifact carries the comment-writing contract" {
    local rel failed=0 term
    while IFS= read -r rel; do
        for term in \
            "<<'EOF'" 'column 1' 'do not indent' 'Python-Markdown' 'blank line' \
            'Do not use HTML' 'publish immediately' 'pr edit-comment' 'complete body'; do
            grep -qiF -- "$term" "$BB_BASH_ROOT/$rel" || {
                echo "$rel misses required comment-writing topic: $term" >&2
                failed=1
            }
        done
    done < <(agent_artifacts)
    [ "$failed" -eq 0 ]
}

@test "lazy skill exposes the public bbb name and invocation hints" {
    local skill="$BB_BASH_ROOT/docs/agents/bb-bash-skill/SKILL.md"
    grep -q '^name: bbb$' "$skill"
    grep -qF '/bbb' "$skill"
    grep -qF '$bbb' "$skill"
    grep -qF 'docs/commands.md' "$skill"
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
