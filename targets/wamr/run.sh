#!/bin/bash
# usage: targets/wamr/run.sh [bin_dir] [out_file]
#   runs the WAMR standalone wasm programs on every iwasm_* binary in bin_dir
#   env: ROUNDS=5 CPU=3 COOL=50000 MIN_SLEEP=3 MAX_WAIT=90 FIXED=0 GHZ=(auto) TOL=0.02 TRIES=3
#        BENCHMARKS="coremark nbody"  VARIANTS="iwasm_cgoto_gcc iwasm_tail_gcc"
# raw line: round benchmark variant time_s cycles instructions branches branch_misses ghz temp_before temp_after loadavg
# Every run's output (timing lines removed) must match the first output seen for that
# benchmark, otherwise the run is reported as FAIL and not recorded.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
B=$(cd "${1:-$ROOT/build/wamr/bin}" && pwd)
OUT=${2:-$ROOT/results/wamr_raw.txt}
W=$ROOT/third_party/wamr/tests/standalone
ROUNDS=${ROUNDS:-5}; CPU=${CPU:-3}
COOL=${COOL:-50000}; MIN_SLEEP=${MIN_SLEEP:-3}; MAX_WAIT=${MAX_WAIT:-90}
FIXED=${FIXED:-0}; TOL=${TOL:-0.02}; TRIES=${TRIES:-3}

# name | dir | iwasm args | output lines to compare (grep -E; "-" = discard output, check exit code only)
CASES="
coremark|coremark|coremark_wasi_nofp.wasm 0x0 0x0 0x66 2000|crc|^Iterations +:
nbody|nbody|nbody.wasm 3000000|.
fannkuch|fannkuch-redux|fannkuch_redux.wasm 10|.
binarytrees|binary-trees|binary_trees.wasm 14|.
fasta|fasta|fasta.wasm 2000000|-
cray|c-ray|c_ray.wasm -s 1600x1200|-
hashset|hashset|HashSet.wasm|^[^T]
raymarcher|raymarcher|raymarcher.wasm|.
"
declare -A DIR ARGS KEEP
ALL=""
while IFS='|' read -r name dir args keep; do
    [ -z "$name" ] && continue
    DIR[$name]=$dir; ARGS[$name]=$args; KEEP[$name]=$keep; ALL="$ALL $name"
done <<< "$CASES"
BENCHMARKS=${BENCHMARKS:-$ALL}
VARIANTS=${VARIANTS:-$(cd "$B" && ls iwasm_* | tr '\n' ' ')}

HW=""
for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name)" = coretemp ] && HW=$h; done
temp() { [ -n "$HW" ] && cat $HW/temp*_input | sort -n | tail -1 || echo 0; }

P=""; [ -d /sys/devices/cpu_core ] && P=cpu_core/
ev() { [ -n "$P" ] && echo "$P$1/" || echo "$1"; }
EVENTS="task-clock,$(ev cycles),$(ev instructions),$(ev branches),$(ev branch-misses)"

NT=/sys/devices/system/cpu/intel_pstate/no_turbo
GOV=/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor

cooldown() {
    sleep $MIN_SLEEP
    local w=$MIN_SLEEP
    while [ $(temp) -gt $COOL ] && [ $w -lt $MAX_WAIT ]; do sleep 1; w=$((w+1)); done
}

check_settings() {
    [ "$FIXED" = 1 ] || return 0
    while [ "$(cat $NT)" != 1 ] || [ "$(cat $GOV)" != performance ]; do
        echo "WAIT settings changed: no_turbo=$(cat $NT) gov=$(cat $GOV)" >&2; sleep 10
    done
}

if [ -z "${GHZ:-}" ]; then
    GHZ=$(for k in 1 2 3; do
        sleep $MIN_SLEEP
        taskset -c $CPU perf stat -x, -e task-clock,$(ev cycles) awk 'BEGIN{for(i=0;i<5e7;i++);}' 2>&1 >/dev/null \
            | awk -F, '/task-clock/{tc=$1} /cycles/{c=$1} END{printf "%.3f\n", c/(tc*1e6)}'
    done | sort -n | sed -n 2p)
fi
echo "cpu$CPU GHZ=$GHZ (tol $TOL)" >&2

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
declare -A FP   # first output fingerprint per benchmark

measure() {
    local bench=$1 v=$2 i=$3 t0 t1 rc fp
    t0=$(temp)
    if [ "${KEEP[$bench]}" = "-" ]; then
        (cd "$W/${DIR[$bench]}" && taskset -c $CPU perf stat -o "$TMP/perf" -e $EVENTS \
            "$B/$v" ${ARGS[$bench]} > /dev/null 2> "$TMP/err"); rc=$?
        fp="rc=$rc"
    else
        (cd "$W/${DIR[$bench]}" && taskset -c $CPU perf stat -o "$TMP/perf" -e $EVENTS \
            "$B/$v" ${ARGS[$bench]} > "$TMP/out" 2> "$TMP/err"); rc=$?
        fp="rc=$rc $(grep -E "${KEEP[$bench]}" "$TMP/out" | md5sum | cut -c1-12)"
    fi
    t1=$(temp)
    echo "$fp" > "$TMP/fp"   # runs in a subshell: the caller compares fingerprints
    if [ $rc -ne 0 ]; then
        echo "FAIL $bench $v: exit $rc $(head -c 200 "$TMP/err")" >&2; return 1
    fi
    awk -v b=$bench -v vn=$v -v i=$i -v t0=$t0 -v t1=$t1 -v la=$(cut -d' ' -f1 /proc/loadavg) '
        /task-clock/   { tc=$1; next }
        /time elapsed/ { t=$1; next }
        NF>=2 { n=$2; sub(/^cpu_core\//,"",n); sub(/\/?:?u$/,"",n); v[n]=$1 }
        END {
            for (x in v) gsub(",","",v[x]); gsub(",","",tc)
            printf "%d %s %s %s %s %s %s %s %.3f %d %d %s\n", i, b, vn, t, v["cycles"], v["instructions"],
                v["branches"], v["branch-misses"], v["cycles"]/(tc*1e6), t0/1000, t1/1000, la
        }' "$TMP/perf"
}

mkdir -p "$(dirname "$OUT")"; : > "$OUT"
for i in $(seq $ROUNDS); do
    for pair in $(for b in $BENCHMARKS; do for v in $VARIANTS; do echo "$b:$v"; done; done | shuf); do
        bench=${pair%%:*}; v=${pair#*:}
        for try in $(seq $TRIES); do
            check_settings; cooldown
            line=$(measure $bench $v $i) || break
            fp=$(cat "$TMP/fp")
            if [ -z "${FP[$bench]:-}" ]; then FP[$bench]=$fp
            elif [ "${FP[$bench]}" != "$fp" ]; then
                echo "FAIL $bench $v: output differs ($fp vs ${FP[$bench]})" >&2; break
            fi
            g=$(echo "$line" | awk '{print $9}')
            if awk -v g=$g -v e=$GHZ -v t=$TOL 'BEGIN{d=(g-e)/e; exit !(d<t && d>-t)}'; then
                echo "$line" | tee -a "$OUT"; break
            fi
            echo "DISCARD (GHz=$g) $line" >&2
        done
    done
done
