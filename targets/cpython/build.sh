#!/bin/bash
# usage: targets/cpython/build.sh [out_dir]
#   builds CPython with switch / computed-goto / tail-call dispatch, for gcc and clang
#   env: CCS="gcc clang"  MODES="switch cgoto tail"  JOBS=$(nproc)  EXTRA_CONF=""  PGO=0|1
#   result: <out_dir>/<mode>_<cc>/bin/python3   (installed with make altinstall)
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
V=3.15.2
SHA=8b5536d280142ecf6cdfe15d12a21ba1c65e300bbf7b28a8d0cdb849575797de
TP=$ROOT/third_party
SRC=$TP/Python-$V
# PGO=1: --enable-optimizations --with-lto (PGO training needs the test modules)
PGO=${PGO:-0}
if [ "$PGO" = 1 ]; then DEFOUT=$ROOT/build/cpython-pgo; BASECONF="--enable-optimizations --with-lto"
else DEFOUT=$ROOT/build/cpython; BASECONF="--disable-test-modules"; fi
OUT=$(mkdir -p "${1:-$DEFOUT}" && cd "${1:-$DEFOUT}" && pwd)
CCS=${CCS:-"gcc clang"}
MODES=${MODES:-"switch cgoto tail"}
JOBS=${JOBS:-$(nproc)}

if [ ! -d "$SRC" ]; then
    mkdir -p "$TP"
    curl -sSfL -o "$TP/Python-$V.tar.xz" "https://www.python.org/ftp/python/$V/Python-$V.tar.xz"
    echo "$SHA  $TP/Python-$V.tar.xz" | sha256sum -c -
    tar xJf "$TP/Python-$V.tar.xz" -C "$TP"
fi

for cc in $CCS; do
    command -v $cc >/dev/null || { echo "skip $cc (not found)" >&2; continue; }
    # some systems (Termux, macOS) ship "gcc" as an alias of clang
    if [ $cc = gcc ] && gcc --version 2>/dev/null | grep -q clang; then echo "skip gcc (it is clang)" >&2; continue; fi
    for mode in $MODES; do
        case $mode in
            switch) CONF="--without-computed-gotos" ;;
            cgoto)  CONF="--with-computed-gotos" ;;
            tail)   CONF="--with-tail-call-interp" ;;
        esac
        b=$OUT/obj_${mode}_$cc
        inst=$OUT/${mode}_$cc
        rm -rf "$b" "$inst"; mkdir -p "$b"
        echo "== $mode $cc: $CONF" >&2
        (cd "$b" && "$SRC/configure" -q CC="$cc" --prefix="$inst" $CONF \
                $BASECONF ${EXTRA_CONF:-} > configure.log 2>&1 \
            && make -s -j"$JOBS" > make.log 2>&1 \
            && make -s altinstall > install.log 2>&1) \
            || { echo "FAILED $mode $cc (see $b/*.log)" >&2; exit 1; }
        ln -sf "python${V%.*}" "$inst/bin/python3"
        "$inst/bin/python3" -c 'import sys, sysconfig; print(sys.version.split()[0], sysconfig.get_config_var("CC"), sysconfig.get_config_var("CONFIG_ARGS"))'
    done
done
