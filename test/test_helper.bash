# Shared bats helpers. Uses PATH-shadowed stub scripts (more portable
# across bash versions than `export -f` function overrides).
#
# The stub-script-writing helpers below use single-quoted printf strings
# to keep ${} literals in the WRITTEN file rather than expanding them in
# the writer. Each such helper carries its own SC2016 disable so the
# linter stays useful for the rest of the file.

# Locate script path
export BB_BASH_ROOT="${BB_BASH_ROOT:-$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)}"
export BB_BASH_SCRIPT="${BB_BASH_SCRIPT:-${BB_BASH_ROOT}/bbb}"

# bbb_command_surface — the user-facing command surface, one entry per line
# ("pr show", "pipeline log", "raw-put"), parsed out of the router in bbb.
#
# PARSED, never hard-coded. A literal list here would be a fourth copy of the
# command surface for someone to forget — which is the exact failure the
# artifact-drift tests exist to catch.
#
# Parsed from the file rather than enumerated from a sourced shell because the
# router is a `case` inside main(): sourcing bbb gives you the functions, not
# the dispatch table.
#
# Depends on the router's indentation — top-level arms at 8 spaces, nested
# subcommand arms at 16. If that ever changes this quietly returns a short list
# and the drift tests pass for the wrong reason, so test_agent_artifacts.bats
# pins both the count and a couple of known entries.
#
# SC2016: the `$` in the sed addresses is sed's own literal, matching `"$cmd"`
# in the router text — single quotes are required so bash leaves it alone.
# shellcheck disable=SC2016
# The arm classes accept `|` so an alternation arm (`rc|request-changes)`, the
# first shape anyone reaches for when adding an alias, and already idiomatic at
# bbb:499 / :1287 / :1527) is matched and then split into its separate commands.
# A `)`-only class silently skipped such arms entirely — the commands never
# entered the surface and the drift tests passed while covering nothing.
bbb_command_surface() {
    local src="${1:-$BB_BASH_SCRIPT}"
    # Top-level verbs. `pr` and `pipeline` are group prefixes, not commands —
    # their subcommands are enumerated below instead.
    sed -n '/^    case "\$cmd" in/,/^    esac/p' "$src" \
        | grep -oE '^        [a-z][a-z|-]*\)' | tr -d ' )' | tr '|' '\n' \
        | grep -vE '^(pr|pipeline)$'
    sed -n '/case "\$subcmd" in/,/esac/p' "$src" \
        | grep -oE '^ +[a-z][a-z|-]*\)' | tr -d ' )' | tr '|' '\n' | sed 's/^/pr /'
    sed -n '/case "\$psubcmd" in/,/esac/p' "$src" \
        | grep -oE '^ +[a-z][a-z|-]*\)' | tr -d ' )' | tr '|' '\n' | sed 's/^/pipeline /'
}

# bbb_router_arm_count — how many command NAMES the router declares, counted at
# ANY nesting depth (`*)` excluded, alternation arms split like the surface does).
#
# The independence that matters is the depth rule, not the splitting: this scans
# every indentation level, while bbb_command_surface only scans the levels it
# knows about. So arms the surface cannot reach still get counted here.
#
# The accounting invariant it feeds — surface == arms - groups — closes the CLASS
# of parser bug rather than one instance. Two escapes passed silently before it
# existed: an alternation arm the surface regex did not match, and a third command
# group whose nested `case` the surface does not know about. Either now shows up
# as a count mismatch instead of as quiet under-coverage.
# shellcheck disable=SC2016
bbb_router_arm_count() {
    local src="${1:-$BB_BASH_SCRIPT}"
    sed -n '/^    case "\$cmd" in/,/^    esac/p' "$src" \
        | grep -oE '^ +[a-z][a-z|-]*\)' | tr -d ' )' | tr '|' '\n' | grep -c .
}

# bbb_router_group_count — nested `case` blocks inside the router, i.e. command
# GROUPS (`pr`, `pipeline`). Their top-level arm is a prefix, not a command, so
# each one costs the surface exactly one entry against the arm count.
#
# The 8-space floor excludes the router's own `case "$cmd" in`, which sits at 4
# and would otherwise be counted as a group and skew the invariant by one.
# shellcheck disable=SC2016
bbb_router_group_count() {
    local src="${1:-$BB_BASH_SCRIPT}"
    sed -n '/^    case "\$cmd" in/,/^    esac/p' "$src" \
        | grep -cE '^ {8,}case "\$[a-z]+" in'
}

