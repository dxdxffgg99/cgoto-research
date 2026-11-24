#!/bin/bash
# usage: targets/cpython/run.sh [inst_dir] [out_dir]
#   runs pyperformance on every <inst_dir>/<mode>_<cc>/bin/python3
#   env: CPU=3  PYPERF=<pyperformance exe>  REF=cgoto_gcc
#        SPEED=""|--fast|--rigorous   BENCHMARKS="" (pyperformance -b list)
#        VARIANTS="cgoto_gcc tail_clang"
# per variant: <out_dir>/<variant>.json (pyperf), <variant>.perf (perf stat), <variant>.env
# The REF variant runs first and calibrates loop counts; the others reuse them (--same-loops)
# in shuffled order, so every interpreter executes exactly the same work.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
INST=$(cd "${1:-$ROOT/build/cpython}" && pwd)
OUT=$(mkdir -p "${2:-$ROOT/results/cpython}" && cd "${2:-$ROOT/results/cpython}" && pwd)
PYPERF=${PYPERF:-$ROOT/build/pyperf-venv/bin/pyperformance}
CPU=${CPU:-3}
REF=${REF:-cgoto_gcc}
SPEED=${SPEED:-}
BM=${BENCHMARKS:+-b $BENCHMARKS}
VARIANTS=${VARIANTS:-$(cd "$INST" && ls -d *_* | grep -v '^obj_' | tr '\n' ' ')}

P=""; [ -d /sys/devices/cpu_core ] && P=cpu_core/
ev() { [ -n "$P" ] && echo "$P$1/" || echo "$1"; }
EVENTS="task-clock,$(ev cycles),$(ev instructions),$(ev branches),$(ev branch-misses)"

snapshot() {  # CPU settings and temperature, for the record
    echo "date=$(date -Is) cpu=$CPU"
    echo "no_turbo=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)"
    echo "governor=$(cat /sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor 2>/dev/null)"
    echo "loadavg=$(cat /proc/loadavg)"
    for h in /sys/class/hwmon/hwmon*; do
        [ "$(cat $h/name)" = coretemp ] && echo "temp_max=$(( $(cat $h/temp*_input | sort -n | tail -1) / 1000 ))"
    done
}

WORK=$(mkdir -p "${WORK:-$ROOT/build/pyperf-work}" && cd "${WORK:-$ROOT/build/pyperf-work}" && pwd)
cd "$WORK"   # pyperformance creates its venvs under the current directory

# 1. create benchmark venvs up front so installs are not measured
for v in $VARIANTS; do
    echo "== venv $v" >&2
    "$PYPERF" venv recreate -p "$INST/$v/bin/python3" $BM > "$OUT/$v.venv.log" 2>&1 \
        || { echo "venv failed for $v (see $OUT/$v.venv.log)" >&2; exit 1; }
done

run_one() {  # variant [same-loops json]   (runs in $WORK so the venvs above are reused)
    local v=$1 same=${2:-} o=$OUT/$1
    echo "== run $v $(date +%T)" >&2
    { echo "variant=$v"; "$INST/$v/bin/python3" -c 'import sys,sysconfig;print("version="+sys.version.split()[0]);print("cc="+sysconfig.get_config_var("CC"));print("config="+sysconfig.get_config_var("CONFIG_ARGS"))'; echo "[before]"; snapshot; } > "$o.env"
    rm -f "$o.json"
    taskset -c $CPU perf stat -o "$o.perf" -e $EVENTS -- \
        "$PYPERF" run -p "$INST/$v/bin/python3" --affinity=$CPU $SPEED $BM \
            ${same:+--same-loops "$same"} -o "$o.json" > "$o.log" 2>&1 \
        || echo "run failed for $v (see $o.log)" >&2
    grep -qE 'Downloading|Successfully installed' "$o.log" && echo "WARNING: $v run installed packages during measurement (see $o.log)" >&2
    { echo "[after]"; snapshot; } >> "$o.env"
}

# 2. reference first (calibrates loops), then the rest in random order
run_one "$REF"
for v in $(echo $VARIANTS | tr ' ' '\n' | grep -vx "$REF" | shuf); do
    run_one "$v" "$OUT/$REF.json"
done
echo "done $(date +%T)" >&2
