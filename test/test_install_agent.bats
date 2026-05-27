#!/usr/bin/env bats
# Tests for `bb-api install-agent` subcommand.

load test_helper

setup() {
    TEST_TMP=$(mktemp -d)
    export TEST_TMP
    stub_paths
    # Always operate inside a clean temp dir so cmd_install_agent's $PWD
    # writes don't leak into the real project tree.
    cd "$TEST_TMP" || exit 1
}

teardown() {
    stub_paths_teardown
    rm -rf "$TEST_TMP"
}

# Run bb-api with auth bypassed (install-agent doesn't need it, but the
# top-level guard's case-statement short-circuit is exercised end-to-end here).
_run_bb_api() {
    BB_API_EMAIL="" BB_API_TOKEN="" \
        run "${BATS_TEST_DIRNAME}/../bb-api" "$@"
}

# --- flag parsing ---

@test "install-agent: --help exits 0 and prints synopsis" {
    _run_bb_api install-agent --help
    [ "$status" -eq 0 ]
    contains "$output" "*--rule*"
    contains "$output" "*--skill*"
    contains "$output" "*--claudemd*"
    contains "$output" "*--agents*"
    contains "$output" "*BB_API_REF*"
}

@test "install-agent: unknown flag dies" {
    _run_bb_api install-agent --bogus
    [ "$status" -ne 0 ]
    contains "$output" "*Unknown flag*"
}

# --- dry-run paths (no curl invocation) ---

@test "install-agent: --rule --dry-run prints what would happen, no writes" {
    _run_bb_api install-agent --rule --dry-run
    [ "$status" -eq 0 ]
    contains "$output" "*dry-run*"
    contains "$output" "*bb-api-rule.md*"
    [ ! -e "$TEST_TMP/.claude/rules/bb-api-rule.md" ]
}

@test "install-agent: --rule --skill --claudemd --agents --dry-run all four lines, no writes" {
    _run_bb_api install-agent --rule --skill --claudemd --agents --dry-run
    [ "$status" -eq 0 ]
    contains "$output" "*bb-api-rule.md*"
    contains "$output" "*SKILL.md*"
    contains "$output" "*CLAUDE.md*"
    contains "$output" "*AGENTS.md*"
    [ ! -e "$TEST_TMP/.claude" ]
    [ ! -e "$TEST_TMP/CLAUDE.md" ]
    [ ! -e "$TEST_TMP/AGENTS.md" ]
}

# --- live downloads (stubbed curl) ---

@test "install-agent: --rule writes file via curl stub" {
    stub_curl_download "rule body"
    _run_bb_api install-agent --rule
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/.claude/rules/bb-api-rule.md" ]
    grep -q "rule body" "$TEST_TMP/.claude/rules/bb-api-rule.md"
    contains "$(last_curl_call)" "*raw.githubusercontent.com/restarter/bb-api/main/docs/bb-api-rule.md*"
}

@test "install-agent: BB_API_REF pins the ref in the URL" {
    stub_curl_download "pinned body"
    BB_API_REF=v0.1.2 _run_bb_api install-agent --rule
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" "*restarter/bb-api/v0.1.2/docs/bb-api-rule.md*"
}

@test "install-agent: --rule skips when file already exists, no --force" {
    mkdir -p "$TEST_TMP/.claude/rules"
    echo "existing" > "$TEST_TMP/.claude/rules/bb-api-rule.md"
    stub_curl_download "new body"
    _run_bb_api install-agent --rule
    [ "$status" -eq 0 ]
    contains "$output" "*skip*"
    grep -q "existing" "$TEST_TMP/.claude/rules/bb-api-rule.md"
    [ ! -f "$STUB_DIR/.calls" ] || [ ! -s "$STUB_DIR/.calls" ]
}

@test "install-agent: --rule --force overwrites existing file" {
    mkdir -p "$TEST_TMP/.claude/rules"
    echo "existing" > "$TEST_TMP/.claude/rules/bb-api-rule.md"
    stub_curl_download "new body"
    _run_bb_api install-agent --rule --force
    [ "$status" -eq 0 ]
    grep -q "new body" "$TEST_TMP/.claude/rules/bb-api-rule.md"
}

# --- CLAUDE.md / AGENTS.md modes ---

