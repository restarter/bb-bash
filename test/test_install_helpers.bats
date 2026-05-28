#!/usr/bin/env bats
# Tests for scripts/install.sh pure-function helpers. Sources install.sh
# under its BASH_SOURCE guard (main is wrapped in _bbb_install_main()
# and only fires when run directly), so helpers are usable individually.
#
# WARNING: don't combine load_install_sh with load_bbb in the same @test —
# both files define die(); the second source silently overwrites the first.

load test_helper

INSTALL_SH="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/scripts/install.sh"

setup() {
    TEST_TMP=$(mktemp -d)
    # Save PATH — tests below replace $PATH with synthetic paths to exercise
    # path_contains / find_bbb_on_path; teardown needs the real PATH to
    # find `rm`, `wc`, `tr`, etc.
    _SAVED_PATH=$PATH
}

teardown() {
    PATH=$_SAVED_PATH
    [[ -n "${TEST_TMP:-}" && -d "$TEST_TMP" ]] && rm -rf "$TEST_TMP"
}

# load_install_sh: save+restore -e/-u so test body isn't disrupted by
# install.sh's `set -euo pipefail`.
load_install_sh() {
    local _saved_opts=$-
    # shellcheck source=/dev/null
    source "$INSTALL_SH"
    case "$_saved_opts" in *e*) ;; *) set +e ;; esac
    case "$_saved_opts" in *u*) ;; *) set +u ;; esac
    STEP_CURRENT=0
    unset RELEASE_JSON TAG INSTALLED_TAG DOWNLOAD_TMP
}

# --- pick_install_dir ---

@test "install.sh: pick_install_dir returns preferred when writable" {
    load_install_sh
    mkdir -p "$TEST_TMP/preferred"
    run pick_install_dir "$TEST_TMP/preferred" "$TEST_TMP/fallback"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/preferred" ]
}

@test "install.sh: pick_install_dir falls back when preferred not writable" {
    load_install_sh
    # Non-existent preferred is also not writable
    run pick_install_dir "$TEST_TMP/nope" "$TEST_TMP/fallback"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/fallback" ]
    [ -d "$TEST_TMP/fallback" ]
}

@test "install.sh: pick_install_dir respects BB_BASH_USER_ONLY" {
    load_install_sh
    mkdir -p "$TEST_TMP/preferred"
    BB_BASH_USER_ONLY=1
    run pick_install_dir "$TEST_TMP/preferred" "$TEST_TMP/fallback"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/fallback" ]
}

# --- pick_data_dir ---

@test "install.sh: pick_data_dir respects XDG_DATA_HOME" {
    load_install_sh
    XDG_DATA_HOME="$TEST_TMP/xdg"
    run pick_data_dir
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/xdg/bb-bash" ]
}

@test "install.sh: pick_data_dir falls back to ~/.local/share when XDG unset" {
    load_install_sh
    HOME="$TEST_TMP/home"
    unset XDG_DATA_HOME
    run pick_data_dir
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/home/.local/share/bb-bash" ]
}

# --- path_contains ---

@test "install.sh: path_contains matches first" {
    load_install_sh; PATH="/first:/middle:/last:$_SAVED_PATH"
    run path_contains "/first"; [ "$status" -eq 0 ]
}

@test "install.sh: path_contains matches middle" {
    load_install_sh; PATH="/first:/middle:/last:$_SAVED_PATH"
    run path_contains "/middle"; [ "$status" -eq 0 ]
}

@test "install.sh: path_contains matches last" {
    load_install_sh; PATH="/first:/middle:/last:$_SAVED_PATH"
    run path_contains "/last"; [ "$status" -eq 0 ]
}

@test "install.sh: path_contains rejects non-member" {
    load_install_sh; PATH="/first:/middle:/last:$_SAVED_PATH"
    run path_contains "/nope"; [ "$status" -eq 1 ]
}

@test "install.sh: path_contains rejects substring" {
    load_install_sh; PATH="/first:/middle:/last:$_SAVED_PATH"
    run path_contains "/firs"; [ "$status" -eq 1 ]
}

