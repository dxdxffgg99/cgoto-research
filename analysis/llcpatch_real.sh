#!/bin/bash
# usage: analysis/llcpatch_real.sh emit|link|measure      (on the Cortex-A76 host, from any directory)
#   Real interpreters with the TailDuplicator patch (llvm/llvm-project PR #245624), rule on vs off.
#   Only the dispatch file of each interpreter goes through the patched backend:
#     emit:    clang (21) compiles that file to bitcode with its exact build command
#              -> build/llcpatch/bc/<name>.bc
#     (then, on the LLVM build host: analysis/llcpatch_llc.sh -> build/llcpatch/obj/<name>.{on,off}.o)
#     link:    the rest of each build is reused; the object is replaced in the build's archive and the
#              program relinked with the build's own link command.  The stock program is relinked the
#              same way first and must come out byte-identical.  Outputs are checked against stock.
#     measure: AArch64: bench/android_run.sh (bench/pstat cycles, random order per round), INDEV=0x118
#              x86-64:  analysis/perf_list_run.sh (perf, P-core, turbo off), INDEV=br_misp_retired.indirect
#   Builds reused: build/lua/src_{tail,tailpn}_clang, build/wamr/obj_{tail,tailpn}_clang (pstat_all.sh),
#                  build/cpython/obj_tail_clang (targets/cpython/build.sh, CCS=clang MODES=tail)
#   CPython benchmarks: pyperformance scripts run by pyperf in worker mode (one process, fixed loops)
#     from build/llcpatch/pyperf (pyperf/ and bm_*/ copied from a pyperformance install).
#   env: TAG (cortex-a76 on AArch64; required elsewhere, e.g. i9-14900k)  ROUNDS=5 SUITES="lua wamr cpython"
#        AArch64: MASK=8 COOL=50 MINSLEEP=3 MAXWAIT=60 INDEV=0x118;  x86-64: see analysis/perf_list_run.sh
# outputs: results/llcpatch_{lua,wamr,cpython}_<TAG>_raw.txt (android_run.sh lines + 0x118 column),
#          results/llcpatch_<TAG>_check.txt
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
STEP=${1:-}
ROUNDS=${ROUNDS:-5}; SUITES=${SUITES:-"lua wamr cpython"}
if [ "$(uname -m)" = aarch64 ]; then
    TAG=${TAG:-cortex-a76}; RUNNER="bash bench/android_run.sh"
    export MASK=${MASK:-8} COOL=${COOL:-50} MINSLEEP=${MINSLEEP:-3} MAXWAIT=${MAXWAIT:-60} INDEV=${INDEV:-0x118}
else
    TAG=${TAG:?set TAG, e.g. TAG=i9-14900k}; RUNNER="bash analysis/perf_list_run.sh"
    export INDEV=${INDEV:-br_misp_retired.indirect}
fi
B=$ROOT/build; L=$B/llcpatch; R=$ROOT/results
mkdir -p "$L/bc" "$L/obj" "$L/bin" "$L/tmp"
has() { [[ " $SUITES " == *" $1 "* ]]; }
log() { echo "== [$(date +%T)] $*" >&2; }
# regression tests that do not need the test modules (the build has --disable-test-modules)
PYTESTS="test_grammar test_opcodes test_dict test_generators test_exceptions test_scope test_patma test_unpack test_augassign test_int test_bool test_listcomps test_setcomps test_dictcomps test_coroutines test_asyncgen test_contextlib test_string test_unicode_identifiers"
CPYV=3.15.2; CPYSRC=$ROOT/third_party/Python-$CPYV; CPYOBJ=$B/cpython/obj_tail_clang
LUAF="-O2 -Wall -Wextra -DLUA_COMPAT_5_3 -DLUA_USE_LINUX -DLUA_USE_JUMPTABLE=0 -DLUA_USE_TAILCALL=1 '-Dluai_makeseed(L)=0x2545F491u'"
declare -A SIZE=([DeltaBlue]=12000 [Richards]=100 [Json]=100 [CD]=250 [Havlak]=1500 [Bounce]=1500
                 [List]=1500 [Mandelbrot]=500 [NBody]=250000 [Permute]=1000 [Queens]=1000
                 [Sieve]=3000 [Storage]=1000 [Towers]=600)
