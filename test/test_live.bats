#!/usr/bin/env bats

# Live-API tests for bb-api. Skipped by default.
# Run with:
#   BB_API_TEST_LIVE=1 BB_API_EMAIL=... BB_API_TOKEN=... \
#     BB_API_TEST_WORKSPACE=<ws> BB_API_TEST_REPO=<repo> \
#     bats test/test_live.bats
#
# These tests hit real Bitbucket APIs. Use a sandbox/staging repo, not prod.

setup() {
    [[ "${BB_API_TEST_LIVE:-0}" = "1" ]] \
        || skip "Set BB_API_TEST_LIVE=1 to run live API tests"
    [[ -n "${BB_API_EMAIL:-}" && -n "${BB_API_TOKEN:-}" ]] \
        || skip "BB_API_EMAIL and BB_API_TOKEN must be set"
    [[ -n "${BB_API_TEST_WORKSPACE:-}" && -n "${BB_API_TEST_REPO:-}" ]] \
        || skip "BB_API_TEST_WORKSPACE and BB_API_TEST_REPO must be set"

    export BB_API_WORKSPACE="$BB_API_TEST_WORKSPACE"
    export BB_API_REPO="$BB_API_TEST_REPO"
    BB_API_SCRIPT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/bb-api"
    export BB_API_SCRIPT
}

@test "live: pr list returns valid JSON" {
    run "$BB_API_SCRIPT" raw "/pullrequests?state=OPEN&pagelen=1"
    [ "$status" -eq 0 ]
    echo "$output" | jq . >/dev/null
}

@test "live: auth works (whoami via /user endpoint)" {
    # The /user endpoint is on api.bitbucket.org, not /repositories/.../user.
    # Use curl directly to verify creds.
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -u "${BB_API_EMAIL}:${BB_API_TOKEN}" \
        "https://api.bitbucket.org/2.0/user")
    [ "$response" = "200" ]
}
