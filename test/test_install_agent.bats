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

_file_mode() {
    local path="$1" mode
    if mode=$(stat -f '%Lp' "$path" 2>/dev/null); then
        printf '%s\n' "$mode"
    else
        stat -c '%a' "$path"
    fi
}

# --- flag parsing ---

@test "install-agent: --help exits 0 and prints synopsis" {
    _run_bbb install-agent --help
    [ "$status" -eq 0 ]
    contains "$output" "*--rule*"
    contains "$output" "*--skill*"
    contains "$output" "*--claude*"
    contains "$output" "*--agents*"
    contains "$output" "*--claude-code*"
    contains "$output" "*--codex*"
    contains "$output" "*--codex-skill*"
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
    contains "$(last_curl_call)" "*raw.githubusercontent.com/restarter/bb-bash/main/docs/agents/bb-bash-rule.md*"
}

@test "install-agent: BB_BASH_REF pins the ref in the URL" {
    stub_curl_download "pinned body"
    BB_BASH_REF=v0.1.2 _run_bbb install-agent --rule
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" "*restarter/bb-bash/v0.1.2/docs/agents/bb-bash-rule.md*"
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

@test "install-agent: failed --force download preserves existing artifact" {
    mkdir -p "$TEST_TMP/.claude/rules"
    printf 'existing\n' > "$TEST_TMP/.claude/rules/bb-bash-rule.md"
    stub_curl_fail 6
    _run_bbb install-agent --rule --force
    [ "$status" -ne 0 ]
    grep -q '^existing$' "$TEST_TMP/.claude/rules/bb-bash-rule.md"
}

@test "install-agent: empty successful download preserves existing artifact" {
    mkdir -p "$TEST_TMP/.claude/rules"
    printf 'existing\n' > "$TEST_TMP/.claude/rules/bb-bash-rule.md"
    stub_curl_download ""
    _run_bbb install-agent --rule --force
    [ "$status" -ne 0 ]
    contains "$output" "*empty agent artifact*"
    grep -q '^existing$' "$TEST_TMP/.claude/rules/bb-bash-rule.md"
}

@test "install-agent: fresh artifacts are readable and forced updates preserve mode" {
    stub_curl_download "first"
    _run_bbb install-agent --rule
    [ "$status" -eq 0 ]
    [ "$(_file_mode "$TEST_TMP/.claude/rules/bb-bash-rule.md")" = "644" ]

    chmod 640 "$TEST_TMP/.claude/rules/bb-bash-rule.md"
    stub_curl_download "second"
    _run_bbb install-agent --rule --force
    [ "$status" -eq 0 ]
    [ "$(_file_mode "$TEST_TMP/.claude/rules/bb-bash-rule.md")" = "640" ]
}

@test "install-agent: refuses a symlinked artifact without replacing it" {
    mkdir -p "$TEST_TMP/.claude/rules"
    printf 'shared\n' > "$TEST_TMP/shared-rule.md"
    ln -s "$TEST_TMP/shared-rule.md" "$TEST_TMP/.claude/rules/bb-bash-rule.md"
    stub_curl_download "replacement"
    _run_bbb install-agent --rule --force
    [ "$status" -ne 0 ]
    contains "$output" "*refusing to replace symlink*"
    [ -L "$TEST_TMP/.claude/rules/bb-bash-rule.md" ]
    grep -q '^shared$' "$TEST_TMP/shared-rule.md"
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

@test "install-agent: --claude preserves existing CLAUDE.md content and adds markers" {
    echo "# My project" > "$TEST_TMP/CLAUDE.md"
    stub_curl_download "## Bitbucket via bb-bash
content"
    _run_bbb install-agent --claude
    [ "$status" -eq 0 ]
    grep -q "My project" "$TEST_TMP/CLAUDE.md"
    grep -q "Bitbucket via bb-bash" "$TEST_TMP/CLAUDE.md"
    grep -q '<!-- bb-bash:start -->' "$TEST_TMP/CLAUDE.md"
    grep -q '<!-- bb-bash:end -->' "$TEST_TMP/CLAUDE.md"
    contains "$output" "*updated*"
}

@test "install-agent: legacy unmarked CLAUDE.md section skips with migration message" {
    printf '# Project\n\n## Bitbucket via bb-bash\nold content\n' > "$TEST_TMP/CLAUDE.md"
    stub_curl_download "new content"
    _run_bbb install-agent --claude
    [ "$status" -eq 0 ]
    contains "$output" "*legacy unmarked section*"
    grep -q "old content" "$TEST_TMP/CLAUDE.md"
}

@test "install-agent: --claude --force migrates legacy trailing section without duplication" {
    printf '# Project\n\n## Bitbucket via bb-bash\nold content\n' > "$TEST_TMP/CLAUDE.md"
    stub_curl_download "## Bitbucket via bb-bash
new content"
    _run_bbb install-agent --claude --force
    [ "$status" -eq 0 ]
    contains "$output" "*updated*"
    [ "$(grep -c '<!-- bb-bash:start -->' "$TEST_TMP/CLAUDE.md")" = "1" ]
    [ "$(grep -c 'Bitbucket via bb-bash' "$TEST_TMP/CLAUDE.md")" = "1" ]
    run grep -q 'old content' "$TEST_TMP/CLAUDE.md"
    [ "$status" -ne 0 ]
}

@test "install-agent: --agents writes AGENTS.md (parallel to --claude)" {
    stub_curl_download "## Bitbucket via bb-bash
agents content"
    umask 077
    _run_bbb install-agent --agents
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/AGENTS.md" ]
    grep -q "agents content" "$TEST_TMP/AGENTS.md"
    [ "$(_file_mode "$TEST_TMP/AGENTS.md")" = "644" ]
    [ ! -f "$TEST_TMP/CLAUDE.md" ]
}

@test "install-agent: refuses a symlinked AGENTS.md without replacing it" {
    printf '# Shared instructions\n' > "$TEST_TMP/shared.md"
    ln -s "$TEST_TMP/shared.md" "$TEST_TMP/AGENTS.md"
    stub_curl_download "new content"
    _run_bbb install-agent --agents
    [ "$status" -ne 0 ]
    contains "$output" "*refusing to replace symlink*"
    [ -L "$TEST_TMP/AGENTS.md" ]
    grep -q '^# Shared instructions$' "$TEST_TMP/shared.md"
}

@test "install-agent: managed update preserves destination mode" {
    printf '# Existing\n' > "$TEST_TMP/AGENTS.md"
    chmod 640 "$TEST_TMP/AGENTS.md"
    stub_curl_download "new content"
    _run_bbb install-agent --agents
    [ "$status" -eq 0 ]
    [ "$(_file_mode "$TEST_TMP/AGENTS.md")" = "640" ]
}

@test "install-agent: empty snippet download preserves managed destination" {
    printf '# Existing\n' > "$TEST_TMP/AGENTS.md"
    cp -f "$TEST_TMP/AGENTS.md" "$TEST_TMP/before"
    stub_curl_download ""
    _run_bbb install-agent --agents
    [ "$status" -ne 0 ]
    contains "$output" "*empty agent artifact*"
    cmp "$TEST_TMP/before" "$TEST_TMP/AGENTS.md"
}

# --- combined flags (real-world "all four at once") ---

@test "install-agent: --rule --skill --claude --agents writes all four in one run" {
    stub_curl_download "## Bitbucket via bb-bash
combined content"
    _run_bbb install-agent --rule --skill --claude --agents
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/.claude/rules/bb-bash-rule.md" ]
    [ -f "$TEST_TMP/.claude/skills/bbb/SKILL.md" ]
    [ -f "$TEST_TMP/CLAUDE.md" ]
    [ -f "$TEST_TMP/AGENTS.md" ]
    grep -q "combined content" "$TEST_TMP/CLAUDE.md"
    grep -q "combined content" "$TEST_TMP/AGENTS.md"
}

# --- --global flag (bb-bash-6ru) ---
#
# Global install writes to $HOME/.claude/ instead of $PWD/.claude/. The four
# tests below pin: the two validation gates (alone, with --agents) and the
# three working destinations (--rule, --skill, --claude). HOME is forced to
# $TEST_TMP/h so no test touches the real ~/.claude.

@test "install-agent: --global alone (no selector) dies with explainer" {
    HOME="$TEST_TMP/h" _run_bbb install-agent --global --dry-run
    [ "$status" -ne 0 ]
    contains "$output" "*--global requires*"
}

@test "install-agent: legacy --agents --global targets Codex AGENTS.md" {
    HOME="$TEST_TMP/h" _run_bbb install-agent --agents --global --dry-run
    [ "$status" -eq 0 ]
    contains "$output" "*$TEST_TMP/h/.codex/AGENTS.md*"
}

@test "install-agent: --rule --global writes to \$HOME/.claude/rules/" {
    stub_curl_download "rule body" 200
    HOME="$TEST_TMP/h" _run_bbb install-agent --rule --global
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/h/.claude/rules/bb-bash-rule.md" ]
    grep -q "rule body" "$TEST_TMP/h/.claude/rules/bb-bash-rule.md"
    # Project-level path should NOT have been written
    [ ! -e "$TEST_TMP/.claude/rules/bb-bash-rule.md" ]
}

@test "install-agent: --skill --global writes to \$HOME/.claude/skills/bbb/" {
    stub_curl_download "skill body" 200
    HOME="$TEST_TMP/h" _run_bbb install-agent --skill --global
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/h/.claude/skills/bbb/SKILL.md" ]
    grep -q "skill body" "$TEST_TMP/h/.claude/skills/bbb/SKILL.md"
    [ ! -e "$TEST_TMP/.claude/skills/bbb/SKILL.md" ]
}

@test "install-agent: --claude --global appends to \$HOME/.claude/CLAUDE.md" {
    stub_curl_download "## Bitbucket via bb-bash
snippet body" 200
    HOME="$TEST_TMP/h" _run_bbb install-agent --claude --global
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/h/.claude/CLAUDE.md" ]
    grep -q "Bitbucket via bb-bash" "$TEST_TMP/h/.claude/CLAUDE.md"
    # Project-level CLAUDE.md should NOT have been touched
    [ ! -e "$TEST_TMP/CLAUDE.md" ]
}

# --- native Claude Code and Codex presets ---

@test "install-agent: --claude-code installs project rule and lazy skill" {
    stub_curl_download "canonical artifact"
    _run_bbb install-agent --claude-code
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/.claude/rules/bb-bash-rule.md" ]
    [ -f "$TEST_TMP/.claude/skills/bbb/SKILL.md" ]
}

@test "install-agent: --claude-code --global installs user rule and lazy skill" {
    stub_curl_download "canonical artifact"
    HOME="$TEST_TMP/home with spaces" _run_bbb install-agent --claude-code --global
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/home with spaces/.claude/rules/bb-bash-rule.md" ]
    [ -f "$TEST_TMP/home with spaces/.claude/skills/bbb/SKILL.md" ]
}

@test "install-agent: --codex installs project AGENTS section and lazy skill" {
    stub_curl_download "## Bitbucket Cloud via bb-bash
canonical artifact"
    _run_bbb install-agent --codex
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/AGENTS.md" ]
    [ -f "$TEST_TMP/.agents/skills/bbb/SKILL.md" ]
    [ "$(grep -c '<!-- bb-bash:start -->' "$TEST_TMP/AGENTS.md")" = "1" ]
}

@test "install-agent: --codex-skill installs only the project bbb skill" {
    stub_curl_download "canonical artifact"
    _run_bbb install-agent --codex-skill
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/.agents/skills/bbb/SKILL.md" ]
    [ ! -e "$TEST_TMP/AGENTS.md" ]
}

@test "install-agent: --codex-skill --global installs only the HOME bbb skill" {
    stub_curl_download "canonical artifact"
    HOME="$TEST_TMP/home" CODEX_HOME="$TEST_TMP/codex" \
        _run_bbb install-agent --codex-skill --global
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/home/.agents/skills/bbb/SKILL.md" ]
    [ ! -e "$TEST_TMP/codex" ]
}

@test "install-agent: legacy skill path is reported and never deleted" {
    mkdir -p "$TEST_TMP/.agents/skills/bb-bash"
    printf 'legacy skill\n' > "$TEST_TMP/.agents/skills/bb-bash/SKILL.md"
    stub_curl_download "bbb skill"
    _run_bbb install-agent --codex-skill
    [ "$status" -eq 0 ]
    contains "$output" "*migration*legacy skill remains*"
    grep -q '^legacy skill$' "$TEST_TMP/.agents/skills/bb-bash/SKILL.md"
    grep -q '^bbb skill$' "$TEST_TMP/.agents/skills/bbb/SKILL.md"
}

@test "install-agent: --codex --global installs effective AGENTS and HOME skill" {
    stub_curl_download "canonical artifact"
    HOME="$TEST_TMP/home" _run_bbb install-agent --codex --global
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/home/.codex/AGENTS.md" ]
    [ -f "$TEST_TMP/home/.agents/skills/bbb/SKILL.md" ]
    contains "$output" "*$TEST_TMP/home/.codex/AGENTS.md*"
    contains "$output" "*$TEST_TMP/home/.agents/skills/bbb/SKILL.md*"
}

@test "install-agent: custom CODEX_HOME changes global instruction but not skill" {
    stub_curl_download "canonical artifact"
    HOME="$TEST_TMP/home" CODEX_HOME="$TEST_TMP/custom codex" \
        _run_bbb install-agent --codex --global
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/custom codex/AGENTS.md" ]
    [ -f "$TEST_TMP/home/.agents/skills/bbb/SKILL.md" ]
    [ ! -e "$TEST_TMP/custom codex/skills/bbb/SKILL.md" ]
}

@test "install-agent: non-empty AGENTS.override.md takes global precedence" {
    mkdir -p "$TEST_TMP/codex"
    printf '# Keep override\n' > "$TEST_TMP/codex/AGENTS.override.md"
    stub_curl_download "canonical artifact"
    HOME="$TEST_TMP/home" CODEX_HOME="$TEST_TMP/codex" \
        _run_bbb install-agent --codex --global
    [ "$status" -eq 0 ]
    grep -q 'Keep override' "$TEST_TMP/codex/AGENTS.override.md"
    grep -q '<!-- bb-bash:start -->' "$TEST_TMP/codex/AGENTS.override.md"
    [ ! -e "$TEST_TMP/codex/AGENTS.md" ]
}

@test "install-agent: refuses a symlinked global AGENTS.override.md" {
    mkdir -p "$TEST_TMP/codex"
    printf '# Shared override\n' > "$TEST_TMP/shared-override.md"
    ln -s "$TEST_TMP/shared-override.md" "$TEST_TMP/codex/AGENTS.override.md"
    stub_curl_download "canonical artifact"
    HOME="$TEST_TMP/home" CODEX_HOME="$TEST_TMP/codex" \
        _run_bbb install-agent --codex --global
    [ "$status" -ne 0 ]
    contains "$output" "*refusing to replace symlink*"
    [ -L "$TEST_TMP/codex/AGENTS.override.md" ]
    grep -q '^# Shared override$' "$TEST_TMP/shared-override.md"
    [ ! -e "$TEST_TMP/home/.agents/skills/bbb/SKILL.md" ]
}

@test "install-agent: empty AGENTS.override.md falls back to global AGENTS.md" {
    mkdir -p "$TEST_TMP/codex"
    : > "$TEST_TMP/codex/AGENTS.override.md"
    stub_curl_download "canonical artifact"
    HOME="$TEST_TMP/home" CODEX_HOME="$TEST_TMP/codex" \
        _run_bbb install-agent --codex --global
    [ "$status" -eq 0 ]
    [ ! -s "$TEST_TMP/codex/AGENTS.override.md" ]
    [ -f "$TEST_TMP/codex/AGENTS.md" ]
}

@test "install-agent: managed AGENTS section updates in place without duplicates" {
    printf '# Before\n\n<!-- bb-bash:start -->\nold\n<!-- bb-bash:end -->\n\n# After\n' > "$TEST_TMP/AGENTS.md"
    stub_curl_download "new content"
    _run_bbb install-agent --agents
    [ "$status" -eq 0 ]
    grep -q '^# Before$' "$TEST_TMP/AGENTS.md"
    grep -q '^# After$' "$TEST_TMP/AGENTS.md"
    grep -q 'new content' "$TEST_TMP/AGENTS.md"
    run grep -q '^old$' "$TEST_TMP/AGENTS.md"
    [ "$status" -ne 0 ]
    [ "$(grep -c '<!-- bb-bash:start -->' "$TEST_TMP/AGENTS.md")" = "1" ]

    cp -f "$TEST_TMP/AGENTS.md" "$TEST_TMP/after-first-install"
    _run_bbb install-agent --agents
    [ "$status" -eq 0 ]
    [ "$(grep -c '<!-- bb-bash:start -->' "$TEST_TMP/AGENTS.md")" = "1" ]
    cmp "$TEST_TMP/after-first-install" "$TEST_TMP/AGENTS.md"
    contains "$output" "*skipped*current*"
}

@test "install-agent: malformed managed markers fail without changing file" {
    printf '# Keep\n<!-- bb-bash:start -->\nbroken\n' > "$TEST_TMP/AGENTS.md"
    cp -f "$TEST_TMP/AGENTS.md" "$TEST_TMP/before"
    stub_curl_download "new content"
    _run_bbb install-agent --agents --force
    [ "$status" -ne 0 ]
    cmp "$TEST_TMP/before" "$TEST_TMP/AGENTS.md"
}

@test "install-agent: reversed managed markers fail without changing file" {
    printf '# Keep\n<!-- bb-bash:end -->\nbroken\n<!-- bb-bash:start -->\n' > "$TEST_TMP/AGENTS.md"
    cp -f "$TEST_TMP/AGENTS.md" "$TEST_TMP/before"
    stub_curl_download "new content"
    _run_bbb install-agent --agents --force
    [ "$status" -ne 0 ]
    cmp "$TEST_TMP/before" "$TEST_TMP/AGENTS.md"
}

@test "install-agent: --force refuses ambiguous non-trailing legacy section" {
    printf '# Project\n\n## Bitbucket via bb-bash\nold\n\n## Unrelated\nkeep\n' > "$TEST_TMP/AGENTS.md"
    cp -f "$TEST_TMP/AGENTS.md" "$TEST_TMP/before"
    stub_curl_download "new content"
    _run_bbb install-agent --agents --force
    [ "$status" -ne 0 ]
    contains "$output" "*not trailing*"
    cmp "$TEST_TMP/before" "$TEST_TMP/AGENTS.md"
}

@test "install-agent: dry-run predicts failure for ambiguous non-trailing legacy section" {
    printf '# Project\n\n## Bitbucket via bb-bash\nold\n\n## Unrelated\nkeep\n' > "$TEST_TMP/AGENTS.md"
    cp -f "$TEST_TMP/AGENTS.md" "$TEST_TMP/before"
    _run_bbb install-agent --agents --force --dry-run
    [ "$status" -ne 0 ]
    contains "$output" "*live install would require manual migration*"
    cmp "$TEST_TMP/before" "$TEST_TMP/AGENTS.md"
}

@test "install-agent: Codex global dry-run reports both paths and writes nothing" {
    HOME="$TEST_TMP/home" CODEX_HOME="$TEST_TMP/codex" \
        _run_bbb install-agent --codex --global --dry-run
    [ "$status" -eq 0 ]
    contains "$output" "*$TEST_TMP/codex/AGENTS.md*"
    contains "$output" "*$TEST_TMP/home/.agents/skills/bbb/SKILL.md*"
    [ ! -e "$TEST_TMP/codex" ]
    [ ! -e "$TEST_TMP/home" ]
    [ ! -f "$STUB_DIR/.calls" ] || [ ! -s "$STUB_DIR/.calls" ]
}

@test "install-agent: project preset works from a path containing spaces" {
    mkdir -p "$TEST_TMP/project with spaces"
    cd "$TEST_TMP/project with spaces" || exit 1
    stub_curl_download "canonical artifact"
    _run_bbb install-agent --codex
    [ "$status" -eq 0 ]
    [ -f "$TEST_TMP/project with spaces/AGENTS.md" ]
    [ -f "$TEST_TMP/project with spaces/.agents/skills/bbb/SKILL.md" ]
}

@test "install-agent: installed Codex skill exactly matches canonical repository artifact" {
    local repo_root canonical
    repo_root="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    canonical="$(cat "$repo_root/docs/agents/bb-bash-skill/SKILL.md"; printf x)"
    canonical="${canonical%x}"
    stub_curl_download "$canonical"
    _run_bbb install-agent --codex
    [ "$status" -eq 0 ]
    cmp "$repo_root/docs/agents/bb-bash-skill/SKILL.md" \
        "$TEST_TMP/.agents/skills/bbb/SKILL.md"
}

# --- URL→file mapping regression (bb-bash-6ru) ---
#
# Guard against renaming an artifact locally without updating the fetch URL
# in bbb (or vice versa). Runs install-agent --dry-run, parses every emitted
# fetch URL, strips the github-raw prefix, and asserts the resulting relative
# path is a real file in the repo. Self-maintaining: if a new artifact is
# added to install-agent, this test picks it up automatically. Does NOT touch
# GitHub — purely a local-tree consistency check.

@test "install-agent: every fetch URL maps to an existing file in the repo" {
    local repo_root
    repo_root="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
    cd "$TEST_TMP"

    run "$repo_root/bbb" install-agent --rule --skill --claude --agents --dry-run
    [ "$status" -eq 0 ]

    local url rel missing=0
    while IFS= read -r url; do
        [ -z "$url" ] && continue
        rel="${url#https://raw.githubusercontent.com/restarter/bb-bash/main/}"
        if [ ! -f "$repo_root/$rel" ]; then
            echo "MISSING in repo: $rel  (url: $url)" >&2
            missing=$((missing + 1))
        fi
    done < <(printf '%s\n' "$output" | grep -oE 'https://raw\.githubusercontent\.com/[^[:space:]]+' | sort -u)

    [ "$missing" -eq 0 ]
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
