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

@test "pr checks: pipelines query carries no ref_name filter" {
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"feature/x"}}}' \
        200 '{"values":[]}' \
        200 '{"values":[]}'
    run cmd_pr_checks 42
    [ "$status" -eq 0 ]
    # target.ref_name= is not a valid Bitbucket pipelines filter and can never
    # match a PR-triggered pipeline — the query must not carry it.
    not_contains "$(nth_curl_call 3)" '*target.ref_name*'
    contains "$(nth_curl_call 3)" '*sort=-created_on*'
}

@test "pr checks: lists a PR-triggered pipeline (target.source, ref_name null)" {
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"feature/x"}}}' \
        200 '{"values":[]}' \
        200 '{"values":[{"build_number":7,"state":{"name":"COMPLETED","result":{"name":"FAILED"}},"created_on":"2026-07-22T10:00:00+00:00","creator":{"display_name":"Dima"},"target":{"type":"pipeline_pullrequest_target","source":"feature/x","ref_name":null,"commit":{"hash":"abcdef1234567"},"selector":{"type":"pull-requests"}}}]}'
    run cmd_pr_checks 42
    [ "$status" -eq 0 ]
    contains "$output" '*#7*'
    contains "$output" '*fail*'
    contains "$output" '*pull-requests*'
    contains "$output" '*abcdef1*'
}

@test "pr checks: lists a branch-triggered pipeline (target.ref_name)" {
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"feature/x"}}}' \
        200 '{"values":[]}' \
        200 '{"values":[{"build_number":9,"state":{"name":"COMPLETED","result":{"name":"SUCCESSFUL"}},"created_on":"2026-07-22T11:00:00+00:00","creator":{"display_name":"Dima"},"target":{"type":"pipeline_ref_target","ref_name":"feature/x","commit":{"hash":"1234567abcdef"},"selector":{"type":"branches"}}}]}'
    run cmd_pr_checks 42
    [ "$status" -eq 0 ]
    contains "$output" '*#9*'
    contains "$output" '*pass*'
    contains "$output" '*branches*'
}

@test "pr checks: filters out pipelines from other branches" {
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"feature/x"}}}' \
        200 '{"values":[]}' \
        200 '{"values":[{"build_number":7,"state":{"result":{"name":"FAILED"}},"created_on":"2026-07-22T10:00:00+00:00","creator":{"display_name":"D"},"target":{"source":"feature/x","commit":{"hash":"aaaaaaabbbb"},"selector":{"type":"pull-requests"}}},{"build_number":8,"state":{"result":{"name":"SUCCESSFUL"}},"created_on":"2026-07-22T10:30:00+00:00","creator":{"display_name":"D"},"target":{"ref_name":"main","commit":{"hash":"ccccccceeee"},"selector":{"type":"branches"}}}]}'
    run cmd_pr_checks 42
    [ "$status" -eq 0 ]
    contains "$output" '*#7*'
    not_contains "$output" '*#8*'
}

@test "pr checks: hints at the scan window when it comes back full with no match" {
    export BB_BASH_PIPELINE_SCAN=1
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"feature/x"}}}' \
        200 '{"values":[]}' \
        200 '{"values":[{"build_number":8,"state":{"result":{"name":"SUCCESSFUL"}},"created_on":"2026-07-22T10:30:00+00:00","creator":{"display_name":"D"},"target":{"ref_name":"main","commit":{"hash":"ccccccceeee"},"selector":{"type":"branches"}}}]}'
    run cmd_pr_checks 42
    unset BB_BASH_PIPELINE_SCAN
    [ "$status" -eq 0 ]
    contains "$output" '*no pipelines for this branch*'
    contains "$output" '*BB_BASH_PIPELINE_SCAN*'
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

@test "raw: pretty-prints JSON by default" {
    stub_curl '{"a":1}'
    run cmd_raw "/foo"
    [ "$status" -eq 0 ]
    contains "$output" '*"a": 1*'
}

