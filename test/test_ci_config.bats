#!/usr/bin/env bats
#
# Guards the CI configuration itself. The workflow is the one place where a
# silently-skipped file produces no error at all — nothing runs, and nothing
# says so. That already happened twice in this repo: the bats file list had
# dropped a 22-test suite, and the shellcheck list is still hand-written.
#
# The bats side was fixed by discovery. The shellcheck side cannot be: its file
# list is a static YAML string consumed by a SHA-pinned action, and the pinning
# is worth more than the convenience. So the enumeration stays and this asserts
# it stays complete.

load test_helper

# CI lints shell with a SHA-pinned action whose file list is a static YAML string,
# so it cannot be discovered the way the bats file list now is. The list had
# already gone stale once by omission rather than by decision. This asserts the
# enumeration still covers everything, which is the part that was missing — the
# pinning is worth keeping, the silent skip is not.
@test "ci: shellcheck lints every shell file in the repo" {
    local ci="$BB_BASH_ROOT/.github/workflows/ci.yml" listed ignored f failed=0
    listed=$(sed -n 's/.*additional_files: *.\(.*\).$/\1/p' "$ci" | tr ' ' '\n' | grep -v '^$')
    ignored=$(sed -n "s/.*ignore_paths: *'\(.*\)'.*/\1/p" "$ci" | tr ' ' '\n' | grep -v '^$')
    [ -n "$listed" ] || { echo "could not parse additional_files out of ci.yml" >&2; return 1; }

    # Everything tracked that shellcheck can parse. .bats is deliberately out —
    # its @test syntax is not shell, which is why ignore_paths exists at all.
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        # Covered explicitly?
        printf '%s\n' "$listed" | grep -qxF "$f" && continue
        # Otherwise the action finds *.sh itself, unless the path is ignored.
        case "$f" in
            *.sh)
                local dir="${f%%/*}" skip=0
                printf '%s\n' "$ignored" | grep -qxF "$dir" && skip=1
                [ "$skip" -eq 0 ] && continue
                ;;
        esac
        echo "$f is not linted by CI." >&2
        echo "  It is neither in additional_files nor auto-discovered" >&2
        echo "  (ignore_paths: $(printf '%s' "$ignored" | tr '\n' ' '))." >&2
        echo "  Add it to additional_files in .github/workflows/ci.yml." >&2
        failed=1
    done < <(cd "$BB_BASH_ROOT" && git ls-files 'bbb' '*.sh' '*.bash')

    [ "$failed" -eq 0 ]
}
