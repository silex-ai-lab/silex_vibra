#!/bin/bash
# Each mutation of an incident rule must be caught by the incident tests.
# Usage: tools/gate/mutate-incidents.sh <repo>
# Runs in a throwaway worktree of HEAD and never touches the caller's checkout.
set -uo pipefail
repo=$(cd "$1" && pwd)
work=$(mktemp -d)
trap 'cd /; git -C "$repo" worktree remove --force "$work" >/dev/null 2>&1; rm -rf "$work"' EXIT
git -C "$repo" worktree add --detach "$work" HEAD >/dev/null 2>&1 || { echo "ERROR: could not create worktree"; exit 2; }
cd "$work" || exit 2

extractor=Sources/VibraCore/Incidents/IncidentExtractor.swift
table=Sources/VibraCore/Incidents/CredentialTable.swift
monitor=Sources/VibraCore/Incidents/IncidentMonitor.swift
store=Sources/VibraCore/Incidents/IncidentStore.swift
usage=Sources/VibraCore/Incidents/VendorUsage.swift
report=Sources/VibraCore/Incidents/VendorReport.swift
json=Sources/VibraCore/Incidents/IncidentJSON.swift
failed=0

mutate() {
    local label=$1 file=$2 old=$3 new=$4
    local hits
    hits=$(grep -cF -- "$old" "$file")
    if [ "$hits" != 1 ]; then
        echo "ERROR $label: expected one line matching, found $hits"
        failed=1
        return
    fi
    cp "$file" "$file.orig"
    perl -i -pe 'BEGIN { ($o, $n) = splice(@ARGV, 0, 2) } s/\Q$o\E/$n/' "$old" "$new" "$file"
    local output status
    output=$(swift run --build-system native VibraTests --filter 'Incident|VendorUsage|VendorReport' 2>&1)
    status=$?
    mv "$file.orig" "$file"
    if printf '%s' "$output" | grep -qE '\.swift:[0-9]+:[0-9]+: error:'; then
        echo "ERROR $label: the mutant did not compile"
        failed=1
    elif [ "$status" -ne 0 ]; then
        echo "CAUGHT $label"
    else
        echo "MISSED $label"
        failed=1
    fi
}

mutate "a later write no longer reopens" "$monitor" 'return incident.completedAt > date' 'return false'
mutate "deliver even when the commit failed" "$monitor" 'guard await store.commit(watermark: newest) else { return 0 }' '_ = await store.commit(watermark: newest)'
mutate "the store may lower the watermark" "$store" 'if let previous, watermark <= previous { return true }' ''
mutate "shrunk files are not re-read" "$monitor" '|| source.size < state.lastSize' ''
mutate "every later write notifies" "$monitor" 'return previous <= date' 'return true'
mutate "a stale denial blocks a fresh one" "$extractor" 'guard denials[index].stale else { return }' 'guard !denials[index].stale else { return }'
mutate "empty roots keep the old roots" "$extractor" 'if let values = payload["workspace_roots"] as? [String] { roots = values }' 'if let values = payload["workspace_roots"] as? [String], !values.isEmpty { roots = values }'
mutate "a zero row loses its key" "$usage" 'if let key, !key.isEmpty {' 'if sum > 0, let key, !key.isEmpty {'
mutate "a re-import keeps old findings" "$monitor" 'for id in scope { vendor[id] = nil }' ''
mutate "a discarded import still lands" "$monitor" 'guard isCurrent() else { return false }' ''
mutate "a read-only store renames" "$store" 'if readOnly { return (.empty, false) }' ''
mutate "same-size rewrites are not re-read" "$monitor" '|| (source.size == state.lastSize && source.modified != state.lastModified)' ''
mutate "a redirect target counts as read" "$table" 'guard let candidates = operands(withoutRedirects(Array(words.dropFirst())), reader) else { return nil }' 'guard let candidates = operands(Array(words.dropFirst()), reader) else { return nil }'
mutate "cp destinations count as read" "$table" 'counted = Set(positional.dropLast())' 'counted = Set(positional)'
mutate "failed writes are findings" "$extractor" 'if let family = call.writeFamily, !isError, let toolClass = call.toolClass {' 'if let family = call.writeFamily, let toolClass = call.toolClass {'
mutate "injected records count as human" "$extractor" 'record["isMeta"] as? Bool != true,' ''
mutate "a lease exempts a plus refspec" "$extractor" 'if word.hasPrefix("+"), word.count > 1 { force = true }' ''
mutate "background counts as finished" "$extractor" 'return call.soleForeground && !call.backgrounded && !isError && finished' 'return call.soleForeground && !isError && finished'
mutate "write anchor is per call" "$extractor" 'at: call.at, completedAt: completedAt, anchor: IncidentPaths.writeAnchor(family))' 'at: call.at, completedAt: completedAt, anchor: id)'
mutate "OpenAI double-counts cached input" "$usage" 'return input + output' 'return input + output + 400'
mutate "the current UTC day is compared" "$usage" 'guard let earliest, entry.day >= earliest, entry.day != today else {' 'guard let earliest, entry.day >= earliest else {'
mutate "the draft carries the hashed id" "$report" 'lines.append("OS: \(osVersion)")' 'lines.append("OS: \(osVersion) \(incident.id.hex)")'
mutate "JSON omits the answer" "$json" 'disposition = DispositionOutput(state: row.disposition.state, at: row.disposition.date)' 'disposition = DispositionOutput(state: "open", at: nil)'

[ "$failed" = 0 ] && echo "all mutations caught"
exit "$failed"
