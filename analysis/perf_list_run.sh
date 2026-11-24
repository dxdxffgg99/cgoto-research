#!/bin/bash
# usage: analysis/perf_list_run.sh <list> <out> [rounds=5]
#   x86 Linux counterpart of bench/android_run.sh, with the measurement rules of targets/*/run.sh:
#   perf stat on the P-core PMU, one core, turbo off + performance governor (FIXED=1), cooldown,
#   order shuffled every round, runs whose clock is off by more than TOL are repeated (TRIES).
#   <list> lines:  name|workdir|expected-output-regex|command    ("-": exit status only)
#   env: CPU=3 COOL=50000 MIN_SLEEP=3 MAX_WAIT=90 FIXED=1 GHZ=(auto) TOL=0.02 TRIES=3
#        INDEV=br_misp_retired.indirect (extra event, appended as the last column)
# raw line (as android_run.sh with INDEV, so the same summaries read it):
#   round name time_s cycles instructions branches branch_misses ghz temp_before temp_after loadavg NA indirect_misp
#   time_s = task-clock seconds; "NA" stands for android_run.sh's indirect_spec column.
set -u
LIST=$1; OUT=$2; ROUNDS=${3:-5}
CPU=${CPU:-3}; COOL=${COOL:-50000}; MIN_SLEEP=${MIN_SLEEP:-3}; MAX_WAIT=${MAX_WAIT:-90}
FIXED=${FIXED:-1}; TOL=${TOL:-0.02}; TRIES=${TRIES:-3}; INDEV=${INDEV:-br_misp_retired.indirect}
HW=""
for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name)" = coretemp ] && HW=$h; done
temp() { [ -n "$HW" ] && cat $HW/temp*_input | sort -n | tail -1 || echo 0; }
P=""; [ -d /sys/devices/cpu_core ] && P=cpu_core/
ev() { [ -n "$P" ] && echo "$P$1/" || echo "$1"; }
EVENTS="task-clock,$(ev cycles),$(ev instructions),$(ev branches),$(ev branch-misses),$(ev $INDEV)"
NT=/sys/devices/system/cpu/intel_pstate/no_turbo
GOV=/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor
fixed_ok() { [ "$(cat $NT)" = 1 ] && [ "$(cat $GOV)" = performance ]; }
if [ "$FIXED" = 1 ] && ! fixed_ok; then
    echo "set no_turbo=1 and the performance governor first (FIXED=0 to skip)" >&2; exit 1
fi
cooldown() {
    sleep $MIN_SLEEP; local w=$MIN_SLEEP
    while [ "$(temp)" -gt $COOL ] && [ $w -lt $MAX_WAIT ]; do sleep 1; w=$((w + 1)); done
}
if [ -z "${GHZ:-}" ]; then
    GHZ=$(for k in 1 2 3; do
        sleep $MIN_SLEEP
        taskset -c $CPU perf stat -x, -e task-clock,$(ev cycles) awk 'BEGIN{for(i=0;i<5e7;i++);}' 2>&1 >/dev/null \
            | awk -F, '/task-clock/{tc=$1} /cycles/{c=$1} END{printf "%.3f\n", c/(tc*1e6)}'
    done | sort -n | sed -n 2p)
fi
echo "cpu$CPU GHZ=$GHZ (tol $TOL) events $EVENTS" >&2
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
case $OUT in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
: > "$OUT"
for i in $(seq 1 $ROUNDS); do
    grep -v '^#' "$LIST" | grep -v '^$' | shuf > "$TMP/order"
    while IFS='|' read -r name dir check cmd; do
        for try in $(seq $TRIES); do
            if [ "$FIXED" = 1 ]; then
                while ! fixed_ok; do echo "WAIT settings changed: no_turbo=$(cat $NT) gov=$(cat $GOV)" >&2; sleep 10; done
            fi
            cooldown
            t0=$(temp)
            (cd "$dir" && taskset -c $CPU perf stat -x, -o "$TMP/perf" -e "$EVENTS" -- sh -c "exec $cmd" < /dev/null > "$TMP/out" 2>&1)
            rc=$?
            t1=$(temp)
            if [ $rc -ne 0 ] || { [ "$check" != "-" ] && ! grep -qE "$check" "$TMP/out"; }; then
                echo "FAIL round=$i $name rc=$rc: $(head -c 200 "$TMP/out")" >&2; break
            fi
            line=$(awk -F, -v i=$i -v n="$name" -v t0=$t0 -v t1=$t1 -v la="$(cut -d' ' -f1 /proc/loadavg)" -v ie="$INDEV" '
                $3 ~ /task-clock/ { tc=$1 }
                $3 ~ /cycles/ { c=$1 }
                $3 ~ /instructions/ { n2=$1 }
                $3 ~ /branches/ && $3 !~ /misses/ { br=$1 }
                $3 ~ /branch-misses/ { m=$1 }
                index($3, ie) { im=$1 }
                END { printf "%d %s %.6f %s %s %s %s %.3f %d %d %s NA %s\n", i, n, tc/1000, c, n2, br, m, c/(tc*1e6), t0/1000, t1/1000, la, im }
            ' "$TMP/perf")
            g=$(echo "$line" | awk '{print $(NF-5)}')
            if awk -v g=$g -v e=$GHZ -v t=$TOL 'BEGIN{d=(g-e)/e; exit !(d<t && d>-t)}'; then
                echo "$line" | tee -a "$OUT"; break
            fi
            echo "DISCARD (GHz=$g) $line" >&2
        done
    done < "$TMP/order"
done
