#!/bin/bash
# usage: analysis/layout_dist_android.sh <adb-serial> <ssh-host> [tag=galaxy-s25edge]
#   ARM version of layout_dist.sh (paper 6.2a, task 4): the same random layouts per variant
#   (perturb.py, AArch64 rules), built on the device with its own clang (Termux, reached
#   with ssh <ssh-host>), run over adb shell on the prime core with bench/pstat
#   (analysis/layout_run_android.sh).  Termux's gcc is clang, so clang variants only.
#   The clock cannot be fixed without root: collapses are judged by indirect mispredictions
#   (raw event 0x8117 on Oryon, found with analysis/arm_pmu_probe.sh), not by time.
#   Building finishes before measuring starts.
#   env: SEEDS=100 OPTS=-O2 NLIMIT=2000000 MAXPAD=63 PAD_MODE=fixed
#        VARIANTS="cgoto switch musttail mtargs"  SSH_OPTS="" (extra ssh/scp options)
#        DEV=/data/local/tmp/cg (device directory holding pstat)
# output: results/analysis/layoutdist_<tag>.txt   (columns: layout_run_android.sh)
#         results/analysis/layoutdist_<tag>_asm/<opt>_<variant>.s   (unperturbed assembly)
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
SERIAL=$1; HOST=$2; TAG=${3:-galaxy-s25edge}
SEEDS=${SEEDS:-100}; OPTS=${OPTS:--O2}; NLIMIT=${NLIMIT:-2000000}; MAXPAD=${MAXPAD:-63}
PAD_MODE=${PAD_MODE:-fixed}; VARIANTS=${VARIANTS:-"cgoto switch musttail mtargs"}
DEV=${DEV:-/data/local/tmp/cg}
SSH_OPTS=${SSH_OPTS:-}
OUT=results/analysis/layoutdist_$TAG.txt
ASM=results/analysis/layoutdist_${TAG}_asm
A() { adb -s "$SERIAL" "$@"; }
G() { ssh -o BatchMode=yes $SSH_OPTS "$HOST" "$@"; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
declare -A SRC=( [switch]=src/switch.c [cgoto]=src/cgoto.c [musttail]=src/musttail.c [mtargs]=src/musttail_args.c )

# 1. build on the device (Termux)
G 'rm -rf ld && mkdir -p ld/src ld/bin ld/asm'
for v in $VARIANTS; do
    grep -q '10000001' "${SRC[$v]}" || { echo "limit constant not found in ${SRC[$v]}" >&2; exit 1; }
    sed "s/10000001/$((NLIMIT + 1))/" "${SRC[$v]}" > "$W/$v.c"
done
scp -q -o BatchMode=yes $SSH_OPTS "$W"/*.c analysis/perturb.py "$HOST":ld/src/
G "cd ld && for opt in $OPTS; do for v in $VARIANTS; do
     clang \$opt -S -o asm/\${opt#-}_\${v}_clang.s src/\$v.c
     for seed in \$(seq 0 $SEEDS); do
       python3 -I src/perturb.py asm/\${opt#-}_\${v}_clang.s p.s \$seed $MAXPAD $PAD_MODE 2>/dev/null
       clang \$opt p.s -o bin/\${opt#-}_\${v}_clang_\$seed
     done
   done; done; rm -f p.s; ls bin | wc -l"
mkdir -p "$ASM"
scp -q -o BatchMode=yes $SSH_OPTS "$HOST":'ld/asm/*.s' "$ASM"/
scp -q -r -o BatchMode=yes $SSH_OPTS "$HOST":ld/bin "$W"/

# 2. measure on the device
: > "$W/list"
for opt in $OPTS; do for v in $VARIANTS; do for seed in $(seq 0 $SEEDS); do
    echo "$opt ${v}_clang $seed bin/${opt#-}_${v}_clang_$seed" >> "$W/list"
done; done; done
A shell "rm -rf $DEV/ld && mkdir -p $DEV/ld"
A push "$W/bin" "$DEV/ld/" > /dev/null
A push "$W/list" analysis/layout_run_android.sh "$DEV/ld/" > /dev/null
A shell "cp $DEV/pstat $DEV/ld/pstat && chmod -R 755 $DEV/ld"
echo "# opt variant seed cycles instructions other_misp indirect_misp all_misp  branches indirect_spec ghz temp_before temp_after  nlimit=$NLIMIT maxpad=$MAXPAD pad_mode=$PAD_MODE $(date -Is)" > "$OUT"
A shell "cd $DEV/ld && setsid nohup sh layout_run_android.sh list out.txt > run.log 2>&1 < /dev/null &"
until A shell "test -f $DEV/ld/out.txt.done" 2>/dev/null; do sleep 60; done
A shell "cat $DEV/ld/out.txt" >> "$OUT"
A shell "cat $DEV/ld/run.log" >&2
echo "$(grep -vc '^#' "$OUT") lines -> $OUT"
