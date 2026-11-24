#!/system/bin/sh
# usage (on the Android device, adb shell): sh layout_run_android.sh <list> <out>
#   Phone side of analysis/layout_dist_android.sh.  <list> lines: opt variant seed binary.
#   Runs every binary once, in random order, pinned to the prime core, with bench/pstat
#   (./pstat next to this script).  Each output must equal the variant's seed-0 output.
#   Also runs on Linux without perf (Raspberry Pi): run it with bash ($RANDOM).
#   env: MASK=80 COOL=46 MINSLEEP=2 MAXWAIT=60
#        IND=0x8117 raw event of indirect mispredictions (Oryon; see analysis/arm_pmu_probe.sh);
#                   IND=none if the core has none (indirect_misp column = NA)
#        EV: cycles, instructions, BR_RETIRED (0x21), BR_MIS_PRED_RETIRED (0x22),
#            indirect mispredictions ($IND), BR_INDIRECT_SPEC (0x7a)
# output line (same first 8 columns as layout_dist.sh):
#   opt variant seed cycles instructions other_misp indirect_misp all_misp  branches indirect_spec ghz temp_before temp_after
#   other_misp = all_misp - indirect_misp (conditional and return; no separate conditional event)
cd "$(dirname "$0")"
LIST=$1; OUT=$2
MASK=${MASK:-80}; COOL=${COOL:-46}; MINSLEEP=${MINSLEEP:-2}; MAXWAIT=${MAXWAIT:-60}
IND=${IND:-0x8117}
EV=task-clock,cycles,instructions,raw-0x21,raw-0x22,raw-0x7a
[ "$IND" = none ] || EV=$EV,raw-$IND

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
    sleep $MINSLEEP
    w=$MINSLEEP
    while [ "$(temp)" -gt "$COOL" ] && [ $w -lt $MAXWAIT ]; do sleep 2; w=$((w + 2)); done
}

# reference outputs: seed 0 of every variant
mkdir -p ref
grep ' 0 ' "$LIST" | while read -r opt v seed bin; do
    taskset $MASK ./$bin > "ref/${opt}_$v" 2>&1 || echo "FAIL reference $opt $v" >&2
done

: > "$OUT"
while IFS= read -r l; do echo "$RANDOM $l"; done < "$LIST" | sort -k1,1n | cut -d' ' -f2- > "$OUT.order"
while read -r opt v seed bin; do
    cooldown
    t0=$(temp)
    taskset $MASK ./pstat -o "$OUT.p" -e "$EV" -- ./$bin > "$OUT.o" 2>&1
    rc=$?
    t1=$(temp)
    if [ $rc -ne 0 ] || ! cmp -s "$OUT.o" "ref/${opt}_$v"; then
        echo "WRONG RESULT $opt $v seed $seed rc=$rc: $(head -c 100 "$OUT.o")" >&2
        continue
    fi
    if grep -q scaled "$OUT.p"; then echo "MULTIPLEXED $opt $v seed $seed" >&2; fi
    awk -F, -v o=$opt -v v=$v -v s=$seed -v t0=$t0 -v t1=$t1 -v ind="raw-$IND" '
        $3=="task-clock"   { tc=$1 }
        $3=="cycles"       { c=$1 }
        $3=="instructions" { n=$1 }
        $3 ~ /^raw-0x21/   { br=$1 }
        $3 ~ /^raw-0x22/   { m=$1 }
        $3 == ind          { mi=$1 }
        $3 ~ /^raw-0x7a/   { is=$1 }
        END { if (ind == "raw-none") printf "%s %s %s %s %s NA NA %s  %s %s %.3f %d %d\n", o, v, s, c, n, m, br, is, (tc>0? c/(tc*1e6) : 0), t0, t1
              else printf "%s %s %s %s %s %d %s %s  %s %s %.3f %d %d\n", o, v, s, c, n, m - mi, mi, m, br, is, (tc>0? c/(tc*1e6) : 0), t0, t1 }
    ' "$OUT.p" >> "$OUT"
done < "$OUT.order"
rm -f "$OUT.order" "$OUT.p" "$OUT.o"
touch "$OUT.done"
