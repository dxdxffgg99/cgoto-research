#!/usr/bin/env python3
"""usage: analysis/collapse_geometry.py [variant ...]

Why do some layouts collapse (paper 6.2a)?  Rebuilds the layouts of the 100-layout
experiment exactly as analysis/layout_dist.sh does (same source edit, -O2, perturb.py
seeds 0-100, both padding modes) and records, per seed, the address of every indirect
jump and every direct branch (in code order, so the k-th jump of a seed is the same
instruction as the k-th jump of seed 0), with the symbol that contains it.  Joins the
collapse labels of results/analysis/layoutdist_<cpu>[_fixed].txt.
output: results/analysis/collapse_geometry.json
  {variant: {mode: {"labels": {cpu: [collapsed seeds]}, "jumps": {seed: [[addr, sym, kind], ...]}}}}
Needs gcc/clang of the versions used for the measurements (gcc 16.2.1, clang 23.1.5).
"""
import json, os, re, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R = os.path.join(ROOT, "results", "analysis")
SRC = {"switch": "switch.c", "cgoto": "cgoto.c", "musttail": "musttail.c", "mtargs": "musttail_args.c"}
VARIANTS = sys.argv[1:] or [f"{v}_{c}" for v in SRC for c in ("gcc", "clang")]
THRESH = 10_000_000
FIXED_DATA = {"cgoto_clang", "musttail_gcc", "mtargs_gcc"}   # re-measured with mode fixed

def labels(cpu, fixed):
    p = os.path.join(R, f"layoutdist_{cpu}{'_fixed' if fixed else ''}.txt")
    out = {}
    for line in open(p):
        f = line.split()
        if line.startswith("#") or len(f) < 8:
            continue
        out.setdefault(f[1], set())
        if float(f[6]) > THRESH:
            out[f[1]].add(int(f[2]))
    return out

LAB = {(cpu, fx): labels(cpu, fx) for cpu in ("i5-1135g7", "i9-14900k") for fx in (False, True)}
BR = re.compile(r"^\s*([0-9a-f]+):\s+(?:notrack\s+)?(j\w+)\s+(.*)$")
SYM = re.compile(r"^[0-9a-f]+ <([^>]+)>:")

def branches(binary):
    dis = subprocess.run(["objdump", "-d", "--no-show-raw-insn", binary], capture_output=True, text=True).stdout
    sym, out, text = None, [], False
    for ln in dis.split("\n"):
        if ln.startswith("Disassembly of section"):
            text = ".text" in ln
        m = SYM.match(ln)
        if m:
            sym = m.group(1)
            continue
        b = BR.match(ln)
        if not (b and text) or sym in ("_start", "deregister_tm_clones", "register_tm_clones",
                                        "__do_global_dtors_aux", "frame_dummy"):
            continue
        addr, mn, arg = int(b.group(1), 16), b.group(2), b.group(3)
        kind = "ind" if arg.startswith("*") else ("jmp" if mn == "jmp" else "cond")
        out.append([addr, sym, kind])
    return out

res = {}
with tempfile.TemporaryDirectory() as W:
    for vc in VARIANTS:
        v, cc = vc.rsplit("_", 1)
        src = open(os.path.join(ROOT, "src", SRC[v])).read().replace("10000001", "2000001")
        open(f"{W}/s.c", "w").write(src)
        subprocess.run([cc, "-O2", "-S", "-o", f"{W}/b.s", f"{W}/s.c"], check=True)
        res[vc] = {}
        for mode in ("orig", "fixed"):
            fixed = mode == "fixed"
            if fixed and vc not in FIXED_DATA:
                continue
            lab = {cpu: sorted(LAB[cpu, fixed].get(vc, set())) for cpu in ("i5-1135g7", "i9-14900k")}
            jumps = {}
            for seed in range(101):
                subprocess.run([sys.executable, "-I", os.path.join(ROOT, "analysis", "perturb.py"),
                                f"{W}/b.s", f"{W}/p.s", str(seed), "63", mode], check=True, capture_output=True)
                subprocess.run([cc, "-O2", f"{W}/p.s", "-o", f"{W}/p"], check=True)
                jumps[seed] = branches(f"{W}/p")
            res[vc][mode] = {"labels": lab, "jumps": jumps}
            n = {len([j for j in js if j[2] == "ind"]) for js in jumps.values()}
            print(f"{vc:15} {mode:5} indirect jumps per layout {sorted(n)}  collapsed {lab}", file=sys.stderr)
json.dump(res, open(os.path.join(R, "collapse_geometry.json"), "w"))
