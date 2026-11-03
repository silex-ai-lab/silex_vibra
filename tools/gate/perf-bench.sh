#!/bin/bash
# Probe 4: compare --report cost between a baseline build and the branch on one frozen VIBRA_HOME.
# Usage: tools/gate/perf-bench.sh <baseline VibraApp> <branch VibraApp> <VIBRA_HOME> <VIBRA_NOW> [runs]
# The baseline is 60a61b8 with tools/gate/baseline-vibra-now.patch applied, built in release.
set -euo pipefail
base_bin=$1 branch_bin=$2 home=$3 now=$4 runs=${5:-3}
export TZ=America/Los_Angeles VIBRA_HOME=$home VIBRA_NOW=$now
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

timed() {
    /usr/bin/time -l "$@" > "$work/out" 2> "$work/time"
    local real rss
    real=$(awk '/ real /{print $1; exit}' "$work/time")
    rss=$(awk '/maximum resident set size/{print $1; exit}' "$work/time")
    echo "$real $rss"
}

base_read=$("$base_bin" --report | sed -n 's/^read-exact //p')
branch_read=$("$branch_bin" --report --json | python3 -I -B -c 'import json, sys; r = json.load(sys.stdin)["read"]; print("bytes=%d files=%d" % (r["bytes"], r["files"]))')
echo "baseline read: $base_read"
echo "branch read:   $branch_read"
if [ -z "$base_read" ] || [ "$base_read" != "$branch_read" ]; then
    echo "VOID: the two sides did not read the same bytes and files"; exit 2
fi

: > "$work/base"; : > "$work/branch"; : > "$work/base_bench"; : > "$work/branch_bench"
for i in $(seq "$runs"); do
    timed "$base_bin" --report >> "$work/base"
    timed "$branch_bin" --report >> "$work/branch"
    "$base_bin" --bench | awk '/cold refresh/{print $4}' | tr -d s >> "$work/base_bench"
    "$branch_bin" --bench | awk '/cold refresh/{print $4}' | tr -d s >> "$work/branch_bench"
done

python3 -I -B - "$work" <<'EOF'
import statistics, sys
w = sys.argv[1]
def cols(name):
    rows = [l.split() for l in open(f"{w}/{name}") if l.strip()]
    return [float(r[0]) for r in rows], [int(r[1]) for r in rows]
def one(name): return [float(l) for l in open(f"{w}/{name}") if l.strip()]
bt, br = cols("base"); nt, nr = cols("branch")
bb, nb = one("base_bench"), one("branch_bench")
def show(label, xs, unit): print(f"{label}: min {min(xs):.2f} median {statistics.median(xs):.2f} max {max(xs):.2f} {unit} (n={len(xs)})")
show("baseline --report time", bt, "s"); show("branch   --report time", nt, "s")
show("baseline peak RSS", [x / 2**20 for x in br], "MB"); show("branch   peak RSS", [x / 2**20 for x in nr], "MB")
show("baseline cold refresh", bb, "s"); show("branch   cold refresh", nb, "s")
fail = []
if statistics.median(nt) > 1.15 * statistics.median(bt): fail.append("--report time over baseline +15%")
if statistics.median(nb) > 1.15 * statistics.median(bb): fail.append("cold refresh over baseline +15%")
if statistics.median(nr) > statistics.median(br) + 50 * 2**20: fail.append("peak RSS over baseline +50 MB")
print("RESULT", "PASS" if not fail else "FAIL: " + "; ".join(fail))
sys.exit(1 if fail else 0)
EOF