# load_bbb: source bbb (function definitions only — the top-level
# imperative block is BASH_SOURCE-guarded so sourcing skips it).
# Then set WORKSPACE/REPO/BASE_URL/AUTH manually for test isolation.
load_bbb() {
    # Force test env values (do not inherit caller's real credentials!)
    export BB_BASH_EMAIL="test@example.com"
    export BB_BASH_TOKEN="test-token"
    export BB_BASH_BATCH_DELAY="0"
    unset BB_BASH_REMOTE BB_BASH_WORKSPACE BB_BASH_REPO BB_BASH_PIPELINE_SCAN

    # shellcheck source=/dev/null
    source "$BB_BASH_SCRIPT"

    # Set globals that the real top-level block would have set.
    # (Used by sourced bbb helpers — disable SC2034 since lint can't
    # follow sourcing across files.)
    # shellcheck disable=SC2034
    WORKSPACE="testws"
    # shellcheck disable=SC2034
    REPO="testrepo"
    # shellcheck disable=SC2034
    BASE_URL="https://api.bitbucket.org/2.0/repositories/${WORKSPACE}/${REPO}"
    # shellcheck disable=SC2034
    AUTH="${BB_BASH_EMAIL}:${BB_BASH_TOKEN}"
}

# stub_paths: prepare a temp dir on PATH where we drop fake commands
# (curl, git, uname). Call once in setup(); teardown removes it.
stub_paths() {
    STUB_DIR=$(mktemp -d)
    export STUB_DIR
    export PATH="$STUB_DIR:$PATH"
    : > "$STUB_DIR/.calls"  # call log
}

stub_paths_teardown() {
    [[ -n "${STUB_DIR:-}" && -d "$STUB_DIR" ]] && rm -rf "$STUB_DIR"
}

# stub_curl <body> [http_code] — single-shot stub matching real curl's
# output format ('body' followed by '\n<code>' on one line)
stub_curl() {
    local body="$1" code="${2:-200}"
    cat >"$STUB_DIR/curl" <<EOF
#!/usr/bin/env bash
# Log args for assertion
printf '%s\\n' "\$*" >> "$STUB_DIR/.calls"
# Echo body, then newline, then code (matches curl -w '\\n%{http_code}')
printf '%s\\n%s' $(printf %q "$body") $(printf %q "$code")
EOF
    chmod +x "$STUB_DIR/curl"
}

