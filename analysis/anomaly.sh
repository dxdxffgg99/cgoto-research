#!/bin/bash
# usage: analysis/anomaly.sh [tag]
#   Experiments on the clang -O3 musttail misprediction anomaly (microbenchmark).
#   Needs build/O2 and build/O3 from bench/build.sh. Run on an otherwise idle machine.
#   1. split:  mispredictions split into conditional vs indirect branches (3 runs each)
#   2. profile: precise (PEBS) sampling of mispredicted branches per instruction
#   3. sweep:  shift the jeven/jnei handlers by 0..31 bytes and re-measure
#   env: CPU=3  STEPS="split profile sweep"   output: results/analysis/*_<tag>.txt
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TAG=${1:-$(hostname 2>/dev/null || echo host)}
export CPU=${CPU:-3}
STEPS=${STEPS:-"split profile sweep"}
has() { [[ " $STEPS " == *" $1 "* ]]; }
A=results/analysis
mkdir -p "$A"

P=""; [ -d /sys/devices/cpu_core ] && P=cpu_core/
ev() { [ -n "$P" ] && echo "$P$1/" || echo "$1"; }

# 1. conditional vs indirect mispredictions
if has split; then
out=$A/misp_split_$TAG.txt
echo "# binary round cond_misp indirect_misp all_misp cycles" > "$out"
for r in 1 2 3; do
    for b in O2/musttail_clang O3/musttail_clang O3/mtnopie_clang O3/mtargs_clang O3/cgoto_clang O3/musttail_gcc O3/switch_gcc; do
        sleep 3
        taskset -c $CPU perf stat -x, -e "$(ev br_misp_retired.cond),$(ev br_misp_retired.indirect),$(ev br_misp_retired.all_branches),$(ev cycles)" \
            "build/$b" 2>&1 >/dev/null \
            | awk -F, -v b=$b -v r=$r '/\.cond/{c=$1} /\.indirect/{i=$1} /all_branches/{a=$1} /cycles/{y=$1} END{print b, r, c, i, a, y}' \
            | tee -a "$out"
    done
done
fi

# 2. which instructions mispredict
if has profile; then
for b in O2/musttail_clang O3/musttail_clang O3/mtnopie_clang O3/cgoto_clang; do
    OUT=$A/misp_$(echo $b | tr / _)_$TAG.txt analysis/misp_profile.sh "build/$b" > /dev/null
done
fi

# 3. code placement sweeps
if has sweep; then
OUT=$A/sweep_musttail_clang-O3_$TAG.txt        analysis/layout_sweep.sh src/musttail.c clang -O3
OUT=$A/sweep_musttail_clang-O2_$TAG.txt        analysis/layout_sweep.sh src/musttail.c clang -O2
OUT=$A/sweep_musttail_clang-O3-nopie_$TAG.txt  analysis/layout_sweep.sh src/musttail.c clang -O3 -fno-pie -no-pie
fi
echo "anomaly experiments done ($TAG)"
