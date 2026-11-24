#!/bin/bash
# usage: analysis/lua_merge.sh [tag]
#   Lua dispatch-merging experiment (paper 5.3): build cgoto, cgotonm (tail merging off),
#   cgotobf (branch-free hook check) and tailpn, count the dispatch jumps, run the official
#   Lua test suite on the new modes, then measure AWFY.  Steps run one after another so
#   nothing else runs during the measurement.  Turn turbo off before starting.
#   env: OPT=-O2 STEPS="build jumps test measure" (and targets/lua/run.sh env)
# output: results/analysis/lua_merge_jumps_<tag>.txt, results/lua-merge_<tag>_raw.txt
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TAG=${1:-$(hostname 2>/dev/null || echo host)}
OPT=${OPT:--O2}
STEPS=${STEPS:-"build jumps test measure"}
SFX=""; [ "$OPT" != -O2 ] && SFX=$OPT
B=build/lua-merge$SFX
has() { [[ " $STEPS " == *" $1 "* ]]; }

if has build; then
    OPT=$OPT MODES="cgoto cgotonm cgotobf tailpn" targets/lua/build.sh "$B" > "$B.log" 2>&1
fi
if has jumps; then
    mkdir -p results/analysis
    for b in "$B"/bin/lua_*; do
        printf "%-22s %s\n" "$(basename "$b")" "$(python3 -I analysis/dispatch_tails.py "$b" luaV_execute 3)"
    done | tee "results/analysis/lua_merge_jumps${SFX}_$TAG.txt"
fi
if has test; then
    cd third_party/lua-5.4.8-tests
    for b in "$ROOT/$B"/bin/lua_cgotonm_* "$ROOT/$B"/bin/lua_cgotobf_*; do
        "$b" -e"_U=true" all.lua > /dev/null 2>&1 || { echo "TEST FAILED: $b" >&2; exit 1; }
        echo "tests ok: $(basename "$b")"
    done
    cd "$ROOT"
fi
if has measure; then
    FIXED=${FIXED:-1} TOL=${TOL:-0.05} targets/lua/run.sh "$B/bin" "results/lua-merge${SFX}_${TAG}_raw.txt"
fi
