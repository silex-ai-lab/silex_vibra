#!/bin/bash
# Probe 5: each mutation must be caught by the test the plan names.
# Usage: tools/gate/mutate.sh <repo>
# Runs in a throwaway `git worktree` of HEAD; the caller's checkout is never
# touched. Prints one CAUGHT or MISSED line per mutation and exits non-zero
# when any is MISSED or a mutation's anchor text is not found exactly once.
set -uo pipefail
repo=$(cd "$1" && pwd)
work=$(mktemp -d)
log=$work/.mutate.log
trap 'cd /; git -C "$repo" worktree remove --force "$work" >/dev/null 2>&1; rm -rf "$work"' EXIT
git -C "$repo" worktree add --detach "$work" HEAD >/dev/null 2>&1 || { echo "ERROR: could not create a worktree"; exit 2; }

analyzer=Sources/VibraCore/Perf/PerfAnalyzer.swift
adapter=Sources/VibraCore/Adapters/ClaudeCodeAdapter.swift
failed=0

# edit <file> <old> <new>: replace the one line holding <old>, literally.
edit() {
    local file=$work/$1 old=$2 new=$3
    local hits
    hits=$(grep -cF -- "$old" "$file")
    if [ "$hits" != 1 ]; then
        echo "ERROR: expected exactly one line matching '$old' in $1, found $hits"
        return 1
    fi
    perl -i -pe 'BEGIN { ($o, $n) = splice(@ARGV, 0, 2) } s/\Q$o\E/$n/' "$old" "$new" "$file"
}

# run <label> <test> <file>: build and run the suite in the worktree, report
# whether <test> failed, then restore <file>.
run() {
    local label=$1 test=$2 file=$3
    (cd "$work" && swift run --build-system native VibraTests > "$log" 2>&1)
    if grep -qF "Test $test() failed" "$log"; then
        echo "CAUGHT  $label: $test failed"
    elif grep -qF "Test $test() passed" "$log"; then
        echo "MISSED  $label: $test still passed"
        failed=1
    else
        echo "MISSED  $label: $test did not run (build broken?)"
        grep -m3 "error:" "$log" | sed 's/^/        /'
        failed=1
    fi
    git -C "$work" checkout -q -- "$file"
}

# A mutation whose anchor is missing is a failure of the probe itself, and its
# partial edits must not bleed into the next mutation.
unapplied() {
    echo "MISSED  $1: mutation did not apply"
    failed=1
    git -C "$work" checkout -q -- "$analyzer" "$adapter"
}

label="drop the lead-share comparison"
edit "$analyzer" \
    'exposure >= thresholds.leadMinShare * sessionValue {' \
    'true {' \
    && run "$label" leadNeedsShareOfSessionValue "$analyzer" \
    || unapplied "$label"

label="drop the D2 segment check"
edit "$analyzer" \
    'guard segmentIDs[index] == segmentIDs[index - 1], inWindow[index] else { continue }' \
    'guard inWindow[index] else { continue }' \
    && run "$label" compactionIsNotARewrite "$analyzer" \
    || unapplied "$label"

label="merge records with no ID"
edit "$adapter" \
    'if let id, let held = pending, held.id == id {' \
    'if let held = pending, id == nil || held.id == id {' \
    && edit "$adapter" \
    'pending = (id, UsageSample(' \
    'pending = (held.id, UsageSample(' \
    && edit "$adapter" \
    '        if let id {' \
    '        if let id = Optional(id ?? "") {' \
    && run "$label" recordsWithoutIDNeverMerge "$adapter" \
    || unapplied "$label"

label="copy tool_use.input into toolNames"
edit "$adapter" \
    '            return name' \
    '            return name + String(describing: block["input"] ?? "")' \
    && run "$label" perfPrivacySentinelsNeverLeak "$adapter" \
    || unapplied "$label"

if [ "$failed" = 0 ]; then echo "RESULT: all 4 mutations caught"; else echo "RESULT: FAIL"; fi
exit "$failed"
