#!/bin/bash
# usage: analysis/wamr_spec.sh
#   WAMR's official spec test suite (tests/wamr-test-suites, default proposal, x86-64,
#   fast interpreter) on every dispatch variant: switch / cgoto / tail / tailpn x gcc / clang.
#   The variants are rebuilt with the suite's build options (WAMR_BUILD_SPEC_TEST=1 etc.,
#   as test_wamr.sh sets them) and run through the suite's own all.py.  Downloads the
#   spec repository at the commit test_wamr.sh pins and the wabt 1.0.37 release.
#   env: STEPS="build setup test"  MODES  CCS  JOBS
# output: results/analysis/wamr_spec.txt (summary), build/wamr-spec/logs/<variant>.log
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$ROOT/build/wamr-spec
SUITE=$ROOT/third_party/wamr/tests/wamr-test-suites
STEPS=${STEPS:-"build setup test"}
has() { [[ " $STEPS " == *" $1 "* ]]; }
SPEC_COMMIT=f3a0e06235d2d84bb0f3b5014da4370613886965          # test_wamr.sh, default proposal
WABT_URL=https://github.com/WebAssembly/wabt/releases/download/1.0.37/wabt-1.0.37-ubuntu-20.04.tar.gz
# test_wamr.sh trigger(), fast-interp, no optional proposal
SPEC_CMAKE="-DWAMR_BUILD_TARGET=X86_64 -DWAMR_BUILD_SPEC_TEST=1 -DCOLLECT_CODE_COVERAGE=0
 -DWAMR_BUILD_SHRUNK_MEMORY=0 -DWAMR_BUILD_BULK_MEMORY=1 -DWAMR_BUILD_REF_TYPES=1
 -DWAMR_BUILD_LIBC_WASI=0 -DWAMR_BUILD_MULTI_MODULE=0 -DWAMR_BUILD_MEMORY64=0
 -DWAMR_BUILD_MULTI_MEMORY=0 -DWAMR_BUILD_SIMD=0"

if has build; then
    EXTRA_CMAKE="$SPEC_CMAKE" targets/wamr/build.sh "$W/build" > "$W.build.log" 2>&1 \
        || { echo "build failed: $W.build.log" >&2; exit 1; }
fi

# all.py runs from its work dir and finds iwasm at ../../../product-mini/platforms/linux/build/iwasm
WD=$W/t/s/w
IW=$W/product-mini/platforms/linux/build/iwasm
if has setup; then
    mkdir -p "$WD" "$(dirname "$IW")"
    if [ ! -d "$WD/spec" ]; then
        git clone -q -b main --single-branch https://github.com/WebAssembly/spec "$WD/spec"
        (cd "$WD/spec" && git reset -q --hard $SPEC_COMMIT \
            && git apply --ignore-whitespace "$SUITE/spec-test-script/ignore_cases.patch")
    fi
    if [ ! -x "$WD/wabt/out/gcc/Release/wat2wasm" ]; then
        mkdir -p "$W/dl" "$WD/wabt/out/gcc/Release"
        curl -sSfL -o "$W/dl/wabt.tar.gz" "$WABT_URL"
        tar xzf "$W/dl/wabt.tar.gz" -C "$W/dl"
        cp "$W"/dl/wabt-1.0.37/bin/* "$WD/wabt/out/gcc/Release/"
    fi
    ln -sf "$SUITE/spec-test-script/all.py" "$SUITE/spec-test-script/runtest.py" "$WD/"
fi

if has test; then
    mkdir -p "$W/logs" "$ROOT/results/analysis"
    {
    echo "# analysis/wamr_spec.sh $(date -I): WAMR spec tests (spec $SPEC_COMMIT + ignore_cases.patch), fast interp, x86-64"
    for b in "$W"/build/bin/iwasm_*; do
        v=$(basename "$b")
        ln -sf "$b" "$IW"
        rm -rf "$W/logs/$v.d"; mkdir -p "$W/logs/$v.d"
        (cd "$WD" && python3 all.py -m X86_64 --parl --log "$W/logs/$v.d" > "$W/logs/$v.log" 2>&1) && st=PASS || st=FAIL
        printf "%-20s %s  %s\n" "$v" "$st" "$(grep -E 'IN ALL' "$W/logs/$v.log" | tail -1)"
    done
    } | tee "$ROOT/results/analysis/wamr_spec.txt"
fi
