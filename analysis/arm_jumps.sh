#!/bin/bash
# usage: analysis/arm_jumps.sh
#   Dispatch indirect-jump count of Lua luaV_execute on ARM, compile only (paper 5.3):
#   cross-compiles lvm.c with arm-none-eabi-gcc (AArch32; no AArch64 gcc here, and
#   Termux has no gcc) and clang (AArch64 and AArch32 targets), using the newlib
#   headers of the arm-none-eabi toolchain.  Modes as in targets/lua/build.sh:
#   switch, cgoto, cgotonm (tail merging off).
#   env: OPT=-O2
# output: results/analysis/arm_jumps.txt
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC=$ROOT/third_party/lua-5.4.8/src
OPT=${OPT:--O2}
OUT=$ROOT/results/analysis/arm_jumps.txt
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
NEWLIB=/usr/arm-none-eabi/include
BASE="$OPT -DLUA_COMPAT_5_3 '-Dluai_makeseed(L)=0x2545F491u'"

# name | compiler command | objdump | tail-merge-off flag
TARGETS=(
    "gcc-aarch32-thumb2|arm-none-eabi-gcc -mcpu=cortex-a15 -mthumb|arm-none-eabi-objdump|-fno-crossjumping"
    "gcc-aarch32-arm|arm-none-eabi-gcc -mcpu=cortex-a15 -marm|arm-none-eabi-objdump|-fno-crossjumping"
    "clang-aarch64|clang --target=aarch64-none-elf -isystem $NEWLIB|llvm-objdump|-mllvm -enable-tail-merge=false"
    "clang-aarch32-thumb2|clang --target=armv7a-none-eabi -mcpu=cortex-a15 -mthumb -isystem $NEWLIB|arm-none-eabi-objdump|-mllvm -enable-tail-merge=false"
    "clang-x86-64|clang|objdump|-mllvm -enable-tail-merge=false"
    "gcc-x86-64|gcc|objdump|-fno-crossjumping"
)
{
echo "# analysis/arm_jumps.sh $OPT  $(date -I)"
echo "# $(arm-none-eabi-gcc --version | head -1) | $(clang --version | head -1) | $(gcc --version | head -1)"
for t in "${TARGETS[@]}"; do
    IFS='|' read -r name cc od nm <<< "$t"
    for mode in switch cgoto cgotonm; do
        case $mode in
            switch)  DEF="-DLUA_USE_JUMPTABLE=0"; XF="" ;;
            cgoto)   DEF="-DLUA_USE_JUMPTABLE=1"; XF="" ;;
            cgotonm) DEF="-DLUA_USE_JUMPTABLE=1"; XF="$nm" ;;
        esac
        o=$TMP/${name}_$mode.o
        bash -c "$cc $BASE $DEF $XF -c -o $o $SRC/lvm.c"
        printf "%-22s %-8s %s\n" "$name" "$mode" "$(OBJDUMP=$od python3 -I "$ROOT/analysis/dispatch_tails.py" "$o" luaV_execute 3)"
    done
done
} | tee "$OUT"
