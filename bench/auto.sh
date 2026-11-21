#!/bin/bash
# usage: bench/auto.sh [bin_dir] [out_file]
#   measures the steady clock of $CPU, sets GHZ, then runs bench/run.sh with the same args/env
set -u
D=$(cd "$(dirname "$0")" && pwd)
export CPU=${CPU:-3}

if [ -z "${GHZ:-}" ]; then
    CY=cycles; [ -d /sys/devices/cpu_core ] && CY=cpu_core/cycles/
    GHZ=$(for k in 1 2 3; do
        sleep ${MIN_SLEEP:-3}
        taskset -c $CPU perf stat -x, -e task-clock,$CY awk 'BEGIN{for(i=0;i<5e7;i++);}' 2>&1 >/dev/null \
            | awk -F, '/task-clock/{tc=$1} /cycles/{c=$1} END{printf "%.3f\n", c/(tc*1e6)}'
    done | sort -n | sed -n 2p)
fi
export GHZ
echo "cpu$CPU GHZ=$GHZ (tol ${TOL:-0.02})" >&2

exec "$D/run.sh" "$@"
