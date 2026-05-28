#!/usr/bin/env bats

# Live-API tests for bbb. Skipped by default.
# Run with:
#   BB_BASH_TEST_LIVE=1 BB_BASH_EMAIL=... BB_BASH_TOKEN=... \
#     BB_BASH_TEST_WORKSPACE=<ws> BB_BASH_TEST_REPO=<repo> \
#     bats test/test_live.bats
#
# These tests hit real Bitbucket APIs. Use a sandbox/staging repo, not prod.

setup() {
    [[ "${BB_BASH_TEST_LIVE:-0}" = "1" ]] \
        || skip "Set BB_BASH_TEST_LIVE=1 to run live API tests"
    [[ -n "${BB_BASH_EMAIL:-}" && -n "${BB_BASH_TOKEN:-}" ]] \
        || skip "BB_BASH_EMAIL and BB_BASH_TOKEN must be set"
    [[ -n "${BB_BASH_TEST_WORKSPACE:-}" && -n "${BB_BASH_TEST_REPO:-}" ]] \
        || skip "BB_BASH_TEST_WORKSPACE and BB_BASH_TEST_REPO must be set"

    export BB_BASH_WORKSPACE="$BB_BASH_TEST_WORKSPACE"
    export BB_BASH_REPO="$BB_BASH_TEST_REPO"
    BB_BASH_SCRIPT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/bbb"
    export BB_BASH_SCRIPT
}

@test "live: pr list returns valid JSON" {
    run "$BB_BASH_SCRIPT" raw "/pullrequests?state=OPEN&pagelen=1"
    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null
}

@test "live: auth works (whoami via /user endpoint)" {
    # The /user endpoint is on api.bitbucket.org, not /repositories/.../user.
    # Use curl directly to verify creds.
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${BB_BASH_EMAIL}:${BB_BASH_TOKEN}" \
        "https://api.bitbucket.org/2.0/user")
    [ "$response" = "200" ]
}
