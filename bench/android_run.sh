#!/system/bin/sh
# Android (adb shell) measurement runner. POSIX sh / mksh, toybox tools only.
# usage: sh android_run.sh <list> <out> [rounds=5]
#   <list> lines:  name|workdir|expected-output-regex|command
#   (lines starting with # are ignored; name may contain a space, e.g. "Richards lua_cgoto_clang")
#   expected-output-regex "-": check the exit status only (for commands whose output is discarded)
#   env: MASK=80 (prime core cpu7)  COOL=40 (deg C)  MINSLEEP=10  MAXWAIT=180
#        EV=task-clock,cycles,instructions,raw-0x21,raw-0x22,raw-0x7a
# raw line: round name time_s cycles instructions branches branch_misses ghz temp_before temp_after loadavg indirect_spec
#   branches = BR_RETIRED (0x21), branch_misses = BR_MIS_PRED_RETIRED (0x22), indirect_spec = BR_INDIRECT_SPEC (0x7a)
# Clock frequency cannot be fixed without root: compare cycles, not time.
#   INDEV=0x118: also count that raw event (indirect mispredictions on Cortex-A76) and append it
#   as a 13th column; without INDEV the output is unchanged.
LIST=$1; OUT=$2; ROUNDS=${3:-5}
case $OUT in /*) ;; *) OUT=$(pwd)/$OUT ;; esac   # runs cd into workdirs
MASK=${MASK:-80}; COOL=${COOL:-40}; MINSLEEP=${MINSLEEP:-10}; MAXWAIT=${MAXWAIT:-180}
EV=${EV:-task-clock,cycles,instructions,raw-0x21,raw-0x22,raw-0x7a}
INDEV=${INDEV:-}
[ -n "$INDEV" ] && EV="$EV,raw-$INDEV"
D=$(cd "$(dirname "$0")" && pwd)
PSTAT=$D/pstat

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

: > "$OUT"
i=1
while [ $i -le $ROUNDS ]; do
    grep -v '^#' "$LIST" | grep -v '^$' | while IFS= read -r l; do echo "$RANDOM|$l"; done \
        | sort -t'|' -k1,1n | cut -d'|' -f2- > "$OUT.order"
    while IFS='|' read -r name dir check cmd; do
        cooldown
        t0=$(temp)
        # stdin from /dev/null: a program that reads stdin (WAMR c-ray) must not eat the run list
        (cd "$dir" && taskset $MASK "$PSTAT" -o "$OUT.p" -e "$EV" -- sh -c "exec $cmd" < /dev/null > "$OUT.o" 2>&1)
        rc=$?
        t1=$(temp)
        if [ $rc -ne 0 ] || { [ "$check" != "-" ] && ! grep -qE "$check" "$OUT.o"; }; then
            echo "FAIL round=$i $name rc=$rc: $(head -c 200 "$OUT.o")" >&2
            continue
        fi
        awk -F, -v i=$i -v n="$name" -v t0=$t0 -v t1=$t1 -v la="$(cut -d' ' -f1 /proc/loadavg)" -v ie="$INDEV" '
            ie != "" && $3=="raw-" ie { im=$1 }
            $3=="task-clock"   { tc=$1 }
            $3=="time-elapsed" { t=$1 }
            $3=="cycles"       { c=$1 }
            $3=="instructions" { n2=$1 }
            $3=="raw-0x21"     { br=$1 }
            $3=="raw-0x22"     { m=$1 }
            $3=="raw-0x7a"     { ind=$1 }
            END { printf "%d %s %s %s %s %s %s %.3f %d %d %s %s", i, n, t, c, n2, br, m, (tc>0? c/(tc*1e6) : 0), t0, t1, la, ind
                  if (ie != "") printf " %s", im
                  printf "\n" }
        ' "$OUT.p" | tee -a "$OUT"
    done < "$OUT.order"
    i=$((i + 1))
done
rm -f "$OUT.order" "$OUT.p" "$OUT.o"