@test "raw --text: passes a plain-text body through untouched" {
    stub_curl 'plain log line
second line'
    run cmd_raw --text "/pipelines/%7Bp%7D/steps/%7Bs%7D/log"
    [ "$status" -eq 0 ]
    contains "$output" '*plain log line*'
    contains "$output" '*second line*'
}

@test "raw: rejects a missing endpoint" {
    run cmd_raw --text
    [ "$status" -ne 0 ]
    contains "$output" '*Usage: bbb raw*'
}

@test "pipeline log: URL-encodes braced UUIDs in path segments" {
    stub_curl_seq \
        200 '{"uuid":"{p-1}","build_number":7}' \
        200 '{"values":[{"uuid":"{s-1}","name":"Build","state":{"name":"COMPLETED","result":{"name":"FAILED"}}}]}' \
        200 'step log body'
    run cmd_pipeline_log 7
    [ "$status" -eq 0 ]
    contains "$(nth_curl_call 2)" '*%7Bp-1%7D*'
    contains "$(nth_curl_call 3)" '*%7Bs-1%7D*'
    contains "$output" '*step log body*'
}

@test "pipeline log: falls back to a list scan when direct lookup fails" {
    stub_curl_seq \
        404 '{"error":{"message":"not found"}}' \
        200 '{"values":[{"build_number":7,"uuid":"{p-1}"}]}' \
        200 '{"values":[{"uuid":"{s-1}","name":"Build","state":{"result":{"name":"FAILED"}}}]}' \
        200 'scanned log'
    run cmd_pipeline_log 7
    [ "$status" -eq 0 ]
    contains "$output" '*scanned log*'
}

@test "pipeline log: picks the first FAILED step" {
    stub_curl_seq \
        200 '{"uuid":"{p-1}","build_number":7}' \
        200 '{"values":[{"uuid":"{s-1}","name":"Setup","state":{"result":{"name":"SUCCESSFUL"}}},{"uuid":"{s-2}","name":"Test","state":{"result":{"name":"FAILED"}}}]}' \
        200 'failing test output'
    run cmd_pipeline_log 7
    [ "$status" -eq 0 ]
    contains "$output" '*Test*'
    contains "$(nth_curl_call 3)" '*%7Bs-2%7D*'
}

@test "pipeline log: --step=0 is rejected, not silently the last step" {
    stub_curl_seq \
        200 '{"uuid":"{p-1}","build_number":7}' \
        200 '{"values":[{"uuid":"{s-1}","name":"Setup","state":{"result":{"name":"SUCCESSFUL"}}},{"uuid":"{s-2}","name":"Test","state":{"result":{"name":"FAILED"}}}]}'
    run cmd_pipeline_log 7 --step=0
    [ "$status" -ne 0 ]
    contains "$output" '*--step must be 1 or greater*'
}

@test "pipeline log: rejects a non-numeric build number" {
    run cmd_pipeline_log "../etc/passwd"
    [ "$status" -ne 0 ]
    contains "$output" '*build number must be numeric*'
}

@test "pr logs: resolves the newest matching pipeline for the PR" {
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"feature/x"}}}' \
        200 '{"values":[{"build_number":7,"uuid":"{p-7}","target":{"source":"feature/x"}}]}' \
        200 '{"values":[{"uuid":"{s-1}","name":"Build","state":{"result":{"name":"FAILED"}}}]}' \
        200 'pr log body'
    run cmd_pr_logs 42
    [ "$status" -eq 0 ]
    contains "$output" '*PR 42 pipeline #7*'
    contains "$output" '*pr log body*'
}

@test "pr logs: dies clearly when the PR has no pipelines" {
    stub_curl_seq \
        200 '{"source":{"branch":{"name":"feature/x"}}}' \
        200 '{"values":[]}'
    run cmd_pr_logs 42
    [ "$status" -ne 0 ]
    contains "$output" '*No pipelines found for PR 42*'
}
