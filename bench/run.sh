#!/bin/bash
# usage: bench/run.sh [bin_dir] [out_file]
#   ROUNDS=5 CPU=3 COOL=50000 MIN_SLEEP=3 MAX_WAIT=90
#   FIXED=1      : wait while no_turbo!=1 or governor!=performance
#   GHZ=2.395    : discard and retry runs whose avg clock is off by more than TOL
#   VARIANTS="cgoto_gcc switch_gcc"
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B=${1:-$ROOT/build}
OUT=${2:-$ROOT/results/raw.txt}
ROUNDS=${ROUNDS:-5}; CPU=${CPU:-3}
COOL=${COOL:-50000}; MIN_SLEEP=${MIN_SLEEP:-3}; MAX_WAIT=${MAX_WAIT:-90}
FIXED=${FIXED:-0}; GHZ=${GHZ:-}; TOL=${TOL:-0.02}; TRIES=${TRIES:-3}
L=${VARIANTS:-"switch_gcc switch_clang cgoto_gcc cgoto_clang musttail_gcc musttail_clang mtargs_gcc mtargs_clang mtnopie_gcc mtnopie_clang"}

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

measure() {
    local b=$1 i=$2 t0 t1 r
    t0=$(temp)
    r=$(taskset -c $CPU perf stat -e $EVENTS "$B/$b" 2>&1 >/dev/null)
    t1=$(temp)
    echo "$r" | awk -v b=$b -v i=$i -v t0=$t0 -v t1=$t1 -v la=$(cut -d' ' -f1 /proc/loadavg) '
        /task-clock/   { tc=$1; next }
        /time elapsed/ { t=$1; next }
        NF>=2 { n=$2; sub(/^cpu_core\//,"",n); sub(/\/?:?u$/,"",n); v[n]=$1 }
        END {
            for (k in v) gsub(",","",v[k]); gsub(",","",tc)
            printf "%d %s %s %s %s %s %s %.3f %d %d %s\n", i, b, t, v["cycles"], v["instructions"],
                v["branches"], v["branch-misses"], v["cycles"]/(tc*1e6), t0/1000, t1/1000, la
        }'
}

mkdir -p "$(dirname "$OUT")"; : > "$OUT"
for i in $(seq $ROUNDS); do
    for b in $(echo $L | tr ' ' '\n' | shuf); do
        for try in $(seq $TRIES); do
            check_settings; cooldown
            line=$(measure $b $i)
            g=$(echo "$line" | awk '{print $8}')
            if [ -z "$GHZ" ] || awk -v g=$g -v e=$GHZ -v t=$TOL 'BEGIN{d=(g-e)/e; exit !(d<t && d>-t)}'; then
                echo "$line" | tee -a "$OUT"; break
            fi
            echo "DISCARD (GHz=$g) $line" >&2
        done
    done
done