# as bench/pstat_all.sh (crayscene: real scene on stdin)
WCASES="coremark|coremark|coremark_wasi_nofp.wasm 0x0 0x0 0x66 2000|crc|^Iterations +:
nbody|nbody|nbody.wasm 3000000|.
fannkuch|fannkuch-redux|fannkuch_redux.wasm 10|.
binarytrees|binary-trees|binary_trees.wasm 14|.
fasta|fasta|fasta.wasm 2000000|-
hashset|hashset|HashSet.wasm|took
raymarcher|raymarcher|raymarcher.wasm|.
crayscene|c-ray|c_ray.wasm -s 1600x1200 < scene|-"
WSRC=$ROOT/third_party/wamr/tests/standalone
# CPython: name|pyperformance dir|loops|extra args   (loops: ~0.6 s on i9-14900K tail_clang)
PCASES="chaos|bm_chaos|11|
comprehensions|bm_comprehensions|39590|
coroutines|bm_coroutines|31|
deepcopy|bm_deepcopy|2284|
deltablue|bm_deltablue|211|
fannkuch|bm_fannkuch|2|
float|bm_float|10|
generators|bm_generators|22|
go|bm_go|6|
hexiom|bm_hexiom|113|
logging|bm_logging|5303|
mdp|bm_mdp|1|
meteor_contest|bm_meteor_contest|6|
nbody|bm_nbody|8|
nqueens|bm_nqueens|8|
pickle_pure_python|bm_pickle|95|--pure-python pickle
unpickle_pure_python|bm_pickle|144|--pure-python unpickle
pyflate|bm_pyflate|2|
raytrace|bm_raytrace|3|
regex_compile|bm_regex_compile|5|
richards|bm_richards|15|
richards_super|bm_richards_super|13|
scimark|bm_scimark|2|
spectral_norm|bm_spectral_norm|8|
unpack_sequence|bm_unpack_sequence|46484|
async_generators|bm_async_generators|2|"

emit1() {   # name dir command (compiles one file with -c -o X)
    local name=$1 dir=$2 cmd=$3
    cmd=$(echo "$cmd" | sed -E "s| -o [^ ]+| -o $L/bc/$name.bc|; s| -c | -emit-llvm -c |")
    echo "$name|$dir|$cmd" >> "$L/bc/commands.txt"
    (cd "$dir" && eval "$cmd") 2> "$L/bc/$name.log"
}
emit() {
    : > "$L/bc/commands.txt"
    if has wamr; then for v in tail tailpn; do
        c=$(python3 -I -c "import json,sys; e=[x for x in json.load(open(sys.argv[1])) if 'wasm_interp_fast' in x['file']][0]; print(e['directory']); print(e['command'])" "$B/wamr/obj_${v}_clang/compile_commands.json")
        emit1 wamr_$v "$(echo "$c" | head -1)" "$(echo "$c" | tail -1)"
    done; fi
    if has lua; then
        emit1 lua_tail "$B/lua/src_tail_clang" "clang $LUAF -c lvm.c -o lvm.o"
        emit1 lua_tailpn "$B/lua/src_tailpn_clang" "clang $LUAF -DLUA_TAIL_PRESERVE_NONE=1 -c lvm.c -o lvm.o"
    fi
    if has cpython; then
        c=$(cd "$CPYOBJ" && timeout 60 make -n -W "$CPYSRC/Python/ceval.c" Python/ceval.o 2>/dev/null | sed 's/^ *//' | grep -E "^clang .*-o Python/ceval.o" | tail -1)
        [ -n "$c" ] || { echo "no ceval.o command" >&2; exit 1; }
        emit1 cpython "$CPYOBJ" "$c"
    fi
    clang --version | head -1 > "$L/bc/clang_version.txt"
    ls -la "$L/bc"
}