# --- extract_tag_name ---

@test "install.sh: extract_tag_name parses typical release JSON" {
    load_install_sh
    run extract_tag_name '{"url": "...", "tag_name": "v0.1.0", "name": "v0.1"}'
    [ "$status" -eq 0 ]
    [ "$output" = "v0.1.0" ]
}

@test "install.sh: extract_tag_name handles tag_name with build metadata" {
    load_install_sh
    run extract_tag_name '{"tag_name": "v0.1.0+build.1"}'
    [ "$status" -eq 0 ]
    [ "$output" = "v0.1.0+build.1" ]
}

@test "install.sh: extract_tag_name handles tag_name with pre-release suffix" {
    load_install_sh
    run extract_tag_name '{"tag_name": "v0.2.0-rc.1"}'
    [ "$status" -eq 0 ]
    [ "$output" = "v0.2.0-rc.1" ]
}

@test "install.sh: extract_tag_name ignores name field with literal 'tag_name'" {
    load_install_sh
    # Defensive: a release with name containing the string "tag_name" shouldn't fool the parser.
    run extract_tag_name '{"name": "Release tag_name update", "tag_name": "v0.2.0"}'
    [ "$status" -eq 0 ]
    [ "$output" = "v0.2.0" ]
}

@test "install.sh: extract_tag_name returns non-zero on missing tag_name" {
    load_install_sh
    run extract_tag_name '{"foo": "bar"}'
    [ "$status" -ne 0 ]
}

@test "install.sh: extract_tag_name rejects non-SemVer tag" {
    load_install_sh
    run extract_tag_name '{"tag_name": "../../evil"}'
    [ "$status" -ne 0 ]
    contains "$output" "*Refusing tag*"
}

@test "install.sh: extract_tag_name rejects path traversal with v-prefix" {
    # A case-glob like `v[0-9]*.[0-9]*.[0-9]*` would PASS this — `*` is greedy
    # and unrestricted. The bash regex must reject it because `..` between
    # major and minor isn't `[0-9]+`. Regression test for plan-review B4.
    load_install_sh
    run extract_tag_name '{"tag_name": "v1../../../evil.0.0"}'
    [ "$status" -ne 0 ]
    contains "$output" "*Refusing tag*"
}

@test "install.sh: extract_tag_name rejects tag with whitespace" {
    load_install_sh
    run extract_tag_name '{"tag_name": "v 0.1.0"}'
    [ "$status" -ne 0 ]
}

@test "install.sh: extract_tag_name handles malformed JSON (returns nonzero, no crash)" {
    load_install_sh
    run extract_tag_name '{not json'
    [ "$status" -ne 0 ]
}

# --- _resolve_symlink_chain ---

@test "install.sh: _resolve_symlink_chain follows a chain" {
    load_install_sh
    mkdir -p "$TEST_TMP/real" "$TEST_TMP/mid" "$TEST_TMP/link"
    : > "$TEST_TMP/real/bbb"
    ln -s "$TEST_TMP/real/bbb" "$TEST_TMP/mid/bbb"
    ln -s "$TEST_TMP/mid/bbb"  "$TEST_TMP/link/bbb"
    run _resolve_symlink_chain "$TEST_TMP/link/bbb"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_TMP/real/bbb" ]
}

@test "install.sh: _resolve_symlink_chain caps cycles (no hang)" {
    load_install_sh
    ln -s "$TEST_TMP/b" "$TEST_TMP/a"
    ln -s "$TEST_TMP/a" "$TEST_TMP/b"
    # Function bails after 40 hops, returning the current symlink in the cycle.
    # If the hop cap were missing this would hang the test; rely on that rather
    # than `timeout` (not on stock macOS as `timeout`).
    run _resolve_symlink_chain "$TEST_TMP/a"
    [ "$status" -eq 0 ]
    case "$output" in
        "$TEST_TMP/a"|"$TEST_TMP/b") ;;
        *) false ;;
    esac
}

# --- find_bbb_on_path ---

