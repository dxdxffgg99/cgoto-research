#!/usr/bin/env python3
"""usage: analysis/opt_levels.py [-B 10000]

-O3 versus -O2 for the real interpreters (paper 5.4): for each dispatch variant, the
geometric mean over benchmarks of median(-O3 cycles) / median(-O2 cycles), with a 95%
bootstrap interval over benchmarks, plus the instruction and branch-miss ratios and the
benchmarks that move most.  Reads raw run files:
  round bench variant time cycles instructions branches branch_misses ...
The two levels come from separate sessions (same machine, same settings); same-binary
reruns agree within 0.1-0.6% in geometric mean (paper 5.3), so smaller effects are noise.
output: results/analysis/opt_levels.txt
"""
import math, os, random, re, statistics, sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
R = os.path.join(ROOT, "results")
B = int(sys.argv[sys.argv.index("-B") + 1]) if "-B" in sys.argv else 10000
PAIRS = [  # label, -O2 file, -O3 file
    ("Lua i9-14900K", "lua_i9-14900k_seedfix_raw.txt", "lua-O3_i9-14900k_raw.txt"),
    ("Lua i5-1135G7", "lua_i5-1135g7_raw.txt", "lua-O3_i5-1135g7_raw.txt"),
    ("WAMR i9-14900K", "wamr-O2_i9-14900k_raw.txt", "wamr_i9-14900k_raw.txt"),
    ("WAMR i5-1135G7", "wamr-O2_i5-1135g7_raw.txt", "wamr_i5-1135g7_raw.txt"),
]

def load(path):
    d = defaultdict(lambda: defaultdict(list))   # variant -> bench -> [(cycles, instr, misses)]
    for line in open(os.path.join(R, path)):
        f = line.split()
        if len(f) < 8 or not f[0].isdigit():
            continue
        v = re.sub(r"^(lua|iwasm)_", "", f[2])
        d[v][f[1]].append((float(f[4]), float(f[5]), float(f[7])))
    return d

def med(xs, i):
    return statistics.median(x[i] for x in xs)

def gm(xs):
    return math.exp(sum(math.log(x) for x in xs) / len(xs))

rng = random.Random(1)
out = [f"# analysis/opt_levels.py: -O3 / -O2 per variant (cycles; geomean over benchmarks, 95% bootstrap over benchmarks, B={B})"]
for label, f2, f3 in PAIRS:
    a, b = load(f2), load(f3)
    out.append(f"\n=== {label}  ({f2} -> {f3})")
    out.append(f"{'variant':14} {'cycles':>8} {'95% CI':>17} {'instr':>7} {'misses':>7}  largest moves (cycles)")
    for v in sorted(set(a) & set(b)):
        benches = sorted(set(a[v]) & set(b[v]))
        rc = {k: med(b[v][k], 0) / med(a[v][k], 0) for k in benches}
        ri = {k: med(b[v][k], 1) / med(a[v][k], 1) for k in benches}
        rm = {k: (med(b[v][k], 2) + 1) / (med(a[v][k], 2) + 1) for k in benches}
        g = gm(rc.values())
        boot = sorted(gm([rc[rng.choice(benches)] for _ in benches]) for _ in range(B))
        lo, hi = boot[int(0.025 * B)], boot[int(0.975 * B) - 1]
        sig = "**" if lo > 1 or hi < 1 else "  "
        moves = sorted(benches, key=lambda k: -abs(math.log(rc[k])))[:3]
        mv = ", ".join(f"{k} {100 * (rc[k] - 1):+.1f}%" for k in moves)
        out.append(f"{v:14} {100 * (g - 1):+7.1f}% [{100 * (lo - 1):+6.1f},{100 * (hi - 1):+6.1f}]{sig} "
                   f"{100 * (gm(ri.values()) - 1):+6.1f}% {100 * (gm(rm.values()) - 1):+6.1f}%  {mv}")
text = "\n".join(out)
print(text)
os.makedirs(os.path.join(R, "analysis"), exist_ok=True)
open(os.path.join(R, "analysis", "opt_levels.txt"), "w").write(text + "\n")
