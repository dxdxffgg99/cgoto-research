#!/bin/bash
# usage: ./run.sh            (on an AArch64 Linux machine with a Cortex-A76 / A76-family core)
#   For PAD = 0..15 (4-byte nops at the top of jeven), with and without
#   -mllvm -tail-dup-size=4: builds collapse.c, prints the rule's prediction (predict.py),
#   and counts indirect-branch mispredictions (Cortex-A76 raw PMU event 0x118) and cycles.
#   env: CC=clang  CPU=3 (core to pin to)  PSTAT=<path to bench/pstat> to use it instead of perf
set -eu
cd "$(dirname "$0")"
CC=${CC:-clang}; CPU=${CPU:-3}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
count() {   # prints: indirect_mispredictions cycles output
    if [ -n "${PSTAT:-}" ]; then
        out=$(taskset -c $CPU "$PSTAT" -o "$W/c" -e raw-0x118,cycles -- "$1")
        echo "$(awk -F, '$3=="raw-0x118"{print $1}' "$W/c") $(awk -F, '$3=="cycles"{print $1}' "$W/c") $out"
    else
        out=$(taskset -c $CPU perf stat -x, -o "$W/c" -e r118:u,cycles:u -- "$1")
        echo "$(awk -F, '/r118/{print $1}' "$W/c") $(awk -F, '/cycles/{print $1}' "$W/c") $out"
    fi
}
$CC --version | head -1
printf "%-24s %3s  %-14s %10s %8s  %s\n" flags PAD measured ind_misp Gcycles prediction
for flags in "" "-mllvm -tail-dup-size=4"; do
    for pad in $(seq 0 15); do
        $CC -O2 -falign-functions=256 -DPAD=$pad $flags -o "$W/t" collapse.c
        read -r ind cyc out <<< "$(count "$W/t")"
        [ "$out" = 277182223 ] || { echo "wrong output $out"; exit 1; }
        verdict=$([ "$ind" -gt 10000000 ] && echo COLLAPSE || echo normal)
        printf "%-24s %3d  %-14s %10d %8.2f  %s\n" "${flags:-default}" $pad $verdict $ind "$(awk -v c="$cyc" 'BEGIN { print c / 1e9 }')" "$(python3 -I predict.py "$W/t")"
        sleep 1
    done
done
