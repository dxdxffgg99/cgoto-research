#!/bin/bash
# usage: analysis/llcpatch_llc.sh <workdir>     (on the host with the patched LLVM build)
#   <workdir>/bc/<name>.bc (from analysis/llcpatch_real.sh emit) -> <workdir>/obj/<name>.{on,off}.o
#   with llc built from llvm/llvm-project PR #245624: "on" = default, "off" = -tail-dup-indirect-tail-call-size=0.
#   llc gets the options each build passes to clang that are not recorded in the bitcode
#   (optimization level, -ffunction-sections/-fdata-sections, PIC/PIE).
#   env: LLC=~/llvm-pr/build/bin/llc  TRIPLE=aarch64-linux-gnu (x86_64-pc-linux-gnu for x86-64 bitcode)
#   "br x" / "jmp *" = indirect branches (AArch64 / x86-64) in the object.
set -eu
W=$1; LLC=${LLC:-~/llvm-pr/build/bin/llc}; TRIPLE=${TRIPLE:-aarch64-linux-gnu}
cd "$W"; mkdir -p obj
declare -A F=([wamr_tail]="-O3 -function-sections -data-sections" [wamr_tailpn]="-O3 -function-sections -data-sections"
              [lua_tail]="-O2" [lua_tailpn]="-O2" [cpython]="-O3")
D=$(dirname "$LLC")
for f in bc/*.bc; do
  n=$(basename "$f" .bc)
  [ -n "${F[$n]:-}" ] || { echo "unknown $n" >&2; exit 1; }
  for m in on off; do
    x=""; [ $m = off ] && x=-tail-dup-indirect-tail-call-size=0
    "$LLC" ${F[$n]} -mtriple=$TRIPLE -relocation-model=pic $x -filetype=obj -o obj/$n.$m.o "$f"
  done
  a=$("$D/llvm-objdump" -d --no-show-raw-insn obj/$n.off.o | grep -cE '\sbr\s+x|\sjmpq?\s+\*')
  b=$("$D/llvm-objdump" -d --no-show-raw-insn obj/$n.on.o | grep -cE '\sbr\s+x|\sjmpq?\s+\*')
  ta=$("$D/llvm-size" -A obj/$n.off.o | awk '$1 ~ /^\.text/ {t+=$2} END{print t}')
  tb=$("$D/llvm-size" -A obj/$n.on.o | awk '$1 ~ /^\.text/ {t+=$2} END{print t}')
  printf "%-12s %-40s .text %7d -> %7d (%+.1f%%)  indirect br %4d -> %4d\n" $n "${F[$n]}" $ta $tb \
    "$(awk -v a=$ta -v b=$tb 'BEGIN{print 100*(b-a)/a}')" $a $b
done
"$LLC" --version | head -3
