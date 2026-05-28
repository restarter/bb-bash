#!/usr/bin/env bats
# Tests for `bbb install-agent` subcommand.

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

# Run bbb with auth bypassed (install-agent doesn't need it, but the
# top-level guard's case-statement short-circuit is exercised end-to-end here).
_run_bbb() {
    BB_BASH_EMAIL="" BB_BASH_TOKEN="" \
        run "${BATS_TEST_DIRNAME}/../bbb" "$@"
}

# --- flag parsing ---

@test "install-agent: --help exits 0 and prints synopsis" {
    _run_bbb install-agent --help
    [ "$status" -eq 0 ]
    contains "$output" "*--rule*"
    contains "$output" "*--skill*"
    contains "$output" "*--claude*"
    contains "$output" "*--agents*"
    contains "$output" "*BB_BASH_REF*"
}

@test "install-agent: unknown flag dies" {
    _run_bbb install-agent --bogus
    [ "$status" -ne 0 ]
    contains "$output" "*Unknown flag*"
}

# --- dry-run paths (no curl invocation) ---

@test "install-agent: --rule --dry-run prints what would happen, no writes" {
    _run_bbb install-agent --rule --dry-run
    [ "$status" -eq 0 ]
    contains "$output" "*dry-run*"
    contains "$output" "*bb-bash-rule.md*"
    [ ! -e "$TEST_TMP/.claude/rules/bb-bash-rule.md" ]
}

@test "install-agent: --rule --skill --claude --agents --dry-run all four lines, no writes" {
    _run_bbb install-agent --rule --skill --claude --agents --dry-run
    [ "$status" -eq 0 ]
    contains "$output" "*bb-bash-rule.md*"
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
    _run_bbb install-agent --rule
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/.claude/rules/bb-bash-rule.md" ]
    grep -q "rule body" "$TEST_TMP/.claude/rules/bb-bash-rule.md"
    contains "$(last_curl_call)" "*raw.githubusercontent.com/restarter/bb-bash/main/docs/bb-bash-rule.md*"
}

@test "install-agent: BB_BASH_REF pins the ref in the URL" {
    stub_curl_download "pinned body"
    BB_BASH_REF=v0.1.2 _run_bbb install-agent --rule
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" "*restarter/bb-bash/v0.1.2/docs/bb-bash-rule.md*"
}

@test "install-agent: --rule skips when file already exists, no --force" {
    mkdir -p "$TEST_TMP/.claude/rules"
    echo "existing" > "$TEST_TMP/.claude/rules/bb-bash-rule.md"
    stub_curl_download "new body"
    _run_bbb install-agent --rule
    [ "$status" -eq 0 ]
    contains "$output" "*skip*"
    grep -q "existing" "$TEST_TMP/.claude/rules/bb-bash-rule.md"
    [ ! -f "$STUB_DIR/.calls" ] || [ ! -s "$STUB_DIR/.calls" ]
}

@test "install-agent: --rule --force overwrites existing file" {
    mkdir -p "$TEST_TMP/.claude/rules"
    echo "existing" > "$TEST_TMP/.claude/rules/bb-bash-rule.md"
    stub_curl_download "new body"
    _run_bbb install-agent --rule --force
    [ "$status" -eq 0 ]
    grep -q "new body" "$TEST_TMP/.claude/rules/bb-bash-rule.md"
}

# --- CLAUDE.md / AGENTS.md modes ---

@test "install-agent: --claude creates CLAUDE.md when missing" {
    stub_curl_download "## Bitbucket via bb-bash
content"
    _run_bbb install-agent --claude
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/CLAUDE.md" ]
    grep -q "Bitbucket via bb-bash" "$TEST_TMP/CLAUDE.md"
    contains "$output" "*created*"
}

@test "install-agent: --claude appends to existing CLAUDE.md without bbb section" {
    echo "# My project" > "$TEST_TMP/CLAUDE.md"
    stub_curl_download "## Bitbucket via bb-bash
content"
    _run_bbb install-agent --claude
    [ "$status" -eq 0 ]
    grep -q "My project" "$TEST_TMP/CLAUDE.md"
    grep -q "Bitbucket via bb-bash" "$TEST_TMP/CLAUDE.md"
    grep -q "^---$" "$TEST_TMP/CLAUDE.md"
    contains "$output" "*appended*"
}

@test "install-agent: --claude skips when CLAUDE.md already has bbb section" {
    printf '# Project\n\n## Bitbucket via bb-bash\nold content\n' > "$TEST_TMP/CLAUDE.md"
    stub_curl_download "new content"
    _run_bbb install-agent --claude
    [ "$status" -eq 0 ]
    contains "$output" "*already has*"
    grep -q "old content" "$TEST_TMP/CLAUDE.md"
}

@test "install-agent: --claude --force re-appends even when section exists" {
    printf '# Project\n\n## Bitbucket via bb-bash\nold content\n' > "$TEST_TMP/CLAUDE.md"
    stub_curl_download "## Bitbucket via bb-bash
new content"
    _run_bbb install-agent --claude --force
    [ "$status" -eq 0 ]
    contains "$output" "*appended*"
    [ "$(grep -c 'Bitbucket via bb-bash' "$TEST_TMP/CLAUDE.md")" = "2" ]
}

@test "install-agent: --agents writes AGENTS.md (parallel to --claude)" {
    stub_curl_download "## Bitbucket via bb-bash
agents content"
    _run_bbb install-agent --agents
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/AGENTS.md" ]
    grep -q "agents content" "$TEST_TMP/AGENTS.md"
    [ ! -f "$TEST_TMP/CLAUDE.md" ]
}

# --- combined flags (real-world "all four at once") ---

@test "install-agent: --rule --skill --claude --agents writes all four in one run" {
    stub_curl_download "## Bitbucket via bb-bash
combined content"
    _run_bbb install-agent --rule --skill --claude --agents
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/.claude/rules/bb-bash-rule.md" ]
    [ -f "$TEST_TMP/.claude/skills/bb-bash/SKILL.md" ]
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

@test "guard: 'bbb help' runs without BB_BASH_EMAIL/BB_BASH_TOKEN" {
    BB_BASH_EMAIL="" BB_BASH_TOKEN="" BB_BASH_WORKSPACE="" BB_BASH_REPO="" \
        run "${BATS_TEST_DIRNAME}/../bbb" help
    [ "$status" -eq 0 ]
    contains "$output" "*install-agent*"
}

@test "guard: 'bbb pr list' takes the full guard path (auth/repo resolution)" {
    # Run from an isolated copy so the project's own .env doesn't get sourced
    # (which would mask the empty-credential test by populating BB_BASH_EMAIL).
    cp "${BATS_TEST_DIRNAME}/../bbb" "$TEST_TMP/bbb"
    chmod +x "$TEST_TMP/bbb"
    BB_BASH_EMAIL="" BB_BASH_TOKEN="" BB_BASH_WORKSPACE="" BB_BASH_REPO="" \
        run "$TEST_TMP/bbb" pr list
    [ "$status" -ne 0 ]
    contains "$output" "*BB_BASH_EMAIL*"
}
