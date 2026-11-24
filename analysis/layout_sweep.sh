#!/bin/bash
# usage: analysis/layout_sweep.sh <src.c> <cc> <opt> [extra cflags...]
#   Shifts the code of the jeven/jnei handlers by K = 0..MAXK bytes (".nops K" after the
#   function label), rebuilds, and measures cycles / branch misses for every K.
#   Tells whether a misprediction anomaly depends on code placement.
#   env: CPU=3 MAXK=31 STEP=1 OUT=results/analysis/sweep_<name>.txt
# output line: K jeven_jne_block jeven_jmp_block jnei_jne_block jnei_jmp_block cycles branch_misses
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$1; CC=$2; OPT=$3; shift 3
EXTRA="$*"
CPU=${CPU:-3}; MAXK=${MAXK:-31}; STEP=${STEP:-1}
NAME=$(basename "$SRC" .c)_${CC}${OPT}$(echo "$EXTRA" | tr -d ' -')
OUT=${OUT:-$ROOT/results/analysis/sweep_$NAME.txt}
mkdir -p "$(dirname "$OUT")"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

P=""; [ -d /sys/devices/cpu_core ] && P=cpu_core/
ev() { [ -n "$P" ] && echo "$P$1/" || echo "$1"; }

$CC $OPT $EXTRA -S -o "$W/base.s" "$SRC"
echo "# $CC $OPT $EXTRA  src=$SRC  cpu=$CPU  $(date -Is)" > "$OUT"
for K in $(seq 0 $STEP $MAXK); do
    python3 -I - "$W/base.s" "$W/k$K.s" "$K" <<'EOF'
import re, sys
src, dst, k = sys.argv[1], sys.argv[2], int(sys.argv[3])
s = open(src).read()
for fn in ("jeven", "jnei"):
    s, n = re.subn(rf"^({fn}:[^\n]*)$", (rf"\1\n\t.nops {k}" if k else r"\1"), s, flags=re.M)
    assert n == 1, (fn, n)
open(dst, "w").write(s)
EOF
    $CC $OPT $EXTRA "$W/k$K.s" -o "$W/k$K"
    blocks=$(objdump -d --no-show-raw-insn "$W/k$K" | awk '
        /^[0-9a-f]+ <(jeven|jnei)>:/ {f=$2; seen=0} /^$/ {f=""}
        f && /\tj[a-z]+ / { split($1, a, ":"); b = int(strtonum("0x" a[1]) / 32)
            if ($2 !~ /jmp/ && !seen) { jne[f] = b }
            if ($0 ~ /jmp +\*/ && !seen) { jmp[f] = b; seen = 1 } }
        END { printf "%x %x %x %x", jne["<jeven>:"], jmp["<jeven>:"], jne["<jnei>:"], jmp["<jnei>:"] }')
    sleep 2
    r=$(taskset -c $CPU perf stat -x, -e $(ev cycles),$(ev branch-misses) "$W/k$K" 2>&1 >/dev/null \
        | awk -F, '/cycles/{c=$1} /branch-misses/{m=$1} END{print c, m}')
    echo "$K $blocks $r" | tee -a "$OUT"
done
