#!/bin/bash
# usage: analysis/layout_sensitivity.sh [tag]
#   For every dispatch variant of the microbenchmark, measure the original layout and
#   SEEDS random layouts (analysis/perturb.py: unexecuted padding before non-fallthrough
#   labels), recording cycles, instructions and conditional / indirect mispredictions.
#   Run on an otherwise idle machine with turbo off.
#   env: CPU=3 SEEDS=20 OPTS="-O2 -O3" MAXPAD=63 PAD_MODE=fixed (orig: the layouts measured before 2026-11-23)
# output: results/analysis/layout_<tag>.txt
#   opt variant seed cycles instructions cond_misp indirect_misp all_misp
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TAG=${1:-$(hostname 2>/dev/null || echo host)}
CPU=${CPU:-3}; SEEDS=${SEEDS:-20}; OPTS=${OPTS:-"-O2 -O3"}; MAXPAD=${MAXPAD:-63}; PAD_MODE=${PAD_MODE:-fixed}
OUT=results/analysis/layout_$TAG.txt
mkdir -p results/analysis
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

P=""; [ -d /sys/devices/cpu_core ] && P=cpu_core/
ev() { [ -n "$P" ] && echo "$P$1/" || echo "$1"; }
EVENTS="$(ev cycles),$(ev instructions),$(ev br_misp_retired.cond),$(ev br_misp_retired.indirect),$(ev br_misp_retired.all_branches)"

# variant -> source, extra flags
declare -A SRC=( [switch]=src/switch.c [cgoto]=src/cgoto.c [musttail]=src/musttail.c
                 [mtnopie]=src/musttail.c [mtargs]=src/musttail_args.c )
declare -A FLG=( [mtnopie]="-fno-pie -no-pie" )

echo "# opt variant seed cycles instructions cond_misp indirect_misp all_misp  cpu=$CPU maxpad=$MAXPAD $(date -Is)" > "$OUT"
for opt in $OPTS; do
  for cc in gcc clang; do
    for v in switch cgoto musttail mtnopie mtargs; do
      f=${FLG[$v]:-}
      $cc $opt $f -S -o "$W/base.s" "${SRC[$v]}"
      for seed in $(seq 0 $SEEDS); do
        python3 -I analysis/perturb.py "$W/base.s" "$W/p.s" $seed $MAXPAD $PAD_MODE 2>/dev/null
        $cc $opt $f "$W/p.s" -o "$W/p"
        sleep 2
        res=$(taskset -c $CPU perf stat -x, -o "$W/perf" -e "$EVENTS" "$W/p")
        [ "$res" = 1552724831 ] || { echo "WRONG RESULT $opt ${v}_$cc seed $seed: $res" >&2; continue; }
        awk -F, -v o=$opt -v n=${v}_$cc -v s=$seed '
            /cycles/{c=$1} /instructions/{i=$1} /\.cond/{mc=$1} /\.indirect/{mi=$1} /all_branches/{ma=$1}
            END{print o, n, s, c, i, mc, mi, ma}' "$W/perf" | tee -a "$OUT"
      done
    done
  done
done