# relink(): archive member replaced, link command rewritten; $1=name of output, $2=archive, $3=member,
#           $4=object or "" (stock), $5=dir to link in, $6=link command, $7=archive token, $8=output token
relink() {
    local out=$1 ar=$2 member=$3 obj=$4 dir=$5 cmd=$6 artok=$7 outtok=$8 t=$L/tmp/$1
    rm -rf "$t"; mkdir -p "$t"; cp "$ar" "$t/lib.a"
    if [ -n "$obj" ]; then cp "$obj" "$t/$member"; (cd "$t" && ar r lib.a "$member"); fi
    cmd=${cmd//" $artok "/" $t/lib.a "}
    cmd=${cmd//" $outtok "/" $L/bin/$out "}
    cmd=$(echo "$cmd" | sed -E "s|--dependency-file=[^ ]+|--dependency-file=$t/link.d|")
    (cd "$dir" && eval "$cmd")
}
# relink_obj(): same, for a program linked from objects (static CPython): $1=output, $2=object or "" (stock),
#               $3=dir, $4=link command, $5=object token, $6=output token
relink_obj() {
    local out=$1 obj=$2 dir=$3 cmd=$4 objtok=$5 outtok=$6
    [ -n "$obj" ] && cmd=${cmd//" $objtok "/" $obj "}
    cmd=${cmd//" -o $outtok "/" -o $L/bin/$out "}
    (cd "$dir" && eval "$cmd")
}
check() { echo "$*" | tee -a "$R/llcpatch_${TAG}_check.txt"; }

link() {
    : > "$R/llcpatch_${TAG}_check.txt"
    if has lua; then for v in tail tailpn; do
        d=$B/lua/src_${v}_clang
        relink lua_${v}_stock "$d/liblua.a" lvm.o "" "$d" "clang -o OUT lua.o LIB -lm -Wl,-E -ldl " LIB OUT
        cmp -s "$L/bin/lua_${v}_stock" "$B/lua/bin/lua_${v}_clang" && r=identical || r=DIFFERENT
        check "relink lua_${v}_stock vs lua_${v}_clang: $r"
        for m in off on; do
            relink lua_${v}_llc$m "$d/liblua.a" lvm.o "$L/obj/lua_$v.$m.o" "$d" "clang -o OUT lua.o LIB -lm -Wl,-E -ldl " LIB OUT
        done
        for m in stock llcoff llcon; do
            f=$L/bin/lua_${v}_$m
            (cd third_party/awfy/benchmarks && LUA_PATH="Lua/?.lua;;" "$f" Lua/harness.lua Richards 1 10 2>&1) | grep -q 'runtime:' && r=ok || r=WRONG
            check "lua $(basename "$f") $r"
        done
    done; fi
    if has wamr; then for v in tail tailpn; do
        d=$B/wamr/obj_${v}_clang
        cmd="$(cat "$d/CMakeFiles/iwasm.dir/link.txt") "
        relink iwasm_${v}_stock "$d/libiwasm.a" wasm_interp_fast.c.o "" "$d" "$cmd" libiwasm.a iwasm-2.4.6
        cmp -s "$L/bin/iwasm_${v}_stock" "$B/wamr/bin/iwasm_${v}_clang" && r=identical || r=DIFFERENT
        check "relink iwasm_${v}_stock vs iwasm_${v}_clang: $r"
        for m in off on; do
            relink iwasm_${v}_llc$m "$d/libiwasm.a" wasm_interp_fast.c.o "$L/obj/wamr_$v.$m.o" "$d" "$cmd" libiwasm.a iwasm-2.4.6
        done
    done
    while IFS='|' read -r name dir args keep; do
        ref=""
        for f in "$L"/bin/iwasm_*; do
            if [ "$keep" = - ]; then       # output file or image on stdout; timing on stderr
                fp="$(cd "$WSRC/$dir" && sh -c "exec $f $args 2>/dev/null" < /dev/null | md5sum | cut -c1-12)"
            elif [ "$name" = hashset ]; then   # prints only "That took X seconds."
                fp="$(cd "$WSRC/$dir" && sh -c "exec $f $args" < /dev/null 2>&1 | grep -cE "$keep")"
            else
                fp="$(cd "$WSRC/$dir" && sh -c "exec $f $args" < /dev/null 2>&1 | grep -E "$keep" | md5sum | cut -c1-12)"
            fi
            [ -z "$ref" ] && ref=$fp
            [ "$fp" = "$ref" ] && r=ok || r="WRONG ($fp vs $ref)"
            check "wamr $name $(basename "$f") $r"
        done
    done <<< "$WCASES"; fi
    if has cpython; then
        c=$(cd "$CPYOBJ" && timeout 60 make -n -W Programs/python.o python 2>/dev/null | sed 's/^ *//' | grep -E "^clang .*-o python " | tail -1)
        [ -n "$c" ] || { echo "no python link command" >&2; exit 1; }
        [[ "$c " == *" Python/ceval.o "* ]] || { echo "python link command has no Python/ceval.o" >&2; exit 1; }
        echo "$c" > "$L/tmp/python_link.txt"
        relink_obj python_stock "" "$CPYOBJ" "$c " Python/ceval.o python
        cmp -s "$L/bin/python_stock" "$CPYOBJ/python" && r=identical || r=DIFFERENT
        check "relink python_stock vs obj_tail_clang/python: $r"
        for m in off on; do relink_obj python_llc$m "$L/obj/cpython.$m.o" "$CPYOBJ" "$c " Python/ceval.o python; done
        # the build-tree python finds its stdlib through pybuilddir.txt next to the executable
        for m in stock llcoff llcon; do
            cp "$L/bin/python_$m" "$CPYOBJ/python_$m"
            out=$(cd "$L/pyperf" && PYTHONPATH="$L/pyperf" PYTHONHASHSEED=0 "$CPYOBJ/python_$m" bm_richards/run_benchmark.py --worker -l 1 -w 0 -n 1 2>&1 | tail -1)
            case $out in *richards*) r=ok ;; *) r="WRONG ($out)" ;; esac
            check "cpython python_$m $r"
            # the test package from the source tree (an installed --disable-test-modules build has none)
            mkdir -p "$L/pytests"; ln -sfn "$CPYSRC/Lib/test" "$L/pytests/test"
            out=$(PYTHONPATH="$L/pytests" "$CPYOBJ/python_$m" -m test -q $PYTESTS 2>&1 | tail -1)
            case $out in *SUCCESS*) r=ok ;; *) r="WRONG ($out)" ;; esac
            check "cpython python_$m regression tests: $r"
        done
    fi
    for f in "$L"/bin/*; do echo "$(basename "$f") $(sha256sum < "$f" | cut -c1-16)"; done >> "$R/llcpatch_${TAG}_check.txt"
    grep -c WRONG "$R/llcpatch_${TAG}_check.txt" || true
}

measure() {
    if grep -qE "WRONG|DIFFERENT" "$R/llcpatch_${TAG}_check.txt"; then echo "check failed, see $R/llcpatch_${TAG}_check.txt" >&2; exit 1; fi
    if has lua; then
        : > "$L/lua.list"
        for b in "${!SIZE[@]}"; do for v in tail tailpn; do for m in stock llcoff llcon; do
            echo "$b lua_${v}_$m|$ROOT/third_party/awfy/benchmarks|runtime:|env LUA_PATH=Lua/?.lua\\;\\; setarch $(uname -m) -R $L/bin/lua_${v}_$m Lua/harness.lua $b 1 ${SIZE[$b]}" >> "$L/lua.list"
        done; done; done
        log "measure lua"
        $RUNNER "$L/lua.list" "$R/llcpatch_lua_${TAG}_raw.txt" $ROUNDS
    fi
    if has wamr; then
        : > "$L/wamr.list"
        while IFS='|' read -r name dir args keep; do for v in tail tailpn; do for m in stock llcoff llcon; do
            f=$L/bin/iwasm_${v}_$m
            if [ "$keep" = - ]; then echo "$name iwasm_${v}_$m|$WSRC/$dir|-|$f $args > /dev/null" >> "$L/wamr.list"
            else echo "$name iwasm_${v}_$m|$WSRC/$dir|$keep|$f $args" >> "$L/wamr.list"; fi
        done; done; done <<< "$WCASES"
        log "measure wamr"
        $RUNNER "$L/wamr.list" "$R/llcpatch_wamr_${TAG}_raw.txt" $ROUNDS
    fi
    if has cpython; then
        : > "$L/cpython.list"
        while IFS='|' read -r name dir loops extra; do for m in stock llcoff llcon; do
            echo "$name python_tail_$m|$L/pyperf/$dir|[0-9] [mun]?s|env PYTHONPATH=$L/pyperf PYTHONHASHSEED=0 setarch $(uname -m) -R $CPYOBJ/python_$m run_benchmark.py --worker -l $loops -w 0 -n 1 $extra" >> "$L/cpython.list"
        done; done <<< "$PCASES"
        log "measure cpython"
        $RUNNER "$L/cpython.list" "$R/llcpatch_cpython_${TAG}_raw.txt" $ROUNDS
    fi
    log "measure done"
}

case $STEP in
    emit) emit ;;
    link) link ;;
    measure) measure ;;
    *) echo "usage: $0 emit|link|measure" >&2; exit 2 ;;
esac
