#!/usr/bin/env python3
"""usage: analysis/compiler_versions.py [out_file]

Dispatch indirect-jump count of Lua 5.4.8 luaV_execute across compiler versions
(paper 5.3, task 3).  Compile only, through the Compiler Explorer API (godbolt.org):
lvm.c and the Lua headers are sent as they are (public source, no local paths), each
compiler uses its own system headers, and the assembly of luaV_execute is scanned for
indirect jumps (x86-64 jmp *, AArch64 br, AArch32 bx/ldr pc/...).
Modes: cgoto (-DLUA_USE_JUMPTABLE=1) and cgotonm (cgoto with tail merging off:
gcc -fno-crossjumping, clang -mllvm -enable-tail-merge=false).
output line: arch compiler version mode jumps
"""
import json, os, re, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "third_party", "lua-5.4.8", "src")
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "results", "analysis", "compiler_versions.txt")
API = "https://godbolt.org/api/compiler/{}/compile"
BASE = "-O2 -std=gnu99 -fPIE -DLUA_COMPAT_5_3 -DLUA_USE_JUMPTABLE=1"

# (arch, family, compiler id, version); one release per major version
X86_GCC = "cg447 cg494 cg540 cg65 cg75 cg85 cg95 cg105 cg115 cg125 cg134 cg143 cg152 cg162".split()
X86_CLANG = ("cclang352 cclang391 cclang401 cclang502 cclang601 cclang710 cclang801 cclang901 cclang1001 "
             "cclang1101 cclang1201 cclang1301 cclang1400 cclang1500 cclang1600 cclang1701 cclang1810 "
             "cclang1910 cclang2010 cclang2110 cclang2210 cclang2310").split()
A64_GCC = ("carm64g494 caarchg54 carm64g640 carm64g750 carm64g850 carm64g950 carm64g1050 carm64g1140 "
           "carm64g1250 carm64g1340 carm64g1430 carm64g1520 carm64g1620").split()
A64_CLANG = [f"armv8-cclang{v}" for v in
             "901 1001 1101 1201 1301 1400 1500 1600 1701 1810 1910 2010 2110 2210 2310".split()]
COMPILERS = ([("x86-64", "gcc", c) for c in X86_GCC] + [("x86-64", "clang", c) for c in X86_CLANG] +
             [("aarch64", "gcc", c) for c in A64_GCC] + [("aarch64", "clang", c) for c in A64_CLANG])

if os.environ.get("ONLY"):   # e.g. ONLY=cg162,cclang2310
    COMPILERS = [c for c in COMPILERS if c[2] in os.environ["ONLY"].split(",")]

JUMP = {
    "x86-64": re.compile(r"^\s*(notrack\s+)?jmpq?\s+\*"),
    "aarch64": re.compile(r"^\s*br\s+x\d+"),
}
FUNC_END = re.compile(r"^[A-Za-z_$][\w$]*:")      # next non-local label

def version(cid):
    return compilers.get(cid, cid)

def compile_asm(cid, flags):
    files = [{"filename": f, "contents": open(os.path.join(SRC, f)).read()}
             for f in sorted(os.listdir(SRC)) if f.endswith(".h")]
    body = {
        "source": open(os.path.join(SRC, "lvm.c")).read(),
        "options": {"userArguments": flags,
                    "filters": {"labels": True, "directives": True, "commentOnly": True,
                                "libraryCode": True, "intel": False, "demangle": False}},
        "files": files, "lang": "c", "allowStoreCodeDebug": False,
    }
    req = urllib.request.Request(API.format(cid), data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json", "Accept": "application/json",
                                          "User-Agent": "dispatch-jump-count-script"})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)
        except Exception as e:  # rate limit or transient error: back off
            err = e; time.sleep(10 * (attempt + 1))
    raise err

def count_jumps(res, arch):
    lines = [a.get("text", "") for a in res.get("asm", [])]
    try:
        start = next(i for i, l in enumerate(lines) if l.startswith("luaV_execute:"))
    except StopIteration:
        return None
    n = 0
    for l in lines[start + 1:]:
        if FUNC_END.match(l):
            break
        n += bool(JUMP[arch].match(l))
    return n

with urllib.request.urlopen(urllib.request.Request(
        "https://godbolt.org/api/compilers/c?fields=id,name",
        headers={"Accept": "application/json", "User-Agent": "dispatch-jump-count-script"}), timeout=60) as r:
    compilers = {c["id"]: c["name"] for c in json.load(r)}

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w") as out:
    out.write(f"# analysis/compiler_versions.py  {time.strftime('%Y-%m-%d')}  flags: {BASE}\n")
    out.write("# arch compiler mode jumps  (cgotonm: tail merging off)\n")
    for arch, fam, cid in COMPILERS:
        for mode in ("cgoto", "cgotonm"):
            nm = "" if mode == "cgoto" else (" -fno-crossjumping" if fam == "gcc" else " -mllvm -enable-tail-merge=false")
            res = compile_asm(cid, BASE + nm)
            n = count_jumps(res, arch)
            if n is None:
                errs = " | ".join(s.get("text", "") for s in res.get("stderr", []) if "error" in s.get("text", ""))[:200]
                n = f"ERROR({errs or 'no luaV_execute'})"
            line = f"{arch:8} {version(cid):24} {mode:8} {n}"
            print(line, flush=True); out.write(line + "\n"); out.flush()
            time.sleep(1.5)
