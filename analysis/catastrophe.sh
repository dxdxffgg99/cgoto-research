#!/bin/bash
# usage: analysis/catastrophe.sh [tag]
#   For every binary kept by layout_dist.sh (indirect mispredictions exploded), find the
#   indirect jumps that mispredict (precise sampling) and print their addresses, so that
#   common address relations between colliding jumps can be looked for.
#   env: CPU=3
# output: results/analysis/catastrophe_<tag>.txt
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
TAG=${1:-$(hostname 2>/dev/null || echo host)}
CPU=${CPU:-3}
KEEP=results/analysis/catastrophe_$TAG
OUT=results/analysis/catastrophe_$TAG.txt
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
EV=br_misp_retired.all_branches:upp
[ -d /sys/devices/cpu_core ] && EV=cpu_core/br_misp_retired.all_branches/upp

{
echo "# binary: top mispredicting branches (share%, symbol+off, address, kind, distance to other top indirect jumps)"
for b in "$KEEP"/*; do
    [ -f "$b" ] || continue
    sleep 1
    taskset -c $CPU perf record -q -e "$EV" -c 10007 -o "$W/perf.data" "$b" > /dev/null 2>&1 || continue
    objdump -d --no-show-raw-insn "$b" > "$W/dis.txt"
    echo "== $(basename "$b")"
    # per-instruction share as "symbol+offset" (independent of the PIE load address)
    perf report -i "$W/perf.data" --stdio --sort sym,srcline -F overhead,srcline --no-children 2>/dev/null \
        | grep -vE '^#|^$' | awk '$1+0 >= 1.0 {print $1, $2}' | head -8 > "$W/top.txt"
    addrs=""
    while read pct so; do
        sym=${so%+*}; off=${so##*+}
        base=$(nm "$b" | awk -v s="$sym" '$3==s {print $1; exit}')
        [ -n "$base" ] || continue
        a=$(printf "%x" $((16#$base + off)))
        ins=$(grep -E "^ +$a:" "$W/dis.txt" | head -1 | sed 's/^ *[0-9a-f]*:[[:space:]]*//')
        kind=cond; [[ $ins == jmp* ]] && kind=indirect
        printf "  %6s  %-14s 0x%-6s %-8s %s\n" "$pct" "$so" "$a" "$kind" "$ins"
        [ $kind = indirect ] && addrs="$addrs $a"
    done < "$W/top.txt"
    # pairwise address relations between the mispredicting indirect jumps
    set -- $addrs
    for x in "$@"; do for y in "$@"; do
        [[ $x < $y ]] || continue
        dx=$((16#$y - 16#$x)); xr=$((16#$x ^ 16#$y))
        printf "    pair 0x%s 0x%s  distance=%d (0x%x)  xor=0x%x  same64B=%s same4K=%s\n" $x $y $dx $dx $xr \
            $([ $((16#$x / 64)) = $((16#$y / 64)) ] && echo y || echo n) $([ $((16#$x / 4096)) = $((16#$y / 4096)) ] && echo y || echo n)
    done; done
done
} | tee "$OUT"
