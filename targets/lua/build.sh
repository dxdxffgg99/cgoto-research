#!/bin/bash
# usage: targets/lua/build.sh [out_dir]      (OPT=-O2 by default)
# builds lua_{switch,cgoto,tail,tailpn}_{gcc,clang} into <out_dir>/bin
#   tailpn = tail + __attribute__((preserve_none)) on handlers (as CPython does)
#   extra modes (MODES="cgotonm cgotobf"): dispatch-merging experiment
#   cgotonm = cgoto with tail merging off, cgotobf = branch-free dispatch (patch_bf.py)
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
HERE=$ROOT/targets/lua
V=5.4.8
SHA=4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae
TP=$ROOT/third_party
SRC=$TP/lua-$V
OUT=${1:-$ROOT/build/lua}
OPT=${OPT:--O2}
# FIXED_SEED=1 (default): constant string-hash seed instead of time/address based,
# so table layouts are identical from run to run (use with ASLR off, see run.sh)
FIXED_SEED=${FIXED_SEED:-1}
SEEDDEF=""; [ "$FIXED_SEED" = 1 ] && SEEDDEF="'-Dluai_makeseed(L)=0x2545F491u'"

if [ ! -d "$SRC" ]; then
    mkdir -p "$TP"
    curl -sSfL -o "$TP/lua-$V.tar.gz" "https://www.lua.org/ftp/lua-$V.tar.gz"
    echo "$SHA  $TP/lua-$V.tar.gz" | sha256sum -c -
    tar xzf "$TP/lua-$V.tar.gz" -C "$TP"
fi

mkdir -p "$OUT/bin"
for cc in ${CCS:-gcc clang}; do
    command -v $cc >/dev/null || { echo "skip $cc (not found)" >&2; continue; }
    # some systems (Termux, macOS) ship "gcc" as an alias of clang
    if [ $cc = gcc ] && gcc --version 2>/dev/null | grep -q clang; then echo "skip gcc (it is clang)" >&2; continue; fi
    for mode in ${MODES:-switch cgoto tail tailpn}; do
        d=$OUT/src_${mode}_$cc
        rm -rf "$d"; cp -r "$SRC/src" "$d"
        XF=""
        case $mode in
            switch) DEF="-DLUA_USE_JUMPTABLE=0" ;;
            cgoto)  DEF="-DLUA_USE_JUMPTABLE=1" ;;
            # cgoto with the compiler's tail merging off (keeps per-handler dispatch jumps)
            cgotonm) DEF="-DLUA_USE_JUMPTABLE=1"
                    if [ $cc = gcc ]; then XF="-fno-crossjumping"; else XF="-mllvm -enable-tail-merge=false"; fi ;;
            # cgoto with the hook check folded into the dispatch index (no branch before the jump)
            cgotobf) DEF="-DLUA_USE_JUMPTABLE=1"
                    python3 -I "$HERE/patch_bf.py" "$d" ;;
            tail)   DEF="-DLUA_USE_JUMPTABLE=0 -DLUA_USE_TAILCALL=1"
                    python3 -I "$HERE/gen_tail.py" "$SRC/src/lvm.c" "$d" >/dev/null ;;
            tailpn) DEF="-DLUA_USE_JUMPTABLE=0 -DLUA_USE_TAILCALL=1 -DLUA_TAIL_PRESERVE_NONE=1"
                    python3 -I "$HERE/gen_tail.py" "$SRC/src/lvm.c" "$d" >/dev/null ;;
        esac
        make -s -C "$d" linux CC="$cc" \
            CFLAGS="$OPT -Wall -Wextra -DLUA_COMPAT_5_3 -DLUA_USE_LINUX $DEF $XF $SEEDDEF" >/dev/null
        cp "$d/lua" "$OUT/bin/lua_${mode}_$cc"
    done
done
ls "$OUT/bin"
