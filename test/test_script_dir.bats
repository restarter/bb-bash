#!/usr/bin/env bats
# Tests for bb-api's resolve_script_dir — symlink resolution with cycle
# protection. Sources bb-api via test_helper.bash's load_bb_api; the function
# is defined in Helpers (above the BASH_SOURCE guard), so it's available
# after sourcing without firing main().

load test_helper

setup() {
    TEST_TMP=$(mktemp -d)
    load_bb_api
}

teardown() {
    [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

@test "resolve_script_dir: returns dirname of a non-symlink path" {
    local target="$TEST_TMP/sub/bb-api"
    mkdir -p "$(dirname "$target")"
    : > "$target"
    run resolve_script_dir "$target"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/sub" ]
}

@test "resolve_script_dir: follows a single symlink (absolute target)" {
    local real="$TEST_TMP/data/bb-api"
    local link="$TEST_TMP/bin/bb-api"
    mkdir -p "$(dirname "$real")" "$(dirname "$link")"
    : > "$real"
    ln -s "$real" "$link"
    run resolve_script_dir "$link"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/data" ]
}

@test "resolve_script_dir: follows a chain of symlinks" {
    local real="$TEST_TMP/data/bb-api"
    local mid="$TEST_TMP/mid/bb-api"
    local link="$TEST_TMP/bin/bb-api"
    mkdir -p "$(dirname "$real")" "$(dirname "$mid")" "$(dirname "$link")"
    : > "$real"
    ln -s "$real" "$mid"
    ln -s "$mid" "$link"
    run resolve_script_dir "$link"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/data" ]
}

@test "resolve_script_dir: handles relative symlink targets" {
    local real="$TEST_TMP/data/bb-api"
    local link="$TEST_TMP/bin/bb-api"
    mkdir -p "$(dirname "$real")" "$(dirname "$link")"
    : > "$real"
    ln -s ../data/bb-api "$link"
    run resolve_script_dir "$link"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/data" ]
}

@test "resolve_script_dir: handles paths with embedded spaces" {
    local real="$TEST_TMP/dir with spaces/bb-api"
    mkdir -p "$(dirname "$real")"
    : > "$real"
    run resolve_script_dir "$real"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/dir with spaces" ]
}

@test "resolve_script_dir: broken symlink (missing target) dies with context" {
    # Function detects the missing parent dir explicitly and dies with a
    # bb-api-prefixed message — much better UX than the raw `cd: No such
    # file or directory` the user used to see under set -e.
    local broken="$TEST_TMP/here/bb-api"
    mkdir -p "$(dirname "$broken")"
    ln -s /nonexistent/path "$broken"
    run resolve_script_dir "$broken"
    [ "$status" -ne 0 ]
    contains "$output" "*broken symlink*"
}

@test "resolve_script_dir: refuses circular symlinks (hop cap)" {
    local a="$TEST_TMP/a"
    local b="$TEST_TMP/b"
    ln -s "$b" "$a"
    ln -s "$a" "$b"
    # die() exits non-zero with an "Error: ..." message; the cycle is
    # detected by the 40-hop cap rather than hanging.
    run resolve_script_dir "$a"
    [ "$status" -ne 0 ]
    contains "$output" "*too many symlink hops*"
}

@test "resolve_script_dir: empty target argument dies" {
    run resolve_script_dir ""
    [ "$status" -ne 0 ]
    contains "$output" "*empty target*"
}
