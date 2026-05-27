#!/usr/bin/env bats

load test_helper

setup() {
    stub_paths
    load_bb_api
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
    export BB_API_WORKSPACE="envws"
    export BB_API_REPO="envrepo"
    unset BB_API_REMOTE WORKSPACE REPO
    resolve_workspace_repo
    [ "$WORKSPACE" = "envws" ]
    [ "$REPO" = "envrepo" ]
}

@test "resolve_workspace_repo: rejects slug with leading dot (path-traversal-ish)" {
    stub_git "origin=git@bitbucket.org:.hidden/repo.git"
    unset WORKSPACE REPO BB_API_WORKSPACE BB_API_REPO
    run resolve_workspace_repo
    [ "$status" -ne 0 ]
    contains "$output" '*Invalid workspace slug*'
}

@test "resolve_workspace_repo: rejects evil.bitbucket.org false-positive" {
    stub_git "origin=git@evil.bitbucket.org.attacker.com:foo/bar.git"
    export BB_API_WORKSPACE="envws"
    export BB_API_REPO="envrepo"
    unset BB_API_REMOTE WORKSPACE REPO
    resolve_workspace_repo
    # Should fall to env vars (regex anchored)
    [ "$WORKSPACE" = "envws" ]
    [ "$REPO" = "envrepo" ]
}

@test "resolve_workspace_repo: scans multiple remotes for bitbucket" {
    stub_git "origin=git@github.com:u/r.git" "bb=git@bitbucket.org:bbws/bbrepo.git"
    unset WORKSPACE REPO BB_API_WORKSPACE BB_API_REPO BB_API_REMOTE
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

@test "batch_action: success format" {
    stub_curl '{"state":"DECLINED"}' 200
    run batch_action "declined" "/pullrequests/{id}/decline" '.state' 42
    [ "$status" -eq 0 ]
    contains "$output" '*PR #42*'
    contains "$output" '*declined*'
}
