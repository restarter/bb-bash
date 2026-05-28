#!/usr/bin/env bash
#
# bb-bash installer
# Usage:
#   curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/restarter/bb-bash/main/scripts/install.sh | bash
#
# Re-run to update. Never touches .env.
#
# IMPORTANT: must be EXECUTED, never SOURCED for production use (set -e
# would kill the user's shell on errors). Tests source it; the guard at
# the bottom skips _bbb_install_main() when sourced. Helpers are at
# top level (testable); orchestration lives in the wrapper. Truncation-safe
# either way — see the architecture note in the plan.
#

set -euo pipefail

REPO="restarter/bb-bash"
BIN_NAME="bbb"
RAW_BASE="https://raw.githubusercontent.com/${REPO}"
API_BASE="https://api.github.com/repos/${REPO}"

# Curl hardening: HTTPS only (no http:// redirects), TLS 1.2+, redirect cap.
CURL_OPTS=(--proto '=https' --proto-redir '=https' --tlsv1.2 --max-redirs 5 -fsSL)

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
   ${BOLD}bb-bash installer${NC}
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
        log_warning "jq not found — bbb needs it at runtime, install with:"
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
# AND BB_BASH_USER_ONLY not set, else creates and returns $2.
# No auto-sudo — surprise sudo prompts on `curl | bash` are bad UX.
pick_install_dir() {
    local preferred=$1 fallback=$2
    if [ -z "${BB_BASH_USER_ONLY:-}" ] && [ -w "$preferred" ] 2>/dev/null; then
        echo "$preferred"
    else
        mkdir -p "$fallback"
        echo "$fallback"
    fi
}

pick_data_dir() {
    local base="${XDG_DATA_HOME:-$HOME/.local/share}"
    echo "$base/bb-bash"
}

path_contains() {
    case ":$PATH:" in
        *":$1:"*) return 0 ;;
        *)        return 1 ;;
    esac
}

# _resolve_symlink_chain: portable multi-hop symlink resolution with hop cap.
# Mirrors bbb's resolve_script_dir so install.sh has the same behavior
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

# find_bbb_on_path: print unique resolved paths to `bbb` on $PATH.
# Uses _resolve_symlink_chain for multi-hop chains.
find_bbb_on_path() {
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

# --- Release / download helpers ---

# fetch_release_json: GET /releases/latest. Public repo only. Unauth rate
# limit is 60/hr per IP. Don't swallow curl stderr — users need to tell
# DNS vs 403 vs 404 apart.
fetch_release_json() {
    local url="${API_BASE}/releases/latest"
    RELEASE_JSON=$(curl "${CURL_OPTS[@]}" "$url") || {
        log_error "Failed to fetch ${url}"
        log_info  "    See https://github.com/${REPO}/releases (is there a release?)"
        log_info  "    Or check network / rate limit (60/hr unauth)."
        exit 1
    }
}

# extract_tag_name: parse "tag_name" out of the JSON arg. Uses jq when
# available (project convention); falls back to a strict grep+sed regex.
# Always SemVer-whitelists the result via a bash regex so the value can be
# safely interpolated into the download URL. Refuses `../`, spaces, and any
# non-SemVer characters — a case-glob is too permissive (`v[0-9]*.*` would
# match `v1../../../evil.0.0` because `*` is greedy and doesn't restrict
# to digits). Bash regex `[[ =~ ]]` is supported on bash 3.2+.
extract_tag_name() {
    local tag
    if command -v jq >/dev/null 2>&1; then
        tag=$(printf '%s' "$1" | jq -r '.tag_name // empty')
    else
        tag=$(printf '%s' "$1" \
              | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
              | head -1 \
              | sed -E 's/.*"([^"]+)"$/\1/')
    fi
    if [ -z "$tag" ]; then
        return 1
    fi
    if [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?(\+[A-Za-z0-9.-]+)?$ ]]; then
        printf '%s\n' "$tag"
    else
        die "Refusing tag with unexpected shape: '$tag' (expected vMAJOR.MINOR.PATCH[-PRE][+BUILD])"
    fi
}

# download_file <url> <out>
download_file() {
    local url=$1 out=$2
    curl "${CURL_OPTS[@]}" -o "$out" "$url"
}

# --- PATH / multi-binary helpers ---

