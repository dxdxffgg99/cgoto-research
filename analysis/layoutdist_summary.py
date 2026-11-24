#!/usr/bin/env python3
"""usage: analysis/layoutdist_summary.py [--orig]

Summary of the 100-layout experiment (paper 6.2a, analysis/layout_dist.sh) on both CPUs:
indirect-prediction collapses (indirect mispredicts > 10M) per variant and per dispatch
family, Fisher exact tests between families, and per-variant spread of cycles.

Data: results/analysis/layoutdist_<cpu>.txt were measured with perturb.py mode "orig",
which executes the padding in cgoto clang, musttail gcc and musttail_args gcc (see
perturb.py).  Those three variants were re-measured with mode "fixed" in
results/analysis/layoutdist_<cpu>_fixed.txt; for the other five variants the two modes
produce identical layouts, so their orig data are used as they are.  Validity check per
variant: retired instructions must be the same for every layout (padding not executed).
--orig: use only the orig files (reproduces the earlier table).
ARM: results/analysis/layoutdist_galaxy-s25edge.txt (analysis/layout_dist_android.sh, mode
fixed, clang only) and layoutdist_cortex-a76.txt (bench/pstat_all.sh, Raspberry Pi 5, gcc 15 and
clang 21) are listed per variant when present; the family and compiler tests stay x86-only
(AArch64 clang's switch has no indirect jump, so the families differ).  An ARM core without an
indirect-misprediction event has NA in that column: its collapse count is then n/a.
slow = layouts whose cycles exceed 1.3 x the variant's median, whatever the cause.
output: results/analysis/layoutdist_summary.txt (or _orig.txt)
"""
import math, os, statistics, sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R = os.path.join(ROOT, "results", "analysis")
CPUS = ["i5-1135g7", "i9-14900k"]   # x86: family and compiler tests
ARMS = ["galaxy-s25edge", "cortex-a76"]
THRESH = 10_000_000
SLOW = 1.3
ORIG = "--orig" in sys.argv
FAMILIES = [  # label, variants
    ("switch gcc (1 indirect jump)", ["switch_gcc"]),
    ("cgoto", ["cgoto_gcc", "cgoto_clang"]),
    ("switch clang (jumps replicated)", ["switch_clang"]),
    ("tail call (musttail, musttail_args)", ["musttail_gcc", "musttail_clang", "mtargs_gcc", "mtargs_clang"]),
]

def load(path):
    d = defaultdict(dict)   # variant -> seed -> (cycles, instr, ind_misp)
    if not os.path.exists(path):
        return d
    for line in open(path):
        f = line.split()
        if len(f) < 8 or line.startswith("#"):
            continue
        d[f[1]][int(f[2])] = (float(f[3]), float(f[4]), float("nan") if f[6] == "NA" else float(f[6]))
    return d

data, source = {}, {}
ALL = CPUS + [a for a in ARMS if os.path.exists(os.path.join(R, f"layoutdist_{a}.txt")) and not ORIG]
for cpu in ALL:
    base = load(os.path.join(R, f"layoutdist_{cpu}.txt"))
    fixed = {} if ORIG else load(os.path.join(R, f"layoutdist_{cpu}_fixed.txt"))
    data[cpu] = {}
    for v in base:
        use_fixed = v in fixed and len(fixed[v]) == len(base[v])
        data[cpu][v] = fixed[v] if use_fixed else base[v]
        source[cpu, v] = "fixed" if use_fixed or cpu in ARMS else "orig"

def fisher(a, n1, b, n2):
    """two-sided Fisher exact test for a/n1 vs b/n2"""
    k, n = a + b, n1 + n2
    p = lambda x: math.comb(n1, x) * math.comb(n2, k - x) / math.comb(n, k)
    po = p(a)
    return min(1.0, sum(p(x) for x in range(max(0, k - n2), min(k, n1) + 1) if p(x) <= po * (1 + 1e-9)))

out = [f"# analysis/layoutdist_summary.py{' --orig' if ORIG else ''}: 100-layout experiment, -O2, Collatz limit 2M, "
       f"collapse = indirect mispredicts > {THRESH / 1e6:.0f}M"]
out.append(f"\n{'cpu':14} {'variant':15} {'data':5} {'n':>4} {'collapse':>8} {'slow':>4} {'instr const':>11} "
           f"{'median Gcyc':>11} {'best-worst':>10} {'CV':>6}  collapsed seeds | slow seeds")
