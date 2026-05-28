# Shared bats helpers. Uses PATH-shadowed stub scripts (more portable
# across bash versions than `export -f` function overrides).
#
# The stub-script-writing helpers below use single-quoted printf strings
# to keep ${} literals in the WRITTEN file rather than expanding them in
# the writer. Each such helper carries its own SC2016 disable so the
# linter stays useful for the rest of the file.

# Locate script path
export BB_BASH_SCRIPT="${BB_BASH_SCRIPT:-$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/bbb}"

# load_bbb: source bbb (function definitions only — the top-level
# imperative block is BASH_SOURCE-guarded so sourcing skips it).
# Then set WORKSPACE/REPO/BASE_URL/AUTH manually for test isolation.
load_bbb() {
    # Force test env values (do not inherit caller's real credentials!)
    export BB_BASH_EMAIL="test@example.com"
    export BB_BASH_TOKEN="test-token"
    export BB_BASH_BATCH_DELAY="0"
    unset BB_BASH_REMOTE BB_BASH_WORKSPACE BB_BASH_REPO

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
