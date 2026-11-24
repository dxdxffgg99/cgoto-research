#!/bin/bash
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OPT=${OPT:--O2}
O=${1:-$ROOT/build}
mkdir -p "$O"

for cc in gcc clang; do
    if ! command -v $cc >/dev/null; then echo "skip $cc (not found)" >&2; continue; fi
    # some systems (Termux, macOS) ship "gcc" as an alias of clang
    if [ $cc = gcc ] && gcc --version 2>/dev/null | grep -q clang; then echo "skip gcc (it is clang)" >&2; continue; fi
    $cc $OPT -o "$O/switch_$cc"   "$ROOT/src/switch.c"
    $cc $OPT -o "$O/cgoto_$cc"    "$ROOT/src/cgoto.c"
    $cc $OPT -o "$O/musttail_$cc" "$ROOT/src/musttail.c"
    $cc $OPT -o "$O/mtargs_$cc"   "$ROOT/src/musttail_args.c"
    $cc $OPT -fno-pie -no-pie -o "$O/mtnopie_$cc" "$ROOT/src/musttail.c"
done
ls "$O"
