#!/usr/bin/env bats

load test_helper

setup() {
    stub_paths
    load_bbb
}

teardown() {
    stub_paths_teardown
}

@test "pr decline: success format with single ID" {
    stub_curl '{"state":"DECLINED","id":42}' 200
    run cmd_pr_decline 42
    [ "$status" -eq 0 ]
    contains "$output" '*PR #42*'
    contains "$output" '*declined*'
    contains "$(last_curl_call)" '*/pullrequests/42/decline*'
}

@test "pr decline: batch continues on per-item failure" {
    stub_curl_seq \
        200 '{"state":"DECLINED"}' \
        404 '{"error":{"message":"PR not found"}}' \
        200 '{"state":"DECLINED"}'
    run cmd_pr_decline 1 2 3
    [ "$status" -eq 0 ]
    contains "$output" '*PR #1*declined*'
    contains "$output" '*PR #2*error*'
    contains "$output" '*PR #3*declined*'
    # Verify all three endpoints actually hit (batch didn't short-circuit on the 404)
    contains "$(nth_curl_call 1)" '*/pullrequests/1/decline*'
    contains "$(nth_curl_call 2)" '*/pullrequests/2/decline*'
    contains "$(nth_curl_call 3)" '*/pullrequests/3/decline*'
}

@test "pr approve: requires at least one ID" {
    run cmd_pr_approve
    [ "$status" -ne 0 ]
    contains "$output" '*Usage*'
}

@test "pr approve: sends correct endpoint" {
    stub_curl '{"user":{"display_name":"alice"}}' 200
    run cmd_pr_approve 5
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*/pullrequests/5/approve*'
}

@test "pr inline: --old flag sends 'from' field + path + text in payload" {
    stub_curl '{"id":1,"inline":{"path":"x.ts","from":10},"links":{"html":{"href":"http://x"}}}' 200
    run cmd_pr_inline --old 5 "x.ts" 10 "old code comment"
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*"from":10*'
    not_contains "$(last_curl_call)" '*"to":10*'
    contains "$(last_curl_call)" '*"path":"x.ts"*'
    contains "$(last_curl_call)" '*"old code comment"*'
}

@test "pr inline: default sends 'to' field + path + text in payload" {
    stub_curl '{"id":2,"inline":{"path":"y.ts","to":20},"links":{"html":{"href":"http://y"}}}' 200
    run cmd_pr_inline 5 "y.ts" 20 "new code comment"
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*"to":20*'
    not_contains "$(last_curl_call)" '*"from":20*'
    contains "$(last_curl_call)" '*"path":"y.ts"*'
    contains "$(last_curl_call)" '*"new code comment"*'
}

@test "pr open: prints URL when no opener available" {
    stub_curl '{"links":{"html":{"href":"https://bitbucket.org/ws/repo/pull-requests/42"}}}' 200
    stub_uname "BSD"
    run cmd_pr_open 42
    [ "$status" -eq 0 ]
    contains "$output" '*pull-requests/42*'
}

@test "pr merge: usage error without ID" {
    run cmd_pr_merge
    [ "$status" -ne 0 ]
    contains "$output" '*Usage*'
}

@test "pr merge: default strategy is merge_commit and payload uses 'type'" {
    stub_curl '{"id":42,"merge_commit":{"hash":"abc1234"}}' 200
    run cmd_pr_merge 42
    [ "$status" -eq 0 ]
    contains "$output" '*merge_commit*'
    contains "$(last_curl_call)" '*"type":"merge_commit"*'
}

@test "pr merge: --squash flag is reflected in payload" {
    stub_curl '{"id":42,"merge_commit":{"hash":"abc1234"}}' 200
    run cmd_pr_merge 42 --squash
    [ "$status" -eq 0 ]
    contains "$output" '*squash*'
    contains "$(last_curl_call)" '*"type":"squash"*'
}

@test "pr merge: --ff flag sets type=fast_forward" {
    stub_curl '{"id":42,"merge_commit":{"hash":"abc1234"}}' 200
    run cmd_pr_merge 42 --ff
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*"type":"fast_forward"*'
}

@test "pr merge: --delete-branch sets close_source_branch true" {
    stub_curl '{"id":42,"merge_commit":{"hash":"abc1234"}}' 200
    run cmd_pr_merge 42 --delete-branch
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*"close_source_branch":true*'
}

@test "pr merge: --message included in payload when set" {
    stub_curl '{"id":42,"merge_commit":{"hash":"abc1234"}}' 200
    run cmd_pr_merge 42 --message="Custom msg"
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*"message":"Custom msg"*'
}

