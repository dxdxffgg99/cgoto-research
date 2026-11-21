#!/bin/bash
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
O=${1:-$ROOT/build}
mkdir -p "$O"

for cc in gcc clang; do
    if ! command -v $cc >/dev/null; then echo "skip $cc (not found)" >&2; continue; fi
    $cc -O2 -o "$O/switch_$cc"   "$ROOT/src/switch.c"
    $cc -O2 -o "$O/cgoto_$cc"    "$ROOT/src/cgoto.c"
    $cc -O2 -o "$O/musttail_$cc" "$ROOT/src/musttail.c"
    $cc -O2 -o "$O/mtargs_$cc"   "$ROOT/src/musttail_args.c"
    $cc -O2 -fno-pie -no-pie -o "$O/mtnopie_$cc" "$ROOT/src/musttail.c"
done
ls "$O"