# stub_curl_seq <code1> <body1> <code2> <body2> ... — queue stub for
# commands that make multiple API calls in sequence.
# Paired-args form (previously '<body>|||<code>' — switched to avoid
# silent body truncation when bodies legitimately contain '|||').
# Fails loudly on queue exhaustion (exit 99 instead of empty response).
stub_curl_seq() {
    [[ $(($# % 2)) -eq 0 ]] || {
        echo "stub_curl_seq: expected even number of args (code body pairs), got $#" >&2
        return 1
    }
    local i=0
    while [[ $# -gt 0 ]]; do
        printf '%s' "$2" > "$STUB_DIR/.curl_seq.$i.body"
        printf '%s' "$1" > "$STUB_DIR/.curl_seq.$i.code"
        i=$((i + 1))
        shift 2
    done
    printf '0\n' > "$STUB_DIR/.curl_seq.idx"

    cat >"$STUB_DIR/curl" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$STUB_DIR/.calls"
idx=\$(cat "$STUB_DIR/.curl_seq.idx")
if [[ ! -f "$STUB_DIR/.curl_seq.\${idx}.body" ]]; then
    printf 'stub_curl_seq: queue exhausted at call %s\\n' "\$((idx+1))" >&2
    exit 99
fi
body=\$(cat "$STUB_DIR/.curl_seq.\${idx}.body")
code=\$(cat "$STUB_DIR/.curl_seq.\${idx}.code")
echo \$((idx + 1)) > "$STUB_DIR/.curl_seq.idx"
printf '%s\\n%s' "\$body" "\$code"
EOF
    chmod +x "$STUB_DIR/curl"
}

# stub_curl_code <http_code> — stub for api_delete-style calls, i.e.
# `curl -s -o /dev/null -w "%{http_code}"`, where real curl discards the body
# and prints ONLY the status code. stub_curl cannot express this: it ignores
# -o and always prints 'body\n<code>', so the caller would capture a leading
# newline plus the body and every code comparison would fail.
stub_curl_code() {
    local code="${1:-204}"
    cat >"$STUB_DIR/curl" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$STUB_DIR/.calls"
printf '%s' $(printf %q "$code")
EOF
    chmod +x "$STUB_DIR/curl"
}

# stub_curl_code_seq <code1> <code2> ... — queued variant of stub_curl_code for
# batch DELETE commands. Fails loudly on queue exhaustion (exit 99), like
# stub_curl_seq.
stub_curl_code_seq() {
    local i=0 c
    for c in "$@"; do
        printf '%s' "$c" > "$STUB_DIR/.curl_code_seq.$i"
        i=$((i + 1))
    done
    printf '0\n' > "$STUB_DIR/.curl_code_seq.idx"

    cat >"$STUB_DIR/curl" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$STUB_DIR/.calls"
idx=\$(cat "$STUB_DIR/.curl_code_seq.idx")
if [[ ! -f "$STUB_DIR/.curl_code_seq.\${idx}" ]]; then
    printf 'stub_curl_code_seq: queue exhausted at call %s\\n' "\$((idx+1))" >&2
    exit 99
fi
code=\$(cat "$STUB_DIR/.curl_code_seq.\${idx}")
echo \$((idx + 1)) > "$STUB_DIR/.curl_code_seq.idx"
printf '%s' "\$code"
EOF
    chmod +x "$STUB_DIR/curl"
}

# stub_curl_download <body> [http_code]
# Stub for install-agent style curl: 'curl ... -o <file>'. Writes <body> to
# the file given via -o; exits non-zero on http_code != 200.
# Logs the full arg list to $STUB_DIR/.calls (like stub_curl) for assertions.
stub_curl_download() {
    local body="$1" code="${2:-200}"
    cat >"$STUB_DIR/curl" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$STUB_DIR/.calls"
out=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -o) out="\$2"; shift 2 ;;
        *)  shift ;;
    esac
done
if [[ -n "\$out" ]]; then
    printf '%s' $(printf %q "$body") > "\$out"
fi
case "$code" in
    200) exit 0 ;;
    *)   exit 22 ;;
esac
EOF
    chmod +x "$STUB_DIR/curl"
}

# stub_curl_fail [exit_code] — stub for a TRANSPORT failure: prints nothing and
# exits non-zero, the way real curl behaves on DNS (6), connect (7) or TLS (35)
# errors. Distinct from an HTTP error: curl exits 0 for a 4xx/5xx unless -f is
# given, so stub_curl/stub_curl_seq cannot express this case at all.
stub_curl_fail() {
    local code="${1:-6}"
    cat >"$STUB_DIR/curl" <<EOF
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$STUB_DIR/.calls"
exit $code
EOF
    chmod +x "$STUB_DIR/curl"
}

# stub_git: install a git wrapper that returns canned remote URLs.
# Usage: stub_git origin=https://bitbucket.org/ws/repo.git bb=git@bitbucket.org:other/x.git
stub_git() {
    local pair name url names=""
    # shellcheck disable=SC2016
    {
        printf '#!/usr/bin/env bash\n'
        printf 'case "$1 ${2:-}" in\n'
        printf '    "remote get-url")\n'
        printf '        shift 2\n'
        printf '        [[ "${1:-}" == "--" ]] && shift\n'
        printf '        case "${1:-}" in\n'
        for pair in "$@"; do
            name="${pair%%=*}"
            url="${pair#*=}"
            printf '            %s) printf "%%s\\n" %s ;;\n' "$(printf '%q' "$name")" "$(printf '%q' "$url")"
            names="${names:+$names }$name"
        done
        printf '            *) exit 1 ;;\n'
        printf '        esac\n'
        printf '        ;;\n'
        printf '    "remote ")\n'
        printf '        printf "%%s\\n" %s\n' "$names"
        printf '        ;;\n'
        printf '    *) exit 1 ;;\n'
        printf 'esac\n'
    } > "$STUB_DIR/git"
    chmod +x "$STUB_DIR/git"
}

# stub_uname <output>
stub_uname() {
    cat >"$STUB_DIR/uname" <<EOF
#!/usr/bin/env bash
printf '%s\\n' $(printf %q "$1")
EOF
    chmod +x "$STUB_DIR/uname"
}

# last_curl_call: get the most recent curl invocation args
last_curl_call() {
    tail -n1 "$STUB_DIR/.calls" 2>/dev/null
}

# nth_curl_call N: get the args of the Nth curl invocation (1-indexed).
# Use for multi-call commands like pr checks (PR detail / statuses / pipelines).
nth_curl_call() {
    sed -n "${1}p" "$STUB_DIR/.calls" 2>/dev/null
}

# Assertion helpers. Use these INSTEAD of bare `[[ "$x" == *pat* ]]` in tests.
# Bash quirk: `[[ ]]` is a keyword, not a simple command, so `set -e` does NOT
# exit on false. Bare `[[ ]]` assertions in bats tests silently pass when they
# should fail. These helpers use `case` (a compound but exit-triggering form)
# and `return 1` to force proper failure under set -e.
#
# GLOB, NOT SUBSTRING. The pattern is a shell glob, so `[` and `]` open a
# character class: '*[fail]*' means "any one of f/a/i/l", NOT the literal
# "[fail]". Escape them — '*\[fail\]*' — when matching bracketed output such as
# the "[pass]" / "[fail]" state markers. This bites asymmetrically: `contains`
# with an unescaped class fails loudly, but `not_contains` passes silently and
# the assertion becomes decorative.
contains() {
    local actual="$1" pattern="$2"
    # SC2254: $pattern intentionally unquoted (we want glob expansion in case).
    # shellcheck disable=SC2254
    case "$actual" in
        $pattern) return 0 ;;
        *) echo "contains: actual does not match pattern" >&2; echo "  pattern: $pattern" >&2; echo "  actual:  $actual" >&2; return 1 ;;
    esac
}

not_contains() {
    local actual="$1" pattern="$2"
    # shellcheck disable=SC2254
    case "$actual" in
        $pattern) echo "not_contains: actual unexpectedly matches pattern" >&2; echo "  pattern: $pattern" >&2; echo "  actual:  $actual" >&2; return 1 ;;
        *) return 0 ;;
    esac
}
