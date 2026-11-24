#!/bin/bash
# usage: analysis/latency_inject.sh [tag]
#   -O0 mechanism (paper 5.4): adds k dependent 3-cycle multiplies to the pc chain of each
#   variant (analysis/latency_inject.py chain) and, as control, the same multiplies off any
#   chain (ctrl).  Cycles growing by ~3 per executed multiply from k = 1 = the pc chain is
#   the critical path; flat = it has slack.  All binaries are built before measuring.
#   env: CPU=3 ROUNDS=3 NLIMIT=1000000 KS="1 2 3 4 6 8" OPT=-O0 FIXED=1
#        SITE=pc (pc += 3 updates) or val (VM register values stored to ram[]); see the .py
#        VARIANTS="cgoto_gcc cgoto_clang musttail_gcc musttail_clang"
# output: results/analysis/latency_inject_<tag>.txt  (SITE=val: latency_inject_val_<tag>.txt)
#   round variant mode k cycles instructions        (mode base: unmodified; split: see .py)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TAG=${1:-$(hostname 2>/dev/null || echo host)}
CPU=${CPU:-3}; ROUNDS=${ROUNDS:-3}; NLIMIT=${NLIMIT:-1000000}; KS=${KS:-"1 2 3 4 6 8"}
OPT=${OPT:--O0}; FIXED=${FIXED:-1}; SITE=${SITE:-pc}
VARIANTS=${VARIANTS:-"cgoto_gcc cgoto_clang musttail_gcc musttail_clang"}
OUT=results/analysis/latency_inject_${SITE/pc/}${SITE:+_}$TAG.txt; OUT=${OUT/inject__/inject_}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
P=""; [ -d /sys/devices/cpu_core ] && P=cpu_core/
EV="${P:+${P}}cycles${P:+/},${P:+${P}}instructions${P:+/}"

NT=/sys/devices/system/cpu/intel_pstate/no_turbo
GOV=/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor
if [ "$FIXED" = 1 ] && { [ "$(cat $NT)" != 1 ] || [ "$(cat $GOV)" != performance ]; }; then
    echo "set no_turbo=1 and the performance governor first (FIXED=0 to skip)" >&2; exit 1
fi

# build everything first
: > "$W/list"
for vc in $VARIANTS; do
    v=${vc%_*}; cc=${vc##*_}
    sed "s/10000001/$((NLIMIT + 1))/" src/$v.c > "$W/$v.c"
    $cc $OPT -masm=intel -S -o "$W/$vc.s" "$W/$v.c"
    $cc $OPT "$W/$vc.s" -o "$W/${vc}_base_0"; echo "$vc base 0" >> "$W/list"
    if [ "$SITE" = pc ] && grep -qE 'add\s+QWORD PTR -[0-9]+\[rbp\], 3$' "$W/$vc.s"; then
        python3 -I analysis/latency_inject.py "$W/$vc.s" "$W/p.s" split 0
        $cc $OPT "$W/p.s" -o "$W/${vc}_split_0"; echo "$vc split 0" >> "$W/list"
    fi
    for mode in chain ctrl; do for k in $KS; do
        python3 -I analysis/latency_inject.py "$W/$vc.s" "$W/p.s" $mode $k $SITE
        $cc $OPT "$W/p.s" -o "$W/${vc}_${mode}_$k"; echo "$vc $mode $k" >> "$W/list"
    done; done
done
expect=$("$W/$(head -1 "$W/list" | tr ' ' _)")

echo "# round variant mode k cycles instructions  cpu=$CPU opt=$OPT nlimit=$NLIMIT site=$SITE $(date -Is)" > "$OUT"
for r in $(seq 1 $ROUNDS); do
    shuf "$W/list" | while read -r vc mode k; do
        sleep 0.5
        res=$(taskset -c $CPU perf stat -x, -o "$W/perf" -e "$EV" "$W/${vc}_${mode}_$k")
        [ "$res" = "$expect" ] || { echo "WRONG RESULT $vc $mode $k: $res" >&2; continue; }
        awk -F, -v p="$r $vc $mode $k" '/cycles/{c=$1} /instructions/{i=$1} END{print p, c, i}' "$W/perf" | tee -a "$OUT"
    done
done