@test "install-agent: --claudemd creates CLAUDE.md when missing" {
    stub_curl_download "## Bitbucket via bb-api
content"
    _run_bb_api install-agent --claudemd
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/CLAUDE.md" ]
    grep -q "Bitbucket via bb-api" "$TEST_TMP/CLAUDE.md"
    contains "$output" "*created*"
}

@test "install-agent: --claudemd appends to existing CLAUDE.md without bb-api section" {
    echo "# My project" > "$TEST_TMP/CLAUDE.md"
    stub_curl_download "## Bitbucket via bb-api
content"
    _run_bb_api install-agent --claudemd
    [ "$status" -eq 0 ]
    grep -q "My project" "$TEST_TMP/CLAUDE.md"
    grep -q "Bitbucket via bb-api" "$TEST_TMP/CLAUDE.md"
    grep -q "^---$" "$TEST_TMP/CLAUDE.md"
    contains "$output" "*appended*"
}

@test "install-agent: --claudemd skips when CLAUDE.md already has bb-api section" {
    printf '# Project\n\n## Bitbucket via bb-api\nold content\n' > "$TEST_TMP/CLAUDE.md"
    stub_curl_download "new content"
    _run_bb_api install-agent --claudemd
    [ "$status" -eq 0 ]
    contains "$output" "*already has*"
    grep -q "old content" "$TEST_TMP/CLAUDE.md"
}

@test "install-agent: --claudemd --force re-appends even when section exists" {
    printf '# Project\n\n## Bitbucket via bb-api\nold content\n' > "$TEST_TMP/CLAUDE.md"
    stub_curl_download "## Bitbucket via bb-api
new content"
    _run_bb_api install-agent --claudemd --force
    [ "$status" -eq 0 ]
    contains "$output" "*appended*"
    [ "$(grep -c 'Bitbucket via bb-api' "$TEST_TMP/CLAUDE.md")" = "2" ]
}

@test "install-agent: --agents writes AGENTS.md (parallel to claudemd)" {
    stub_curl_download "## Bitbucket via bb-api
agents content"
    _run_bb_api install-agent --agents
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/AGENTS.md" ]
    grep -q "agents content" "$TEST_TMP/AGENTS.md"
    [ ! -f "$TEST_TMP/CLAUDE.md" ]
}

# --- combined flags (real-world "all four at once") ---

@test "install-agent: --rule --skill --claudemd --agents writes all four in one run" {
    stub_curl_download "## Bitbucket via bb-api
combined content"
    _run_bb_api install-agent --rule --skill --claudemd --agents
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/.claude/rules/bb-api-rule.md" ]
    [ -f "$TEST_TMP/.claude/skills/bb-api/SKILL.md" ]
    [ -f "$TEST_TMP/CLAUDE.md" ]
    [ -f "$TEST_TMP/AGENTS.md" ]
    grep -q "combined content" "$TEST_TMP/CLAUDE.md"
    grep -q "combined content" "$TEST_TMP/AGENTS.md"
}

# --- top-level guard regression (auth/repo resolution refactor) ---
#
# Task 3.3 split the top-level guard into two branches: short-circuit (no auth,
# no repo resolution) for `install-agent`/`help`, full resolution for everything
# else. These two tests pin both branches so a future tweak can't silently
# break either path.

@test "guard: 'bb-api help' runs without BB_API_EMAIL/BB_API_TOKEN" {
    BB_API_EMAIL="" BB_API_TOKEN="" BB_API_WORKSPACE="" BB_API_REPO="" \
        run "${BATS_TEST_DIRNAME}/../bb-api" help
    [ "$status" -eq 0 ]
    contains "$output" "*install-agent*"
}

@test "guard: 'bb-api pr list' takes the full guard path (auth/repo resolution)" {
    # Run from an isolated copy so the project's own .env doesn't get sourced
    # (which would mask the empty-credential test by populating BB_API_EMAIL).
    cp "${BATS_TEST_DIRNAME}/../bb-api" "$TEST_TMP/bb-api"
    chmod +x "$TEST_TMP/bb-api"
    BB_API_EMAIL="" BB_API_TOKEN="" BB_API_WORKSPACE="" BB_API_REPO="" \
        run "$TEST_TMP/bb-api" pr list
    [ "$status" -ne 0 ]
    contains "$output" "*BB_API_EMAIL*"
}