# check_path_and_multi_binary: emit PATH-membership warning + detect duplicate
# bbb copies on $PATH. Uses _resolve_symlink_chain for multi-hop chains.
check_path_and_multi_binary() {
    local target_bin_dir=$BIN_DIR

    if ! path_contains "$target_bin_dir"; then
        echo "" >&2
        log_warning "${target_bin_dir} is not in your PATH."
        printf '%b\n' "    ${DIM}Add to ~/.bashrc, ~/.zshrc, or ~/.profile:${NC}" >&2
        echo "" >&2
        printf '%b\n' "      ${BOLD}export PATH=\"\$PATH:${target_bin_dir}\"${NC}" >&2
        echo "" >&2
    fi

    # bash 3.2 empty-array set -u safety
    local copies
    copies=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && copies+=("$line")
    done < <(find_bbb_on_path)
    local copies_count=${#copies[@]}

    if [ "$copies_count" -gt 1 ]; then
        echo "" >&2
        log_warning "Multiple '${BIN_NAME}' executables on your PATH — earlier entries win."
        printf '%b\n' "    ${DIM}Found:${NC}" >&2
        local i=1 p
        for p in "${copies[@]}"; do
            printf '%b\n' "      ${BOLD}${i}.${NC} $p" >&2
            i=$((i+1))
        done
        echo "" >&2
        printf '%b\n' "    ${DIM}We installed at: ${target_bin_dir}/${BIN_NAME} -> ${DATA_DIR}/${BIN_NAME}${NC}" >&2
    fi
}

# final_message: print next-steps after a successful install/update.
final_message() {
    local tag=$1
    printf '%b\n' "
   ${GREEN}${BOLD}bb-bash ${tag} ready${NC} at ${BOLD}${BIN_DIR}/${BIN_NAME}${NC}

   ${CYAN}${BOLD}Next steps${NC}
     1. Edit ${BOLD}${DATA_DIR}/.env${NC} with your Bitbucket credentials.
        Token: ${DIM}https://id.atlassian.com/manage-profile/security/api-tokens${NC}
     2. cd into any bitbucket.org repo and run:
        ${BOLD}bbb pr list${NC}

   ${DIM}Docs: https://github.com/${REPO}#readme${NC}
   ${DIM}Re-run this installer to update; .env is never touched.${NC}
" >&2
}

# --- Orchestration wrapper ---
# Holds the step sequence + control flow. Helpers are above, testable.
_bbb_install_main() {
    _print_header

    _step_call "Checking dependencies"
    check_deps

    _step_call "Detecting install paths"
    BIN_DIR=$(pick_install_dir "/usr/local/bin" "$HOME/.local/bin")
    DATA_DIR=$(pick_data_dir)
    if [ -z "${BB_BASH_USER_ONLY:-}" ] && [ "$BIN_DIR" = "/usr/local/bin" ]; then
        log_info "bin:  ${BOLD}$BIN_DIR${NC} (system)"
    else
        log_info "bin:  ${BOLD}$BIN_DIR${NC} (user)"
    fi
    log_info "data: ${BOLD}$DATA_DIR${NC}"

    _step_call "Fetching latest release"
    fetch_release_json
    TAG=$(extract_tag_name "$RELEASE_JSON") || die "No tag_name in release JSON (release exists?)"
    log_success "Latest release: ${BOLD}${TAG}${NC}"

    _step_call "Checking existing installation"
    if [ -f "$DATA_DIR/VERSION" ]; then
        INSTALLED_TAG=$(cat "$DATA_DIR/VERSION")
        if [ "$INSTALLED_TAG" = "$TAG" ]; then
            log_info "Already at ${TAG}, nothing to update."
            log_info "(.env and .env.example left untouched.)"
            # Re-chmod 600 unconditionally to heal manual-install drift.
            if [ -f "$DATA_DIR/.env" ]; then
                chmod 600 "$DATA_DIR/.env"
            fi
            check_path_and_multi_binary
            exit 0
        fi
        log_info "Updating ${INSTALLED_TAG} -> ${TAG}"
    else
        log_info "Fresh install: ${TAG}"
        INSTALLED_TAG=""
    fi

    _step_call "Downloading"
    # Stage INSIDE DATA_DIR so the final mv is atomic (rename-on-same-fs).
    mkdir -p "$DATA_DIR"
    chmod 700 "$DATA_DIR"
    DOWNLOAD_TMP=$(mktemp -d "$DATA_DIR/.stage.XXXXXX")
    # shellcheck disable=SC2064  # expand DOWNLOAD_TMP NOW for trap
    trap "rm -rf '$DOWNLOAD_TMP'" EXIT
    download_file "${RAW_BASE}/${TAG}/${BIN_NAME}"    "${DOWNLOAD_TMP}/${BIN_NAME}"    || die "Download failed: ${BIN_NAME}"
    download_file "${RAW_BASE}/${TAG}/.env.example"   "${DOWNLOAD_TMP}/.env.example"   || die "Download failed: .env.example"
    log_success "Fetched ${BIN_NAME} and .env.example"

    # Sanity-check the downloaded bbb is actually a bash script.
    head -1 "${DOWNLOAD_TMP}/${BIN_NAME}" | grep -q '^#!/usr/bin/env bash' \
        || die "Downloaded file doesn't look like bbb(missing shebang)."

    _step_call "Installing"

    # Atomic install: bbb lands as `bbb.new` first, then `mv` into the
    # final name on the same filesystem (rename is atomic). A crash mid-install
    # leaves an old bbb in place rather than a half-written file.
    cp "${DOWNLOAD_TMP}/${BIN_NAME}" "${DATA_DIR}/${BIN_NAME}.new"
    chmod +x "${DATA_DIR}/${BIN_NAME}.new"
    mv "${DATA_DIR}/${BIN_NAME}.new" "${DATA_DIR}/${BIN_NAME}"

    # .env.example: refresh with explicit mode 644.
    cp "${DOWNLOAD_TMP}/.env.example" "${DATA_DIR}/.env.example.new"
    chmod 644 "${DATA_DIR}/.env.example.new"
    mv "${DATA_DIR}/.env.example.new" "${DATA_DIR}/.env.example"

    # VERSION marker — used by the skip-if-same-tag fast path on re-run.
    printf '%s\n' "$TAG" > "${DATA_DIR}/VERSION"

    # .env: create on first install, NEVER overwrite on re-run. Always end
    # at mode 600 (heals previous 644 if user came from a manual install).
    if [ -f "${DATA_DIR}/.env" ]; then
        chmod 600 "${DATA_DIR}/.env"
        log_info ".env exists; left untouched (re-chmod 600 applied)."
        log_info "(check .env.example for new variables: diff ${DATA_DIR}/.env ${DATA_DIR}/.env.example)"
    else
        # Atomic + race-free: umask makes cp create the target as 600 in one syscall.
        ( umask 077 && cp "${DATA_DIR}/.env.example" "${DATA_DIR}/.env" )
        log_info "Created ${DATA_DIR}/.env from .env.example (chmod 600)."
        log_info "Edit it with your Bitbucket credentials before first use."
    fi

    # Symlink into PATH. Refuse non-symlink overwrite unless BB_BASH_FORCE=1.
    # Warn when an existing symlink points somewhere other than our data dir.
    mkdir -p "$BIN_DIR"
    if [ -e "${BIN_DIR}/${BIN_NAME}" ] && [ ! -L "${BIN_DIR}/${BIN_NAME}" ]; then
        if [ "${BB_BASH_FORCE:-}" = "1" ]; then
            log_warning "Removing existing non-symlink ${BIN_DIR}/${BIN_NAME} (BB_BASH_FORCE=1)."
            rm -f "${BIN_DIR}/${BIN_NAME}"
        else
            die "${BIN_DIR}/${BIN_NAME} exists and is not a symlink. Refusing to overwrite. Remove it or re-run with BB_BASH_FORCE=1."
        fi
    elif [ -L "${BIN_DIR}/${BIN_NAME}" ]; then
        local existing_target
        existing_target=$(readlink -- "${BIN_DIR}/${BIN_NAME}")
        if [ "$existing_target" != "${DATA_DIR}/${BIN_NAME}" ]; then
            log_warning "Replacing existing symlink ${BIN_DIR}/${BIN_NAME} -> $existing_target"
        fi
    fi
    # -n avoids the corner case where target is a dir-symlink (would otherwise
    # create the link INSIDE that directory).
    ln -sfn "${DATA_DIR}/${BIN_NAME}" "${BIN_DIR}/${BIN_NAME}"
    log_success "Linked ${BIN_DIR}/${BIN_NAME} -> ${DATA_DIR}/${BIN_NAME}"

    _step_call "Verifying"
    if bash -n "${DATA_DIR}/${BIN_NAME}"; then
        log_success "Syntax OK"
    else
        die "Syntax check failed for ${DATA_DIR}/${BIN_NAME}."
    fi
    check_path_and_multi_binary
    final_message "$TAG"
}

# Run only when executed directly OR when read from stdin (curl | bash).
# Tests source this file to exercise helpers — in that case BASH_SOURCE[0]
# points at the file path and $0 is the test runner, so this guard skips main.
# Under stdin-pipe (curl | bash), BASH_SOURCE is empty; ${...:-$0} substitutes
# $0 ("bash") so the comparison succeeds and main runs. Without the :-$0 the
# bare ${BASH_SOURCE[0]} triggers `set -u` "unbound variable" before main.
if [[ "${BASH_SOURCE[0]:-$0}" == "${0}" ]]; then
    _bbb_install_main "$@"
fi
