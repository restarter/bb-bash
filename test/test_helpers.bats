#!/usr/bin/env bats

load test_helper

setup() {
    stub_paths
    load_bbb
}

teardown() {
    stub_paths_teardown
}

@test "resolve_workspace_repo: parses SSH URL with .git suffix" {
    stub_git "origin=git@bitbucket.org:myws/myrepo.git"
    unset WORKSPACE REPO
    resolve_workspace_repo
    [ "$WORKSPACE" = "myws" ]
    [ "$REPO" = "myrepo" ]
}

@test "resolve_workspace_repo: parses HTTPS URL" {
    stub_git "origin=https://bitbucket.org/anotherws/anotherrepo.git"
    unset WORKSPACE REPO
    resolve_workspace_repo
    [ "$WORKSPACE" = "anotherws" ]
    [ "$REPO" = "anotherrepo" ]
}

@test "resolve_workspace_repo: handles trailing slash + .git/" {
    stub_git "origin=https://bitbucket.org/ws/repo.git/"
    unset WORKSPACE REPO
    resolve_workspace_repo
    [ "$WORKSPACE" = "ws" ]
    [ "$REPO" = "repo" ]
}

@test "resolve_workspace_repo: ignores non-bitbucket origin and falls to env" {
    stub_git "origin=git@github.com:user/repo.git"
    export BB_BASH_WORKSPACE="envws"
    export BB_BASH_REPO="envrepo"
    unset BB_BASH_REMOTE WORKSPACE REPO
    resolve_workspace_repo
    [ "$WORKSPACE" = "envws" ]
    [ "$REPO" = "envrepo" ]
}

@test "resolve_workspace_repo: rejects slug with leading dot (path-traversal-ish)" {
    stub_git "origin=git@bitbucket.org:.hidden/repo.git"
    unset WORKSPACE REPO BB_BASH_WORKSPACE BB_BASH_REPO
    run resolve_workspace_repo
    [ "$status" -ne 0 ]
    contains "$output" '*Invalid workspace slug*'
}

@test "resolve_workspace_repo: rejects evil.bitbucket.org false-positive" {
    stub_git "origin=git@evil.bitbucket.org.attacker.com:foo/bar.git"
    export BB_BASH_WORKSPACE="envws"
    export BB_BASH_REPO="envrepo"
    unset BB_BASH_REMOTE WORKSPACE REPO
    resolve_workspace_repo
    # Should fall to env vars (regex anchored)
    [ "$WORKSPACE" = "envws" ]
    [ "$REPO" = "envrepo" ]
}

@test "resolve_workspace_repo: scans multiple remotes for bitbucket" {
    stub_git "origin=git@github.com:u/r.git" "bb=git@bitbucket.org:bbws/bbrepo.git"
    unset WORKSPACE REPO BB_BASH_WORKSPACE BB_BASH_REPO BB_BASH_REMOTE
    resolve_workspace_repo
    [ "$WORKSPACE" = "bbws" ]
    [ "$REPO" = "bbrepo" ]
}

@test "api_post --soft: returns body on 4xx with non-zero exit" {
    stub_curl '{"error":{"message":"not found"}}' 404
    run api_post --soft "/some/endpoint" '{}'
    [ "$status" -ne 0 ]
    contains "$output" '*not found*'
}

@test "api_post (hard mode): dies on 4xx" {
    stub_curl '{"error":{"message":"forbidden"}}' 403
    run api_post "/some/endpoint" '{}'
    [ "$status" -ne 0 ]
    contains "$output" '*API error*'
}

@test "api_get --soft: returns body on 403 with non-zero exit" {
    stub_curl '{"error":{"message":"scope missing"}}' 403
    run api_get --soft "/pipelines/?target.ref_name=foo"
    [ "$status" -ne 0 ]
    contains "$output" '*scope missing*'
}

@test "api_get: a curl transport failure is fatal, not an empty success" {
    # curl exits 6/7/35 and prints nothing, so http_code is empty — and
    # [[ "" -ge 400 ]] is FALSE. Without an explicit exit-status check the
    # transport error would pass through as a successful empty response.
    stub_curl_fail 6
    run api_get "/pullrequests/42"
    [ "$status" -ne 0 ]
    contains "$output" '*network error*'
}

@test "api_get --soft: a curl transport failure is fatal even in soft mode" {
    # --soft downgrades HTTP errors, not transport errors: there is no body to
    # degrade to, and the caller would report "no results" for a dead network.
    stub_curl_fail 7
    run api_get --soft "/pipelines/?pagelen=20"
    [ "$status" -ne 0 ]
    contains "$output" '*network error*'
}

@test "api_post: a curl transport failure is fatal" {
    stub_curl_fail 35
    run api_post "/pullrequests/42/comments" '{"content":{"raw":"x"}}'
    [ "$status" -ne 0 ]
    contains "$output" '*network error*'
}

@test "api_put: a curl transport failure is fatal" {
    stub_curl_fail 6
    run api_put "/pullrequests/42/comments/1" '{"content":{"raw":"x"}}'
    [ "$status" -ne 0 ]
    contains "$output" '*network error*'
}

@test "api_delete: a curl transport failure is fatal, not an empty status code" {
    # Callers do status=$(api_delete ...); an unguarded transport failure would
    # make that the empty string and print "Failed to delete (HTTP )".
    stub_curl_fail 7
    run api_delete "/pullrequests/42/comments/1"
    [ "$status" -ne 0 ]
    contains "$output" '*network error*'
}

@test "batch_action: success format" {
    stub_curl '{"state":"DECLINED"}' 200
    run batch_action "declined" "/pullrequests/{id}/decline" '.state' 42
    [ "$status" -eq 0 ]
    contains "$output" '*PR #42*'
    contains "$output" '*declined*'
}
