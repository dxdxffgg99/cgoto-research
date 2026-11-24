#!/bin/bash
# usage: bench/all.sh build|measure|all
#
# Builds and measures every suite of the study, in a fixed order:
#   micro        src/*.c microbenchmark, -O0..-O3          (bench/build.sh, bench/auto.sh)
#   lua          Lua 5.4 + AWFY, fixed hash seed, no ASLR   (targets/lua)
#   wamr         WAMR fast interpreter + standalone wasm    (targets/wamr)
#   cpython      CPython 3.15 + pyperformance               (targets/cpython)
#   cpython-pgo  same, built with --enable-optimizations --with-lto
#
# Build everything first, then measure: never build while measuring.
# Long run: start it detached, e.g.  setsid nohup bench/all.sh measure > results/all.log 2>&1 &
#
# env:
#   SUITES="micro lua wamr cpython cpython-pgo"   suites to build/measure
#   CPU=3        core to pin to (use a P-core on hybrid CPUs)
#   TAG=<auto>   result file prefix, default from the CPU model (e.g. i5-1135g7)
#   FORCE=1      measure even if turbo is on / governor is not performance
#   JOBS=<nproc> build parallelism
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
STEP=${1:-}
SUITES=${SUITES:-"micro lua wamr cpython cpython-pgo"}
export CPU=${CPU:-3}
JOBS=${JOBS:-$(nproc)}
MODEL=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2-)
TAG=${TAG:-$(echo "$MODEL" | tr 'A-Z' 'a-z' | grep -oE '[a-z][0-9]+-[0-9]+[a-z0-9]*|ryzen [0-9] [0-9]+[a-z0-9]*' | head -1 | tr ' ' '-')}
TAG=${TAG:-unknown-cpu}
R=$ROOT/results
has() { [[ " $SUITES " == *" $1 "* ]]; }
log() { echo "== [$(date +%T)] $*" >&2; }

build() {
    if has micro; then
        for o in O0 O1 O2 O3; do log "build micro -$o"; OPT=-$o bench/build.sh build/$o > /dev/null; done
    fi
    if has lua;  then log "build lua";  targets/lua/build.sh > /dev/null; fi
    if has wamr; then log "build wamr"; JOBS=$JOBS targets/wamr/build.sh > /dev/null; fi
    if has cpython; then log "build cpython"; JOBS=$JOBS targets/cpython/build.sh; fi
    if has cpython-pgo; then log "build cpython-pgo"; PGO=1 JOBS=$JOBS targets/cpython/build.sh; fi
}

check_settings() {
    local nt gov
    nt=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null || echo "?")
    gov=$(cat /sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor 2>/dev/null || echo "?")
    if [ "$nt" != 1 ] || [ "$gov" != performance ]; then
        if [ "${FORCE:-0}" = 1 ]; then log "WARNING: no_turbo=$nt governor=$gov (FORCE=1)"
        else
            echo "turbo/governor not fixed (no_turbo=$nt governor=$gov). Run:" >&2
            echo "  echo 1 | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo" >&2
            echo "  sudo cpupower frequency-set -g performance" >&2
            echo "or set FORCE=1 to measure anyway." >&2
            exit 1
        fi
    fi
}

write_env() {
    mkdir -p "$R"
    {
        echo "date=$(date -Is)"
        echo "host_cpu=$MODEL"
        echo "kernel=$(uname -r)"
        echo "gcc=$(gcc --version | head -1)"
        echo "clang=$(clang --version 2>/dev/null | head -1)"
        echo "perf=$(perf --version 2>/dev/null)"
        echo "cpu=$CPU smt_siblings=$(cat /sys/devices/system/cpu/cpu$CPU/topology/thread_siblings_list)"
        echo "no_turbo=$(cat /sys/devices/system/cpu/intel_pstate/no_turbo 2>/dev/null)"
        echo "governor=$(cat /sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor 2>/dev/null)"
        echo "suites=$SUITES"
        echo "git=$(git rev-parse --short HEAD 2>/dev/null) dirty=$(git status --porcelain 2>/dev/null | wc -l)"
    } > "$R/${TAG}_env.txt"
}

measure() {
    check_settings
    write_env
    if has micro; then
        for o in O0 O1 O2 O3; do
            log "measure micro -$o"
            FIXED=1 bench/auto.sh build/$o "$R/${TAG}_${o}_raw.txt"
            bench/to_csv.sh "$R/${TAG}_${o}_raw.txt" "$R/${TAG}_$o" > /dev/null
        done
    fi
    if has lua; then
        log "measure lua"
        FIXED=1 TOL=0.05 targets/lua/run.sh build/lua/bin "$R/lua_${TAG}_raw.txt"
    fi
    if has wamr; then
        log "measure wamr"
        FIXED=1 TOL=0.05 targets/wamr/run.sh build/wamr/bin "$R/wamr_${TAG}_raw.txt"
    fi
    if has cpython; then
        log "measure cpython"
        targets/cpython/run.sh build/cpython "$R/cpython_${TAG}"
    fi
    if has cpython-pgo; then
        log "measure cpython-pgo"
        targets/cpython/run.sh build/cpython-pgo "$R/cpython-pgo_${TAG}"
    fi
    log "done ($TAG)"
}

case $STEP in
    build)   build ;;
    measure) measure ;;
    all)     build; measure ;;
    *) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
