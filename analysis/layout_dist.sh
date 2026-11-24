#!/bin/bash
# usage: analysis/layout_dist.sh [tag]
#   Larger-sample version of layout_sensitivity.sh: many random layouts per variant,
#   shorter runs (Collatz limit NLIMIT instead of 10,000,000), and binaries of layouts
#   whose indirect-branch mispredictions explode are kept for analysis/catastrophe.sh.
#   env: CPU=3 SEEDS=100 OPTS=-O2 NLIMIT=2000000 MAXPAD=63 THRESH=10000000 PAD_MODE=fixed
#        VARIANTS="cgoto_gcc cgoto_clang switch_gcc switch_clang musttail_gcc musttail_clang mtargs_gcc mtargs_clang"
# output: results/analysis/layoutdist_<tag>.txt  (opt variant seed cycles instructions cond_misp indirect_misp all_misp)
#         results/analysis/catastrophe_<tag>/<opt>_<variant>_<seed>   (kept binaries)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TAG=${1:-$(hostname 2>/dev/null || echo host)}
CPU=${CPU:-3}; SEEDS=${SEEDS:-100}; OPTS=${OPTS:--O2}; NLIMIT=${NLIMIT:-2000000}
MAXPAD=${MAXPAD:-63}; THRESH=${THRESH:-10000000}; PAD_MODE=${PAD_MODE:-fixed}   # perturb.py mode (orig: layouts measured before 2026-11-23)
VARIANTS=${VARIANTS:-"cgoto_gcc cgoto_clang switch_gcc switch_clang musttail_gcc musttail_clang mtargs_gcc mtargs_clang"}
OUT=results/analysis/layoutdist_$TAG.txt
KEEP=results/analysis/catastrophe_$TAG
mkdir -p results/analysis "$KEEP"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

P=""; [ -d /sys/devices/cpu_core ] && P=cpu_core/
ev() { [ -n "$P" ] && echo "$P$1/" || echo "$1"; }
EVENTS="$(ev cycles),$(ev instructions),$(ev br_misp_retired.cond),$(ev br_misp_retired.indirect),$(ev br_misp_retired.all_branches)"

declare -A SRC=( [switch]=src/switch.c [cgoto]=src/cgoto.c [musttail]=src/musttail.c
                 [mtnopie]=src/musttail.c [mtargs]=src/musttail_args.c )
declare -A FLG=( [mtnopie]="-fno-pie -no-pie" )

echo "# opt variant seed cycles instructions cond_misp indirect_misp all_misp  cpu=$CPU nlimit=$NLIMIT maxpad=$MAXPAD pad_mode=$PAD_MODE $(date -Is)" > "$OUT"
for opt in $OPTS; do
  for vc in $VARIANTS; do
    v=${vc%_*}; cc=${vc##*_}; f=${FLG[$v]:-}
    # same program with a smaller Collatz limit (the JNEI bound in ram[])
    grep -q '10000001' "${SRC[$v]}" || { echo "limit constant not found in ${SRC[$v]}" >&2; exit 1; }
    sed "s/10000001/$((NLIMIT + 1))/" "${SRC[$v]}" > "$W/src.c"
    $cc $opt $f -S -o "$W/base.s" "$W/src.c"
    expect=""
    for seed in $(seq 0 $SEEDS); do
      python3 -I analysis/perturb.py "$W/base.s" "$W/p.s" $seed $MAXPAD $PAD_MODE 2>/dev/null
      $cc $opt $f "$W/p.s" -o "$W/p"
      sleep 1
      res=$(taskset -c $CPU perf stat -x, -o "$W/perf" -e "$EVENTS" "$W/p")
      [ -z "$expect" ] && expect=$res          # seed 0 = unperturbed reference
      [ "$res" = "$expect" ] || { echo "WRONG RESULT $opt $vc seed $seed: $res != $expect" >&2; continue; }
      line=$(awk -F, -v o=$opt -v n=$vc -v s=$seed '
          /cycles/{c=$1} /instructions/{i=$1} /\.cond/{mc=$1} /\.indirect/{mi=$1} /all_branches/{ma=$1}
          END{print o, n, s, c, i, mc, mi, ma}' "$W/perf")
      echo "$line" | tee -a "$OUT"
      ind=$(echo "$line" | awk '{print $7}')
      [ "$ind" -gt "$THRESH" ] && cp "$W/p" "$KEEP/${opt#-}_${vc}_$seed"
    done
  done
done