@test "install.sh: find_bbb_on_path detects duplicates (PATH=A:A)" {
    load_install_sh
    mkdir -p "$TEST_TMP/binA"
    printf '#!/bin/sh\necho A\n' > "$TEST_TMP/binA/bbb"
    chmod +x "$TEST_TMP/binA/bbb"
    PATH="$TEST_TMP/binA:$TEST_TMP/binA:$_SAVED_PATH"
    run find_bbb_on_path
    PATH=$_SAVED_PATH
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "1" ]
}

@test "install.sh: find_bbb_on_path lists two distinct entries" {
    load_install_sh
    mkdir -p "$TEST_TMP/binA" "$TEST_TMP/binB"
    printf '#!/bin/sh\necho A\n' > "$TEST_TMP/binA/bbb"
    printf '#!/bin/sh\necho B\n' > "$TEST_TMP/binB/bbb"
    chmod +x "$TEST_TMP/binA/bbb" "$TEST_TMP/binB/bbb"
    PATH="$TEST_TMP/binA:$TEST_TMP/binB:$_SAVED_PATH"
    run find_bbb_on_path
    PATH=$_SAVED_PATH
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "2" ]
    contains "$output" "*binA/bbb*"
    contains "$output" "*binB/bbb*"
}

@test "install.sh: find_bbb_on_path follows absolute-target symlink" {
    load_install_sh
    mkdir -p "$TEST_TMP/real" "$TEST_TMP/link"
    printf '#!/bin/sh\n' > "$TEST_TMP/real/bbb"
    chmod +x "$TEST_TMP/real/bbb"
    ln -s "$TEST_TMP/real/bbb" "$TEST_TMP/link/bbb"
    PATH="$TEST_TMP/link:$_SAVED_PATH"
    run find_bbb_on_path
    PATH=$_SAVED_PATH
    [ "$status" -eq 0 ]
    contains "$output" "*real/bbb*"
}

@test "install.sh: find_bbb_on_path follows relative-target symlink" {
    load_install_sh
    mkdir -p "$TEST_TMP/real" "$TEST_TMP/link"
    printf '#!/bin/sh\n' > "$TEST_TMP/real/bbb"
    chmod +x "$TEST_TMP/real/bbb"
    ln -s ../real/bbb "$TEST_TMP/link/bbb"
    PATH="$TEST_TMP/link:$_SAVED_PATH"
    run find_bbb_on_path
    PATH=$_SAVED_PATH
    [ "$status" -eq 0 ]
    contains "$output" "*real/bbb*"
}

@test "install.sh: find_bbb_on_path skips non-executable file" {
    load_install_sh
    mkdir -p "$TEST_TMP/bin"
    : > "$TEST_TMP/bin/bbb"   # exists but not +x
    PATH="$TEST_TMP/bin:$_SAVED_PATH"
    run find_bbb_on_path
    PATH=$_SAVED_PATH
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- entry-point guard (regression: bb-api-bhf) ---

@test "install.sh: BASH_SOURCE guard survives stdin pipe (curl|bash) under set -u" {
    # Regression for bb-api-bhf — `curl ... | bash` failed because the
    # entry-point guard `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` dereferenced
    # an empty array under `set -u` and aborted before main ran.
    #
    # We simulate the curl-pipe by feeding install.sh through stdin.
    # The main-call line is stripped so the test exercises ONLY the guard
    # condition — not the actual installer (which would mutate ~/.local).
    # If the guard line trips `set -u`, this produces "unbound variable"
    # and a non-zero exit.
    # Replace the main-call line with `:` (no-op) — deleting it would leave
    # an empty then/fi block which is a bash syntax error.
    sed 's|^    _bbb_install_main "\$@"$|    :|' "$INSTALL_SH" > "$TEST_TMP/no_main.sh"
    run bash < "$TEST_TMP/no_main.sh"
    [ "$status" -eq 0 ]
    not_contains "$output" "*unbound variable*"
    not_contains "$output" "*BASH_SOURCE*"
}
