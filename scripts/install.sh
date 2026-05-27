#!/usr/bin/env bash
#
# bb-api installer
# Usage:
#   curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/restarter/bb-api/main/scripts/install.sh | bash
#
# Re-run to update. Never touches .env.
#
# IMPORTANT: must be EXECUTED, never SOURCED for production use (set -e
# would kill the user's shell on errors). Tests source it; the guard at
# the bottom skips _bb_api_install_main() when sourced. Helpers are at
# top level (testable); orchestration lives in the wrapper. Truncation-safe
# either way — see the architecture note in the plan.
#

set -euo pipefail

REPO="restarter/bb-api"
BIN_NAME="bb-api"
# RAW_BASE / API_BASE / CURL_OPTS are introduced in Task 3 when first used by
# fetch_release_json / download_file.

# Colors + styles. Skipped on non-TTY stderr (clean CI output).
if [ -t 2 ]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; CYAN=''; BOLD=''; DIM=''; NC=''
fi

STEP_TOTAL=7   # Checking deps, Fetching release, Detecting paths, Checking existing, Downloading, Installing, Verifying
STEP_CURRENT=0

# --- Logging / step helpers ---

_step_call() {
    STEP_CURRENT=$((STEP_CURRENT + 1))
    echo "" >&2
    printf '%b\n' "${CYAN}[${STEP_CURRENT}/${STEP_TOTAL}]${NC} ${BOLD}$1${NC}" >&2
}

_print_header() {
    printf '%b\n' "
   ${BOLD}bb-api installer${NC}
   ${DIM}https://github.com/${REPO}${NC}
" >&2
}

# Logs to stderr (stdout reserved for future scripted use).
log_info()    { printf '%b\n' "  ${DIM}·${NC} $1" >&2; }
log_success() { printf '%b\n' "  ${GREEN}✓${NC} $1" >&2; }
log_warning() { printf '%b\n' "  ${YELLOW}⚠${NC} $1" >&2; }
log_error()   { printf '%b\n' "  ${RED}✗ Error:${NC} $1" >&2; }
die()         { log_error "$1"; exit 1; }

# --- Dep / path helpers ---

check_deps() {
    command -v curl >/dev/null 2>&1 || die "curl not found. Install curl and retry."
    if ! command -v jq >/dev/null 2>&1; then
        log_warning "jq not found — bb-api needs it at runtime, install with:"
        case "$(uname -s)" in
            Darwin) log_info "    brew install jq" ;;
            Linux)  log_info "    sudo apt install jq  # or: dnf, pacman, ..." ;;
            *)      log_info "    See https://jqlang.github.io/jq/download/" ;;
        esac
    else
        log_success "Dependencies OK (curl, jq)"
    fi
}

# pick_install_dir <preferred> <fallback>: testable; tries $1 if writable
# AND BB_API_USER_ONLY not set, else creates and returns $2.
# No auto-sudo — surprise sudo prompts on `curl | bash` are bad UX.
pick_install_dir() {
    local preferred=$1 fallback=$2
    if [ -z "${BB_API_USER_ONLY:-}" ] && [ -w "$preferred" ] 2>/dev/null; then
        echo "$preferred"
    else
        mkdir -p "$fallback"
        echo "$fallback"
    fi
}

pick_data_dir() {
    local base="${XDG_DATA_HOME:-$HOME/.local/share}"
    echo "$base/bb-api"
}

path_contains() {
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
        *)        return 1 ;;
    esac
}

# _resolve_symlink_chain: portable multi-hop symlink resolution with hop cap.
# Mirrors bb-api's resolve_script_dir so install.sh has the same behavior
# for multi-binary detection.
_resolve_symlink_chain() {
    local target=$1 link hops=0
    while [ -L "$target" ]; do
        hops=$((hops + 1))
        if [ "$hops" -gt 40 ]; then
            printf '%s\n' "$target"  # bail; return the current symlink in the chain
            return 0
        fi
        link=$(readlink -- "$target")
        case "$link" in
            /*) target="$link" ;;
            *)  target="$(dirname -- "$target")/$link" ;;
        esac
    done
    printf '%s\n' "$target"
}

# find_bb_api_on_path: print unique resolved paths to `bb-api` on $PATH.
# Uses _resolve_symlink_chain for multi-hop chains.
find_bb_api_on_path() {
    local IFS=':'
    local p resolved seen=""
    for p in $PATH; do
        [ -z "$p" ] && continue
        if [ -x "$p/$BIN_NAME" ]; then
            resolved=$(_resolve_symlink_chain "$p/$BIN_NAME")
            case ":$seen:" in
                *":$resolved:"*) ;;
                *) printf '%s\n' "$resolved"; seen="${seen}:${resolved}" ;;
            esac
        fi
    done
}

# --- Orchestration wrapper ---
# Holds the step sequence + control flow. Helpers are above, testable.
_bb_api_install_main() {
    _print_header

    _step_call "Checking dependencies"
    check_deps

    _step_call "Detecting install paths"
    BIN_DIR=$(pick_install_dir "/usr/local/bin" "$HOME/.local/bin")
    DATA_DIR=$(pick_data_dir)
    if [ -z "${BB_API_USER_ONLY:-}" ] && [ "$BIN_DIR" = "/usr/local/bin" ]; then
        log_info "bin:  ${BOLD}$BIN_DIR${NC} (system)"
    else
        log_info "bin:  ${BOLD}$BIN_DIR${NC} (user)"
    fi
    log_info "data: ${BOLD}$DATA_DIR${NC}"
}

# Run only when executed directly. Tests source this file to exercise helpers.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _bb_api_install_main "$@"
fi