coll = {}
for cpu in ALL:
    for v in sorted(data[cpu]):
        rows = data[cpu][v]
        cyc = [r[0] for r in rows.values()]
        ins = [r[1] for r in rows.values()]
        bad = sorted(s for s, r in rows.items() if r[2] > THRESH)
        na = all(math.isnan(r[2]) for r in rows.values())   # no indirect-misprediction event
        coll[cpu, v] = (float("nan") if na else len(bad), len(rows), set(bad))
        const = (max(ins) - min(ins)) / min(ins) < 1e-4
        med = statistics.median(cyc)
        slow = sorted(s for s, r in rows.items() if r[0] > SLOW * med)
        nb = "n/a" if na else str(len(bad))
        out.append(f"{cpu:14} {v:15} {source[cpu, v]:5} {len(rows):4d} {nb:>8} {len(slow):4d} {'yes' if const else 'NO':>11} "
                   f"{med / 1e9:11.3f} {100 * (max(cyc) / min(cyc) - 1):9.1f}% "
                   f"{100 * statistics.pstdev(cyc) / statistics.mean(cyc):5.1f}%  {' '.join(map(str, bad))} | {' '.join(map(str, slow))}")

out.append(f"\n{'family':38} {'i5':>9} {'i9':>9} {'both':>11}")
fam = {}
for label, vs in FAMILIES:
    per = []
    for cpu in CPUS:
        a = sum(coll[cpu, v][0] for v in vs if (cpu, v) in coll)
        n = sum(coll[cpu, v][1] for v in vs if (cpu, v) in coll)
        per.append((a, n))
    a, n = sum(x[0] for x in per), sum(x[1] for x in per)
    fam[label] = (a, n)
    out.append(f"{label:38} {per[0][0]:3d}/{per[0][1]:<5d} {per[1][0]:3d}/{per[1][1]:<5d} {a:3d}/{n:<4d} ({100 * a / n:.1f}%)")

L = [f[0] for f in FAMILIES]
out.append("\nFisher exact test (two-sided), both CPUs pooled:")
for x, y in [(1, 3), (1, 2), (0, 3), (2, 3)]:
    (a, n1), (b, n2) = fam[L[x]], fam[L[y]]
    out.append(f"  {L[x]} {a}/{n1} vs {L[y]} {b}/{n2}: p = {fisher(a, n1, b, n2):.4f}")

out.append("\nby compiler (both CPUs pooled):")
byc = {}
for c, excl in [("gcc", ()), ("clang", ()), ("gcc", ("switch_gcc",))]:
    vs = [v for v in data[CPUS[0]] if v.endswith("_" + c) and v not in excl]
    a = sum(coll[cpu, v][0] for cpu in CPUS for v in vs)
    n = sum(coll[cpu, v][1] for cpu in CPUS for v in vs)
    key = c + (" without switch_gcc" if excl else "")
    byc[key] = (a, n)
    out.append(f"  {key:22} {a:3d}/{n:<4d} ({100 * a / n:.1f}%)  [{', '.join(sorted(vs))}]")
for k in ("gcc", "gcc without switch_gcc"):
    (a, n1), (b, n2) = byc[k], byc["clang"]
    out.append(f"  Fisher {k} vs clang: p = {fisher(a, n1, b, n2):.5f}")

out.append("\nsame layout collapsing on both CPUs (per variant: i9 collapses that also collapse on i5):")
for v in sorted(data[CPUS[1]]):
    s5, s9 = coll[CPUS[0], v][2], coll[CPUS[1], v][2]
    if s5 or s9:
        out.append(f"  {v:15} i5 {len(s5):2d}  i9 {len(s9):2d}  both {len(s5 & s9):2d}")

if any(a in ALL for a in ARMS):
    out.append("\nclang variants per CPU (collapse = indirect mispredicts > 10M; slow = cycles > 1.3 x median):")
    cl = {}
    for cpu in ALL:
        vs = [v for v in data[cpu] if v.endswith("_clang")]
        a = sum(coll[cpu, v][0] for v in vs)
        n = sum(coll[cpu, v][1] for v in vs)
        sl = sum(1 for v in vs for r in data[cpu][v].values()
                 if r[0] > SLOW * statistics.median(x[0] for x in data[cpu][v].values()))
        cl[cpu] = (a, n, sl)
        out.append(f"  {cpu:14} collapse {'n/a' if a != a else int(a):>3}/{n:<4d} slow {sl:3d}/{n:<4d}")
    for arm in [a for a in ARMS if a in ALL]:
        for cpu in CPUS:
            (a, n1, _), (b, n2, _) = cl[arm], cl[cpu]
            if a == a:   # not NaN
                out.append(f"  Fisher collapse {arm} vs {cpu}: p = {fisher(a, n1, b, n2):.5f}")

text = "\n".join(out)
print(text)
open(os.path.join(R, "layoutdist_summary_orig.txt" if ORIG else "layoutdist_summary.txt"), "w").write(text + "\n")
