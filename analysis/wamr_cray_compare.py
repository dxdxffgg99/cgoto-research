#!/usr/bin/env python3
"""usage: analysis/wamr_cray_compare.py <cray raw (analysis/wamr_cray_scene.sh)> <wamr raw (targets/wamr/run.sh)>

How much the empty-scene c-ray (paper 8, threats) changes the WAMR results.
1. Same session: per variant, median cycles of `cray` (empty scene) and `crayscene` (real
   scene) relative to iwasm_cgoto_gcc.
2. Effect on the WAMR summary: geometric mean over the 8 programs of the per-program ratio
   variant / cgoto_gcc (median cycles), with c-ray as measured in the WAMR run (empty scene)
   and with c-ray replaced by `crayscene` from file 1.  Each ratio is taken within one
   session, so programs from the two sessions can be combined.
"""
import math, statistics, sys
from collections import defaultdict

def load(path):
    d = defaultdict(lambda: defaultdict(list))   # bench -> variant -> [cycles]
    for line in open(path):
        f = line.split()
        if len(f) < 8 or not f[0].isdigit():
            continue
        d[f[1]][f[2]].append(float(f[4]))
    return d

cray, wamr = load(sys.argv[1]), load(sys.argv[2])
REF = "iwasm_cgoto_gcc"
ratio = lambda d, b, v: statistics.median(d[b][v]) / statistics.median(d[b][REF])
variants = sorted(v for v in cray["cray"] if v != REF)
print(f"# {sys.argv[1]} vs {sys.argv[2]}: cycles relative to {REF} (median)")
print(f"{'variant':20} {'cray empty':>11} {'cray scene':>11} {'(old run empty)':>16}   "
      f"{'WAMR geomean, old':>18} {'with scene':>11}")
for v in variants:
    progs = [b for b in wamr if v in wamr[b] and REF in wamr[b]]
    old = math.exp(sum(math.log(ratio(wamr, b, v)) for b in progs) / len(progs))
    new = math.exp(sum(math.log(ratio(cray, "crayscene", v) if b == "cray" else ratio(wamr, b, v))
                       for b in progs) / len(progs))
    print(f"{v:20} {100 * (ratio(cray, 'cray', v) - 1):+10.1f}% {100 * (ratio(cray, 'crayscene', v) - 1):+10.1f}% "
          f"{100 * (ratio(wamr, 'cray', v) - 1):+15.1f}%   {100 * (old - 1):+17.1f}% {100 * (new - 1):+10.1f}%")
print(f"\nmedian Gcycles of {REF}: cray {statistics.median(cray['cray'][REF]) / 1e9:.2f}, "
      f"crayscene {statistics.median(cray['crayscene'][REF]) / 1e9:.2f}")
