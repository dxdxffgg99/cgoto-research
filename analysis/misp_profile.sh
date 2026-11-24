#!/bin/bash
# usage: analysis/misp_profile.sh <binary> [name]
#   Samples retired mispredicted branches with precise IPs (PEBS) and prints, per
#   handler function, the instructions that mispredict (perf annotate).
#   env: CPU=3 PERIOD=10007 OUT=results/analysis/misp_<name>.txt
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
NAME=${2:-$(basename "$(dirname "$1")")_$(basename "$1")}
CPU=${CPU:-3}; PERIOD=${PERIOD:-10007}
OUT=${OUT:-$ROOT/results/analysis/misp_$NAME.txt}
mkdir -p "$(dirname "$OUT")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

EV=br_misp_retired.all_branches:upp
[ -d /sys/devices/cpu_core ] && EV=cpu_core/br_misp_retired.all_branches/upp

taskset -c $CPU perf record -q -e "$EV" -c $PERIOD -o "$W/perf.data" "$BIN" > /dev/null 2> "$W/err" \
    || { echo "perf record failed: $(cat "$W/err")" >&2; exit 1; }
{
    echo "# $BIN  event=$EV period=$PERIOD  $(date -Is)"
    echo "## mispredictions by function"
    perf report -i "$W/perf.data" --stdio --sort symbol 2>/dev/null | grep -vE '^#|^$'
    echo "## mispredictions by instruction"
    perf report -i "$W/perf.data" --stdio --sort symbol,srcline --no-children -F overhead,sym 2>/dev/null \
        | grep -vE '^#|^$' | head -40
    for fn in jeven jnei addi loadi mov muli shri; do
        echo "## annotate $fn"
        perf annotate -i "$W/perf.data" --stdio -s "$fn" 2>/dev/null | grep -vE '^\s*$' | head -40
    done
} > "$OUT"
cat "$OUT"
