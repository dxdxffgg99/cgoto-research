#!/bin/bash
# usage: targets/lua/run.sh [bin_dir] [out_file]
#   runs every AWFY benchmark on every lua_* binary in bin_dir
#   env: ROUNDS=5 CPU=3 COOL=50000 MIN_SLEEP=3 MAX_WAIT=90 FIXED=0 GHZ=(auto) TOL=0.02 TRIES=3
#        BENCHMARKS="Richards Json"  VARIANTS="lua_cgoto_gcc lua_tail_gcc"
# raw line: round benchmark variant time_s cycles instructions branches branch_misses ghz temp_before temp_after loadavg
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
B=$(cd "${1:-$ROOT/build/lua/bin}" && pwd)
OUT=${2:-$ROOT/results/lua_raw.txt}
AWFY=$ROOT/third_party/awfy/benchmarks
ROUNDS=${ROUNDS:-5}; CPU=${CPU:-3}
COOL=${COOL:-50000}; MIN_SLEEP=${MIN_SLEEP:-3}; MAX_WAIT=${MAX_WAIT:-90}
FIXED=${FIXED:-0}; TOL=${TOL:-0.02}; TRIES=${TRIES:-3}
# NOASLR=1 (default): run lua with address randomization off (setarch -R)
NOASLR=${NOASLR:-1}
NORAND=""; [ "$NOASLR" = 1 ] && NORAND="setarch $(uname -m) -R"

# standard AWFY problem sizes (rebench.conf)
declare -A SIZE=(
    [DeltaBlue]=12000 [Richards]=100 [Json]=100 [CD]=250 [Havlak]=1500
    [Bounce]=1500 [List]=1500 [Mandelbrot]=500 [NBody]=250000 [Permute]=1000
    [Queens]=1000 [Sieve]=3000 [Storage]=1000 [Towers]=600
)
BENCHMARKS=${BENCHMARKS:-"DeltaBlue Richards Json CD Havlak Bounce List Mandelbrot NBody Permute Queens Sieve Storage Towers"}
VARIANTS=${VARIANTS:-$(cd "$B" && ls lua_* | tr '\n' ' ')}

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

measure() {
    local bench=$1 v=$2 i=$3 t0 t1 r
    t0=$(temp)
    (cd "$AWFY" && LUA_PATH="Lua/?.lua;;" taskset -c $CPU perf stat -o "$TMP/perf" -e $EVENTS \
        $NORAND "$B/$v" Lua/harness.lua $bench 1 ${SIZE[$bench]} > "$TMP/out" 2>&1)
    t1=$(temp)
    if ! grep -q 'runtime:' "$TMP/out"; then
        echo "FAIL $bench $v: $(head -c 300 "$TMP/out")" >&2; return 1
    fi
    r=$(cat "$TMP/perf")
    echo "$r" | awk -v b=$bench -v vn=$v -v i=$i -v t0=$t0 -v t1=$t1 -v la=$(cut -d' ' -f1 /proc/loadavg) '
        /task-clock/   { tc=$1; next }
        /time elapsed/ { t=$1; next }
        NF>=2 { n=$2; sub(/^cpu_core\//,"",n); sub(/\/?:?u$/,"",n); v[n]=$1 }
        END {
            for (x in v) gsub(",","",v[x]); gsub(",","",tc)
            printf "%d %s %s %s %s %s %s %s %.3f %d %d %s\n", i, b, vn, t, v["cycles"], v["instructions"],
                v["branches"], v["branch-misses"], v["cycles"]/(tc*1e6), t0/1000, t1/1000, la
        }'
}

mkdir -p "$(dirname "$OUT")"; : > "$OUT"
for i in $(seq $ROUNDS); do
    for pair in $(for b in $BENCHMARKS; do for v in $VARIANTS; do echo "$b:$v"; done; done | shuf); do
        bench=${pair%%:*}; v=${pair#*:}
        for try in $(seq $TRIES); do
            check_settings; cooldown
            line=$(measure $bench $v $i) || break
            g=$(echo "$line" | awk '{print $9}')
            if awk -v g=$g -v e=$GHZ -v t=$TOL 'BEGIN{d=(g-e)/e; exit !(d<t && d>-t)}'; then
                echo "$line" | tee -a "$OUT"; break
            fi
            echo "DISCARD (GHz=$g) $line" >&2
        done
    done
done
