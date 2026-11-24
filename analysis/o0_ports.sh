#!/bin/bash
# usage: analysis/o0_ports.sh [tag]
#   -O0 mechanism (paper 5.4), after analysis/latency_inject.sh found slack on the pc and
#   VM-register chains: execution-port use, uops executed per cycle, mispredict recovery,
#   machine clears (memory ordering) and blocked loads of the -O0
#   microbenchmark.  Raptor Lake (P-core) event names; each group fits the free counters
#   (6 general + fixed cycles/instructions, NMI watchdog on) so nothing is multiplexed.
#   env: CPU=3 ROUNDS=2 NLIMIT=1000000 OPT=-O0 VARIANTS="cgoto_gcc cgoto_clang musttail_gcc musttail_clang"
# output: results/analysis/o0_ports_<tag>.txt   (round variant group event count)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TAG=${1:-$(hostname 2>/dev/null || echo host)}
CPU=${CPU:-3}; ROUNDS=${ROUNDS:-2}; NLIMIT=${NLIMIT:-1000000}; OPT=${OPT:--O0}
VARIANTS=${VARIANTS:-"cgoto_gcc cgoto_clang musttail_gcc musttail_clang"}
OUT=results/analysis/o0_ports_$TAG.txt
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
GROUPS_EV=(
  "ports:cycles,instructions,uops_dispatched.port_0,uops_dispatched.port_1,uops_dispatched.port_2_3_10,uops_dispatched.port_4_9,uops_dispatched.port_5_11,uops_dispatched.port_6"
  "exec:cycles,uops_dispatched.port_7_8,uops_executed.thread,uops_executed.cycles_ge_1,uops_executed.cycles_ge_2,uops_executed.cycles_ge_3,uops_executed.cycles_ge_4"
  "clears:cycles,int_misc.recovery_cycles,int_misc.clear_resteer_cycles,br_misp_retired.all_branches,machine_clears.count,machine_clears.memory_ordering"
  "blocks:cycles,ld_blocks.store_forward,ld_blocks.address_alias,ld_blocks.no_sr,resource_stalls.sb"
  "stalls:cycles,resource_stalls.scoreboard,exe_activity.bound_on_stores,cycle_activity.stalls_total,exe_activity.bound_on_loads,exe_activity.exe_bound_0_ports,exe_activity.1_ports_util"
  "util:cycles,exe_activity.2_ports_util,exe_activity.3_ports_util,exe_activity.4_ports_util"
)
for vc in $VARIANTS; do
    v=${vc%_*}; cc=${vc##*_}
    sed "s/10000001/$((NLIMIT + 1))/" src/$v.c > "$W/$v.c"
    $cc $OPT -o "$W/$vc" "$W/$v.c"
done
echo "# round variant group event count  cpu=$CPU opt=$OPT nlimit=$NLIMIT $(date -Is)" > "$OUT"
for r in $(seq 1 $ROUNDS); do
  for vc in $(printf "%s\n" $VARIANTS | shuf); do
    for g in "${GROUPS_EV[@]}"; do
        name=${g%%:*}
        evs=$(echo "${g#*:}" | tr ',' '\n' | sed 's|.*|cpu_core/&/|' | paste -sd,)
        sleep 0.5
        taskset -c $CPU perf stat -x, -o "$W/perf" -e "$evs" setarch "$(uname -m)" -R "$W/$vc" > /dev/null
        awk -F, -v p="$r $vc $name" '/^[0-9]/ { e=$3; gsub(/cpu_core\/|\//, "", e); print p, e, $1, $5 }' "$W/perf" | tee -a "$OUT"
    done
  done
done
