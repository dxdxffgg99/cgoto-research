#!/bin/bash
# usage: analysis/topdown.sh <out_file> <binary>...
#   Top-down (TMA) and front-end / memory counters for each binary (paper 5.3, task 2).
#   A binary named lua_* runs every AWFY benchmark; any other binary runs without arguments
#   (the src/*.c microbenchmark).  Each event group is a separate perf stat run so no
#   group is multiplexed; ratios use the counts of one run.
#   env: ROUNDS=2 CPU=3 MIN_SLEEP=1 FIXED=1 BENCHMARKS="..."
#        TMA="TopdownL1,TopdownL2"  metric groups, one perf run per space-separated item
#        (i9: one run covers L1+L2; Tiger Lake needs "TopdownL1 TopdownL2")
# output line: round bench variant group event value pct_counted
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=$1; shift
set -- $(realpath "$@")
AWFY=$ROOT/third_party/awfy/benchmarks
ROUNDS=${ROUNDS:-2}; CPU=${CPU:-3}; MIN_SLEEP=${MIN_SLEEP:-1}; FIXED=${FIXED:-1}
TMA=${TMA:-"TopdownL1,TopdownL2"}
declare -A SIZE=(
    [DeltaBlue]=12000 [Richards]=100 [Json]=100 [CD]=250 [Havlak]=1500
    [Bounce]=1500 [List]=1500 [Mandelbrot]=500 [NBody]=250000 [Permute]=1000
    [Queens]=1000 [Sieve]=3000 [Storage]=1000 [Towers]=600
)
BENCHMARKS=${BENCHMARKS:-"DeltaBlue Richards Json CD Havlak Bounce List Mandelbrot NBody Permute Queens Sieve Storage Towers"}
NORAND="setarch $(uname -m) -R"

P=""; CT=""; [ -d /sys/devices/cpu_core ] && { P=cpu_core/; CT="--cputype core"; }
ev() { local e out=""; for e in ${1//,/ }; do out="$out,${P:+$P}$e${P:+/}"; done; echo "${out#,}"; }
GROUPS_EV=(
    "fe:$(ev cycles,instructions,idq.dsb_uops,idq.mite_uops,idq.ms_uops,uops_issued.any)"
    "stall:$(ev cycles,icache_data.stalls,baclears.any,int_misc.clear_resteer_cycles,dsb2mite_switches.penalty_cycles)"
    "mem:$(ev cycles,br_inst_retired.indirect,br_misp_retired.indirect,mem_inst_retired.all_loads,mem_inst_retired.all_stores)"
)

NT=/sys/devices/system/cpu/intel_pstate/no_turbo
GOV=/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor
check_settings() {
    [ "$FIXED" = 1 ] || return 0
    while [ "$(cat $NT)" != 1 ] || [ "$(cat $GOV)" != performance ]; do
        echo "WAIT settings changed: no_turbo=$(cat $NT) gov=$(cat $GOV)" >&2; sleep 10
    done
}

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# run <bin> <bench> <perf args...>: perf -x, output in $TMP/perf
run() {
    local bin=$1 bench=$2; shift 2
    if [ "$bench" = - ]; then
        taskset -c $CPU perf stat -x, -o "$TMP/perf" "$@" $NORAND "$bin" > "$TMP/out" 2>&1
    else
        (cd "$AWFY" && LUA_PATH="Lua/?.lua;;" taskset -c $CPU perf stat -x, -o "$TMP/perf" "$@" \
            $NORAND "$bin" Lua/harness.lua $bench 1 ${SIZE[$bench]} > "$TMP/out" 2>&1)
        grep -q 'runtime:' "$TMP/out" || { echo "FAIL $bench $bin: $(head -c 200 "$TMP/out")" >&2; return 1; }
    fi
}

# emit <round> <bench> <variant> <group>: one line per event count and per metric
emit() {
    awk -F, -v pre="$1 $2 $3 $4" '
        /^#/ || NF < 3 { next }
        $1 ~ /^[0-9.]+$/ { n=$3; sub(/^cpu_core\//,"",n); sub(/\/u?$/,"",n); sub(/:u$/,"",n); n=tolower(n)
                           print pre, n, $1, $5 }
        $6 != "" && $7 != "" { m=$7; sub(/^%? */,"",m); print pre, m, $6, "-" }' "$TMP/perf"
}

mkdir -p "$(dirname "$OUT")"; : > "$OUT"
jobs_list() {
    local b bench
    for b in "$@"; do
        case $(basename "$b") in
            lua_*) for bench in $BENCHMARKS; do echo "$b:$bench"; done ;;
            *) echo "$b:-" ;;
        esac
    done
}
for i in $(seq $ROUNDS); do
    for job in $(jobs_list "$@" | shuf); do
        b=${job%:*}; bench=${job##*:}; v=$(basename "$b")
        [ "$bench" = - ] && v="$(basename "$(dirname "$b")")_$v"   # micro: O0_cgoto_gcc
        for g in $TMA; do
            check_settings; sleep $MIN_SLEEP
            run "$b" $bench -M $g $CT && emit $i $bench $v tma >> "$OUT"
        done
        for ge in "${GROUPS_EV[@]}"; do
            check_settings; sleep $MIN_SLEEP
            run "$b" $bench -e "${ge#*:}" && emit $i $bench $v "${ge%%:*}" >> "$OUT"
        done
    done
    echo "round $i done $(date +%T)" >&2
done
