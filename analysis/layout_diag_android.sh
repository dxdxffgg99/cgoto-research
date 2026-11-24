#!/system/bin/sh
# usage (on the Android device, adb shell, in the directory of layout_run_android.sh):
#   sh layout_diag_android.sh <list> <out> [reps=3]
#   Follow-up of analysis/layout_dist_android.sh: re-runs chosen layouts (<list> lines:
#   opt variant seed binary) with front-end / back-end stall events, in two event groups
#   that fit the counters (no multiplexing), on the prime core.  ARMv8 common events:
#   0x23 STALL_FRONTEND, 0x24 STALL_BACKEND, 0x01 L1I_CACHE_REFILL, 0x02 L1I_TLB_REFILL,
#   0x10 BR_MIS_PRED (speculative), 0x1b INST_SPEC, 0x3a OP_RETIRED, 0x3b OP_SPEC,
#   0x3e STALL_SLOT_FRONTEND, 0x3f STALL_SLOT; 0x8117 indirect mispredictions (Oryon).
#   env: MASK=80 COOL=46 MINSLEEP=2 MAXWAIT=60
# output line: opt variant seed rep group event count
cd "$(dirname "$0")"
LIST=$1; OUT=$2; REPS=${3:-3}
MASK=${MASK:-80}; COOL=${COOL:-46}; MINSLEEP=${MINSLEEP:-2}; MAXWAIT=${MAXWAIT:-60}
G1=cycles,instructions,raw-0x23,raw-0x24,raw-0x01,raw-0x02,raw-0x10
G2=cycles,raw-0x1b,raw-0x3a,raw-0x3b,raw-0x3e,raw-0x3f,raw-0x8117
temp() {
    max=0
    for z in /sys/class/thermal/thermal_zone*; do
        case $(cat $z/type 2>/dev/null) in
            cpu-*) v=$(cat $z/temp 2>/dev/null); [ -n "$v" ] && [ "$v" -gt "$max" ] && max=$v ;;
        esac
    done
    echo $((max / 1000))
}
cooldown() {
    sleep $MINSLEEP; w=$MINSLEEP
    while [ "$(temp)" -gt "$COOL" ] && [ $w -lt $MAXWAIT ]; do sleep 2; w=$((w + 2)); done
}
: > "$OUT"
r=1
while [ $r -le $REPS ]; do
    while read -r opt v seed bin; do
        for g in g1 g2; do
            [ $g = g1 ] && ev=$G1 || ev=$G2
            cooldown
            taskset $MASK ./pstat -o "$OUT.p" -e "$ev" -- ./$bin > /dev/null 2>&1 || echo "FAIL $v $seed" >&2
            grep -q scaled "$OUT.p" && echo "MULTIPLEXED $v $seed $g" >&2
            awk -F, -v p="$opt $v $seed $r $g" '$3 != "time-elapsed" { print p, $3, $1 }' "$OUT.p" >> "$OUT"
        done
    done < "$LIST"
    r=$((r + 1))
done
rm -f "$OUT.p"
touch "$OUT.done"