@test "pr merge: omits message key when --message not passed" {
    stub_curl '{"id":42,"merge_commit":{"hash":"abc1234"}}' 200
    run cmd_pr_merge 42
    [ "$status" -eq 0 ]
    not_contains "$(last_curl_call)" '*"message"*'
}

@test "pr update: nothing-to-update error without flags" {
    run cmd_pr_update 5
    [ "$status" -ne 0 ]
    contains "$output" '*Nothing to update*'
}

@test "pr update: title-only payload" {
    stub_curl '{"id":5,"links":{"html":{"href":"http://x"}}}' 200
    run cmd_pr_update 5 --title="New title"
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*"title":"New title"*'
    not_contains "$(last_curl_call)" '*"description"*'
}

@test "pr update: --description=\"\" sends empty description (clearing)" {
    # Regression guard for the silent-drop bug fixed in this branch.
    stub_curl '{"id":5,"links":{"html":{"href":"http://x"}}}' 200
    run cmd_pr_update 5 --description=
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*"description":""*'
}

@test "pr update: reviewers payload uses username objects" {
    stub_curl '{"id":5,"links":{"html":{"href":"http://x"}}}' 200
    run cmd_pr_update 5 --reviewers=alice,bob
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*"username":"alice"*'
    contains "$(last_curl_call)" '*"username":"bob"*'
}

@test "pr update: reviewers filters empty entries from trailing comma" {
    stub_curl '{"id":5,"links":{"html":{"href":"http://x"}}}' 200
    run cmd_pr_update 5 --reviewers=alice,
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*"username":"alice"*'
    not_contains "$(last_curl_call)" '*"username":""*'
}

@test "pr list: --state=foo rejected" {
    run cmd_pr_list --state=foo
    [ "$status" -ne 0 ]
    contains "$output" '*Unknown --state*'
}

@test "pr list: --state=open accepted, query contains state=OPEN" {
    stub_curl '{"values":[]}' 200
    run cmd_pr_list --state=open
    [ "$status" -eq 0 ]
    contains "$(last_curl_call)" '*state=OPEN*'
}

@test "pr list: --state=all omits state filter from query" {
    stub_curl '{"values":[]}' 200
    run cmd_pr_list --state=all
    [ "$status" -eq 0 ]
    not_contains "$(last_curl_call)" '*state=*'
}

@test "pr list: --reviewer rejected with helpful message" {
    run cmd_pr_list --reviewer=alice
    [ "$status" -ne 0 ]
    contains "$output" '*not yet supported*'
}

@test "pr list: --author builds BBQL author.username query (URL-encoded)" {
    stub_curl '{"values":[]}' 200
    run cmd_pr_list --author=alice
    [ "$status" -eq 0 ]
    # @uri encoding produces %3D for '=' (full URL-component encoding, not the
    # historical hand-rolled "only space and quote" encoding).
    contains "$(last_curl_call)" '*q=author.username%3D%22alice%22*'
}

@test "pr checks: degrades gracefully when pipelines call returns 403" {
    # Three calls: PR detail, statuses (success), pipelines (403)
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"feature/x"}}}' \
        200 '{"values":[{"state":"SUCCESSFUL","name":"build","url":"http://ci/1"}]}' \
        403 '{"error":{"message":"scope missing"}}'
    run cmd_pr_checks 42
    [ "$status" -eq 0 ]
    contains "$output" '*PR statuses*'
    contains "$output" '*pass*'
    contains "$output" '*pipelines unavailable*'
}

@test "pr checks: URL-encodes branch with slashes" {
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"feature/x"}}}' \
        200 '{"values":[]}' \
        200 '{"values":[]}'
    run cmd_pr_checks 42
    [ "$status" -eq 0 ]
    # Pipelines call (3rd) must URL-encode the branch slash
    contains "$(nth_curl_call 3)" '*target.ref_name=feature%2Fx*'
    not_contains "$(nth_curl_call 3)" '*target.ref_name=feature/x*'
}

@test "pr checks: prints empty-state messages when no statuses or pipelines" {
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"main"}}}' \
        200 '{"values":[]}' \
        200 '{"values":[]}'
    run cmd_pr_checks 1
    [ "$status" -eq 0 ]
    contains "$output" '*no external statuses*'
    contains "$output" '*no pipelines for this branch*'
}

@test "pr show: rejects non-numeric id" {
    run cmd_pr_show "../etc/passwd"
    [ "$status" -ne 0 ]
    contains "$output" '*PR id must be numeric*'
}

@test "pr approve: rejects non-numeric id in batch" {
    run cmd_pr_approve 5 "../foo" 7
    [ "$status" -ne 0 ]
    contains "$output" '*PR id must be numeric*'
}
