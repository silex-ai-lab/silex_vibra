#!/bin/bash
# Frozen-snapshot agreement run for --wait-stats (plan task 7). Prints counts, sizes, timings and diff
# results only; the snapshot lives in the caller's private directory and is deleted at the end.
# usage: agreement_run.sh <vibra binary> <repo> <private snapshot dir> <from> <to>
set -euo pipefail
bin="$1"; repo="$2"; snap="$3"; from="$4"; to="$5"
export TZ=America/Los_Angeles
rm -rf "$snap"; mkdir -p "$snap"
marker=$(mktemp); touch -t "$(date -j -v-2d -f %Y-%m-%d "$from" +%Y%m%d)0000" "$marker"
( cd "$HOME"
  find .claude/projects -name '*.jsonl' -newer "$marker" -print0 | xargs -0 -I{} rsync -a --relative {} "$snap/"
  find .codex/sessions -name 'rollout-*.jsonl' -newer "$marker" -print0 | xargs -0 -I{} rsync -a --relative {} "$snap/" )
rm -f "$marker"; chmod -R a-w "$snap"
echo "snapshot taken $(date -u +%FT%TZ): $(find "$snap" -type f | wc -l | tr -d ' ') files, $(find "$snap" -type f -exec stat -f %z {} + | awk '{s+=$1} END {print s}') bytes (sum of file sizes)"
out=$(mktemp -d)
for order in swift-oracle oracle-swift; do
  for who in ${order/-/ }; do
    start=$(python3 -c 'import time; print(time.time())')
    if [ "$who" = swift ]; then VIBRA_HOME="$snap" "$bin" --wait-stats --from "$from" --to "$to" > "$out/$order-$who.txt" 2> "$out/$order-$who.err"
    else VIBRA_HOME="$snap" python3 -I "$repo/tools/wait-oracle/wait_oracle.py" --from "$from" --to "$to" > "$out/$order-$who.txt" 2> "$out/$order-$who.err"; fi
    end=$(python3 -c 'import time; print(time.time())')
    printf '%s run %s: exit 0, %s lines, %.1f s wall, stderr: %s\n' "$order" "$who" "$(wc -l < "$out/$order-$who.txt" | tr -d ' ')" "$(python3 -c "print($end-$start)")" "$(cat "$out/$order-$who.err")"
  done
  if diff -q "$out/$order-swift.txt" "$out/$order-oracle.txt" >/dev/null; then echo "$order: swift and oracle identical"; else echo "$order: DIFFER"; diff "$out/$order-swift.txt" "$out/$order-oracle.txt" | head -20; fi
done
diff -q "$out/swift-oracle-swift.txt" "$out/oracle-swift-swift.txt" >/dev/null && echo "swift run 1 == swift run 2"
VIBRA_NOW= "$bin" --wait-stats --from "$from" --to "$to" > "$out/live-swift.txt" 2>/dev/null
python3 -I "$repo/tools/wait-oracle/wait_oracle.py" --from "$from" --to "$to" > "$out/live-oracle.txt"
diff -q "$out/live-swift.txt" "$out/live-oracle.txt" >/dev/null && echo "live: swift and oracle identical" || echo "live: DIFFER"
echo "live vs snapshot (diagnostic):"; diff "$out/swift-oracle-swift.txt" "$out/live-swift.txt" || true
cp "$out/swift-oracle-swift.txt" "$repo/docs/research/2026-11-12/pilot/wait-stats-$from"_"$to.txt"
chmod -R u+w "$snap"; rm -rf "$snap" "$out"; echo "snapshot deleted $(date -u +%FT%TZ)"
