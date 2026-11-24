#!/bin/bash
# usage: bench/pstat_all.sh build|measure
#   Every suite on a Linux host without perf and without root (used for the Raspberry Pi 5,
#   Cortex-A76): counters with bench/pstat (perf_event_open, user mode), runs with
#   bench/android_run.sh (random order per round, cooldown on the CPU thermal zone).
#   The clock cannot be fixed without root, so compare cycles, not time.
#   Compilers: the gcc and clang first in PATH.  Build (and check) everything first, then measure.
#   env: TAG=cortex-a76  MASK=8 (taskset mask: cpu3)  ROUNDS=5 (micro, lua, wamr)
#        SUITES="probe micro layout lua wamr"  COOL=50 MINSLEEP=3 MAXWAIT=60 (cooldown)
#        SEEDS=100 NLIMIT=2000000 MAXPAD=63 (layout experiment, as analysis/layout_dist.sh)
#        IND=<raw event of indirect mispredictions>, default: found by the probe (none if absent)
# outputs: results/<TAG>_O{0,1,2,3}_raw.txt, results/lua_<TAG>_raw.txt, results/wamr_<TAG>_raw.txt
#            (android_run.sh lines: round name time_s cycles instructions branches branch_misses
#             ghz temp_before temp_after loadavg indirect_spec; lua/wamr names are "bench variant")
#          results/analysis/arm_pmu_scan_<TAG>.txt, results/analysis/layoutdist_<TAG>.txt
#          results/<TAG>_env.txt, results/<TAG>_check.txt (build-time correctness checks)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
STEP=${1:-}
TAG=${TAG:-cortex-a76}; ROUNDS=${ROUNDS:-5}
SUITES=${SUITES:-"probe micro layout lua wamr"}
export MASK=${MASK:-8} COOL=${COOL:-50} MINSLEEP=${MINSLEEP:-3} MAXWAIT=${MAXWAIT:-60}
SEEDS=${SEEDS:-100}; NLIMIT=${NLIMIT:-2000000}; MAXPAD=${MAXPAD:-63}
B=$ROOT/build; R=$ROOT/results
mkdir -p "$B" "$R/analysis"
has() { [[ " $SUITES " == *" $1 "* ]]; }
log() { echo "== [$(date +%T)] $*" >&2; }
declare -A SIZE=([DeltaBlue]=12000 [Richards]=100 [Json]=100 [CD]=250 [Havlak]=1500 [Bounce]=1500
                 [List]=1500 [Mandelbrot]=500 [NBody]=250000 [Permute]=1000 [Queens]=1000
                 [Sieve]=3000 [Storage]=1000 [Towers]=600)
# WAMR cases as in targets/wamr/run.sh: name|dir|args|lines to compare ("-": discard output)
WCASES="coremark|coremark|coremark_wasi_nofp.wasm 0x0 0x0 0x66 2000|crc|^Iterations +:
nbody|nbody|nbody.wasm 3000000|.
fannkuch|fannkuch-redux|fannkuch_redux.wasm 10|.
binarytrees|binary-trees|binary_trees.wasm 14|.
fasta|fasta|fasta.wasm 2000000|-
cray|c-ray|c_ray.wasm -s 1600x1200|-
hashset|hashset|HashSet.wasm|^[^T]
raymarcher|raymarcher|raymarcher.wasm|.
crayscene|c-ray|c_ray.wasm -s 1600x1200 < scene|-"
# c-ray reads its scene from stdin.  targets/wamr/run.sh gives it none, so every x86 "cray"
# measurement rendered an empty scene (9.5G instructions instead of 71G with the scene); "cray"
# keeps that (stdin /dev/null, comparable with the x86 data), "crayscene" renders the real scene.
WSRC=$ROOT/third_party/wamr/tests/standalone
LAYOUT_VARIANTS="switch cgoto musttail mtargs"
declare -A LSRC=([switch]=src/switch.c [cgoto]=src/cgoto.c [musttail]=src/musttail.c [mtargs]=src/musttail_args.c)
# gcc gets preserve_none variants only if it accepts the attribute on this target
gcc_pn() { echo 'void __attribute__((preserve_none)) f(void) {}' | gcc -x c -c -Werror=attributes -o /dev/null - 2>/dev/null; }

