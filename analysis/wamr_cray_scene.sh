#!/bin/bash
# usage: analysis/wamr_cray_scene.sh <bin_dir> <out_file>
#   WAMR c-ray with its scene (paper 5.3, threats).  c-ray reads the scene from stdin and
#   targets/wamr/run.sh gave it none, so the "cray" numbers of the WAMR runs rendered an
#   empty scene.  This runs every iwasm_* in <bin_dir> on both inputs in one session:
#     cray       stdin /dev/null (as the earlier runs, 9.5G instructions)
#     crayscene  stdin = tests/standalone/c-ray/scene (the intended input, ~71G)
#   Order shuffled every round; every output must match the first output for its input.
#   env: ROUNDS=5 CPU=3 MIN_SLEEP=3 COOL=50000 MAX_WAIT=90 FIXED=1
# raw line (as targets/wamr/run.sh): round benchmark variant time_s cycles instructions
#   branches branch_misses ghz temp_before temp_after loadavg
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B=$(cd "$1" && pwd); OUT=$2
D=$ROOT/third_party/wamr/tests/standalone/c-ray
ROUNDS=${ROUNDS:-5}; CPU=${CPU:-3}; MIN_SLEEP=${MIN_SLEEP:-3}; COOL=${COOL:-50000}; MAX_WAIT=${MAX_WAIT:-90}
FIXED=${FIXED:-1}
HW=""
for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name)" = coretemp ] && HW=$h; done
temp() { [ -n "$HW" ] && cat $HW/temp*_input | sort -n | tail -1 || echo 0; }
P=""; [ -d /sys/devices/cpu_core ] && P=cpu_core/
ev() { [ -n "$P" ] && echo "$P$1/" || echo "$1"; }
EVENTS="task-clock,$(ev cycles),$(ev instructions),$(ev branches),$(ev branch-misses)"
NT=/sys/devices/system/cpu/intel_pstate/no_turbo
GOV=/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor
if [ "$FIXED" = 1 ] && { [ "$(cat $NT)" != 1 ] || [ "$(cat $GOV)" != performance ]; }; then
    echo "set no_turbo=1 and the performance governor first (FIXED=0 to skip)" >&2; exit 1
fi
cooldown() {
    sleep $MIN_SLEEP; local w=$MIN_SLEEP
    while [ "$(temp)" -gt $COOL ] && [ $w -lt $MAX_WAIT ]; do sleep 1; w=$((w + 1)); done
}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
declare -A REF
: > "$OUT"
for i in $(seq 1 $ROUNDS); do
    for job in $( (cd "$B" && for v in iwasm_*; do echo "$v:cray"; echo "$v:crayscene"; done) | shuf); do
        v=${job%%:*}; bench=${job#*:}
        [ $bench = crayscene ] && IN=$D/scene || IN=/dev/null
        cooldown
        t0=$(temp)
        fp=$(cd "$D" && taskset -c $CPU perf stat -x, -o "$TMP/perf" -e "$EVENTS" \
                "$B/$v" c_ray.wasm -s 1600x1200 < "$IN" 2> "$TMP/err" | md5sum | cut -c1-12)
        t1=$(temp)
        [ -z "${REF[$bench]:-}" ] && REF[$bench]=$fp
        if [ "$fp" != "${REF[$bench]}" ]; then echo "WRONG $bench $v: $fp != ${REF[$bench]}" >&2; continue; fi
        awk -F, -v i=$i -v b=$bench -v vn=$v -v t0=$t0 -v t1=$t1 -v la=$(cut -d' ' -f1 /proc/loadavg) '
            $3 ~ /task-clock/ { tc=$1 } $3 ~ /cycles/ { c=$1 } $3 ~ /instructions/ { n=$1 }
            $3 ~ /branches/ && $3 !~ /misses/ { br=$1 } $3 ~ /branch-misses/ { m=$1 }
            END { printf "%d %s %s %.6f %s %s %s %s %.3f %d %d %s\n", i, b, vn, tc/1000, c, n, br, m, c/(tc*1e6), t0/1000, t1/1000, la }
        ' "$TMP/perf" | tee -a "$OUT"
    done
done
