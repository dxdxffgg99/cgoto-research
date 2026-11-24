#!/system/bin/sh
# usage (on the Android device, adb shell): sh arm_pmu_probe.sh <out>
#   Runs in its own directory, next to bench/pstat (as ./pstat) and analysis/arm_pmu_probe.c
#   built with the device's clang -O2 (as ./probe).  For every raw PMU event id in the
#   ranges below, counts it while ./probe runs in modes 0/1/2 on the prime core, five
#   events per run.  Used to find the indirect-misprediction event of the Galaxy's
#   Oryon core, which sysfs does not list (paper 6.2a, ARM layout experiment).
# output line: mode event count
cd "$(dirname "$0")"
OUT=$1; : > "$OUT"
MASK=${MASK:-80}
scan() {   # from to (decimal)
    e=$1
    while [ $e -le $2 ]; do
        L=""; j=0
        while [ $j -lt 5 ] && [ $e -le $2 ]; do L="$L,raw-$(printf 0x%x $e)"; e=$((e + 1)); j=$((j + 1)); done
        for m in 0 1 2; do
            taskset $MASK ./pstat -o p.txt -e "${L#,}" -- ./probe $m > /dev/null 2>&1
            awk -F, -v m=$m '$3 ~ /^raw-/ { print m, $3, $1 }' p.txt >> "$OUT"
        done
    done
}
scan 0 1023          # 0x000-0x3ff
scan 16384 16639     # 0x4000-0x40ff
scan 32768 33279     # 0x8000-0x81ff
rm -f p.txt