build() {
    gcc -O2 -o bench/pstat bench/pstat.c
    PNG=""; gcc_pn && PNG=" tailpn"
    {
        echo "tag: $TAG"; grep -m1 -E 'Model name|model name' /proc/cpuinfo || lscpu | grep 'Model name'
        lscpu | grep -E 'Vendor ID|Model name|CPU\(s\)|max MHz|min MHz' || true
        uname -a; grep PRETTY_NAME /etc/os-release || true
        echo "gcc: $(command -v gcc) $(gcc --version | head -1)"
        echo "clang: $(command -v clang) $(clang --version | head -1)"
        echo "gcc preserve_none: ${PNG:-no (tailpn_gcc not built)}"
        echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor) (not fixed, no root)"
        echo "core: taskset mask $MASK; cooldown COOL=$COOL MINSLEEP=$MINSLEEP MAXWAIT=$MAXWAIT"
        echo "counters: bench/pstat (perf_event_open, user mode); perf_event_paranoid=$(cat /proc/sys/kernel/perf_event_paranoid)"
        echo "other load: shared machine, services running (see loadavg column)"
    } > "$R/${TAG}_env.txt"
    # keep the checks of suites not rebuilt now
    touch "$R/${TAG}_check.txt"
    grep -vE "^(${SUITES// /|}) " "$R/${TAG}_check.txt" > "$R/${TAG}_check.tmp" || true
    mv "$R/${TAG}_check.tmp" "$R/${TAG}_check.txt"
    if has probe; then
        log "build probe"
        mkdir -p "$B/probe"; gcc -O2 -o "$B/probe/probe" analysis/arm_pmu_probe.c
        cp bench/pstat analysis/arm_pmu_probe.sh "$B/probe/"
    fi
    if has micro; then
        for o in O0 O1 O2 O3; do
            log "build micro -$o"; OPT=-$o bench/build.sh "$B/$o" > /dev/null
            for f in "$B/$o"/*; do
                [ "$("$f")" = 1552724831 ] && r=ok || r=WRONG
                echo "micro $o $(basename "$f") $r" >> "$R/${TAG}_check.txt"
            done
        done
    fi
    if has layout; then
        log "build layout ($SEEDS seeds)"
        rm -rf "$B/layout"; mkdir -p "$B/layout/bin" "$B/layout/asm"
        : > "$B/layout/list"
        for v in $LAYOUT_VARIANTS; do for cc in gcc clang; do
            sed "s/10000001/$((NLIMIT + 1))/" "${LSRC[$v]}" > "$B/layout/s.c"
            $cc -O2 -S -o "$B/layout/asm/O2_${v}_$cc.s" "$B/layout/s.c"
            for seed in $(seq 0 $SEEDS); do
                python3 -I analysis/perturb.py "$B/layout/asm/O2_${v}_$cc.s" "$B/layout/p.s" $seed $MAXPAD fixed 2>/dev/null
                $cc -O2 "$B/layout/p.s" -o "$B/layout/bin/O2_${v}_${cc}_$seed"
                echo "-O2 ${v}_$cc $seed bin/O2_${v}_${cc}_$seed" >> "$B/layout/list"
            done
        done; done
        rm -f "$B/layout/s.c" "$B/layout/p.s"
        cp bench/pstat analysis/layout_run_android.sh "$B/layout/"
    fi
    if has lua; then
        log "build lua"
        CCS=clang targets/lua/build.sh "$B/lua" > /dev/null
        CCS=gcc MODES="switch cgoto tail$PNG" targets/lua/build.sh "$B/lua" > /dev/null
        for f in "$B"/lua/bin/lua_*; do
            (cd third_party/awfy/benchmarks && LUA_PATH="Lua/?.lua;;" "$f" Lua/harness.lua Richards 1 10 2>&1) \
                | grep -q 'runtime:' && r=ok || r=WRONG
            echo "lua $(basename "$f") $r" >> "$R/${TAG}_check.txt"
        done
    fi
    if has wamr; then
        log "build wamr"
        CCS=clang targets/wamr/build.sh "$B/wamr" > /dev/null
        CCS=gcc MODES="switch cgoto tail$PNG" targets/wamr/build.sh "$B/wamr" > /dev/null
        log "check wamr outputs"
        while IFS='|' read -r name dir args keep; do
            ref=""
            for f in "$B"/wamr/bin/iwasm_*; do
                if [ "$keep" = - ]; then
                    (cd "$WSRC/$dir" && sh -c "exec $f $args > /dev/null 2>&1" < /dev/null) && fp=rc=0 || fp=rc=$?
                else
                    fp="$(cd "$WSRC/$dir" && sh -c "exec $f $args" < /dev/null 2>&1 | grep -E "$keep" | md5sum | cut -c1-12)"
                fi
                [ -z "$ref" ] && ref=$fp
                [ "$fp" = "$ref" ] && r=ok || r="WRONG ($fp vs $ref)"
                echo "wamr $name $(basename "$f") $r" >> "$R/${TAG}_check.txt"
            done
        done <<< "$WCASES"
    fi
    log "build done: $(grep -c ok "$R/${TAG}_check.txt") ok, $(grep -c WRONG "$R/${TAG}_check.txt") wrong"
}

measure() {
    if grep -q WRONG "$R/${TAG}_check.txt"; then echo "correctness check failed, see $R/${TAG}_check.txt" >&2; exit 1; fi
    IND=${IND:-}
    if has probe; then
        log "probe PMU events"
        bash "$B/probe/arm_pmu_probe.sh" "$R/analysis/arm_pmu_scan_$TAG.txt"
        if [ -z "$IND" ]; then
            # indirect mispredictions: ~7/8 N in probe mode 0, ~0 in modes 1 and 2 (see arm_pmu_probe.c)
            IND=$(awk '{v[$2 " " $1]=$3; e[$2]=1} END {for (x in e) if (v[x " 0"] > 3e6 && v[x " 1"] < 1e6 && v[x " 2"] < 1e6) print x}' \
                  "$R/analysis/arm_pmu_scan_$TAG.txt" | sed 's/^raw-//' | sort | head -1)
        fi
    fi
    IND=${IND:-none}
    echo "indirect-misprediction event: $IND" >> "$R/${TAG}_env.txt"
    log "indirect-misprediction event: $IND"
    if has micro; then
        for o in O0 O1 O2 O3; do
            : > "$B/micro_$o.list"
            for f in "$B/$o"/*; do echo "$(basename "$f")|$B/$o|^1552724831\$|./$(basename "$f")" >> "$B/micro_$o.list"; done
            log "measure micro -$o"
            bash bench/android_run.sh "$B/micro_$o.list" "$R/${TAG}_${o}_raw.txt" $ROUNDS
        done
    fi
    if has layout; then
        log "measure layout"
        (cd "$B/layout" && MINSLEEP=2 IND=$IND bash layout_run_android.sh list out.txt)
        { echo "# opt variant seed cycles instructions other_misp indirect_misp all_misp  branches indirect_spec ghz temp_before temp_after  nlimit=$NLIMIT maxpad=$MAXPAD pad_mode=fixed ind=$IND $(date -Is)"
          cat "$B/layout/out.txt"; } > "$R/analysis/layoutdist_$TAG.txt"
    fi
    if has lua; then
        : > "$B/lua.list"
        for b in "${!SIZE[@]}"; do for f in "$B"/lua/bin/lua_*; do
            echo "$b $(basename "$f")|$ROOT/third_party/awfy/benchmarks|runtime:|env LUA_PATH=Lua/?.lua\\;\\; setarch $(uname -m) -R $f Lua/harness.lua $b 1 ${SIZE[$b]}" >> "$B/lua.list"
        done; done
        log "measure lua"
        bash bench/android_run.sh "$B/lua.list" "$R/lua_${TAG}_raw.txt" $ROUNDS
    fi
    if has wamr; then
        : > "$B/wamr.list"
        while IFS='|' read -r name dir args keep; do for f in "$B"/wamr/bin/iwasm_*; do
            if [ "$keep" = - ]; then
                echo "$name $(basename "$f")|$WSRC/$dir|-|$f $args > /dev/null" >> "$B/wamr.list"
            else
                echo "$name $(basename "$f")|$WSRC/$dir|$keep|$f $args" >> "$B/wamr.list"
            fi
        done; done <<< "$WCASES"
        log "measure wamr"
        bash bench/android_run.sh "$B/wamr.list" "$R/wamr_${TAG}_raw.txt" $ROUNDS
    fi
    log "measure done"
}

case $STEP in
    build) build ;;
    measure) measure ;;
    *) echo "usage: $0 build|measure" >&2; exit 2 ;;
esac
