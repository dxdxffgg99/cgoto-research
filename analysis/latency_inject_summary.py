#!/usr/bin/env python3
"""usage: analysis/latency_inject_summary.py <latency_inject_<tag>.txt>

Summary of analysis/latency_inject.sh: per variant, median cycles over rounds for each
(mode, k); executed multiplies n = (instructions - reference instructions); extra cycles
per executed multiply = (cycles - reference cycles) / n.  Reference: the unmodified
binary (base) for ctrl, the k = 0 rewrite (split) for chain when gcc's memory-destination
add had to be rewritten, else base.  A chain multiply costs 3 cycles of latency and one
uop: ~3 extra cycles per multiply = the pc chain is the critical path; ~0 = slack (the
k where it starts to grow gives the slack); ctrl shows the cost of the uop alone.
"""
import statistics, sys
from collections import defaultdict

path = sys.argv[1]
d = defaultdict(list)
for line in open(path):
    f = line.split()
    if line.startswith("#") or len(f) < 6:
        continue
    d[f[1], f[2], int(f[3])].append((float(f[4]), float(f[5])))
med = {k: (statistics.median(x[0] for x in v), statistics.median(x[1] for x in v), len(v)) for k, v in d.items()}
print(f"# {path}: median over rounds; extra cycles per executed multiply (3 = on the critical path)")
for vc in sorted({k[0] for k in med}):
    base = med[vc, "base", 0]
    print(f"\n{vc}: base {base[0] / 1e9:.3f} Gcycles, {base[1] / 1e9:.3f} Ginstr" +
          (f"; split {med[vc, 'split', 0][0] / base[0] * 100 - 100:+.2f}% cycles" if (vc, "split", 0) in med else ""))
    for mode in ("chain", "ctrl"):
        ref = med.get((vc, "split", 0), base) if mode == "chain" else base
        ks = sorted(k for (v, m, k) in med if v == vc and m == mode)
        row = []
        for k in ks:
            c, i, n = med[vc, mode, k]
            row.append(f"k={k}: {(c - ref[0]) / (i - ref[1]):5.2f} ({100 * (c / ref[0] - 1):+5.1f}%)")
        print(f"  {mode:5}  " + "  ".join(row))
