#!/usr/bin/env python3
"""Per-benchmark summary of analysis/llcpatch_real.sh results (TailDuplicator patch, rule on vs off).

usage: llcpatch_summary.py results/llcpatch_<suite>_<tag>_raw.txt ...

Raw lines (bench/android_run.sh with INDEV): round bench variant time cycles instructions branches
branch_misses ghz temp_before temp_after loadavg indirect_spec indirect_misp.
Variants are <family>_{stock,llcoff,llcon}: stock = clang 21 as released, llcoff/llcon = the same
bitcode through llc built from the PR with the rule off (=0) / on (default).
Per benchmark: median cycles and median indirect mispredictions (raw 0x118 on Cortex-A76);
"on/off" = median(llcon) / median(llcoff) - 1.  Geomean over benchmarks at the bottom.
"""
import sys, math, statistics as st
from collections import defaultdict

for path in sys.argv[1:]:
    cyc = defaultdict(list); ind = defaultdict(list); ins = defaultdict(list)
    for line in open(path):
        f = line.split()
        if len(f) < 14 or not f[0].isdigit():
            continue
        bench, var = f[1], f[2]
        fam, mode = var.rsplit('_', 1)
        cyc[(fam, bench, mode)].append(float(f[4]))
        ins[(fam, bench, mode)].append(float(f[5]))
        ind[(fam, bench, mode)].append(float(f[13]))
    fams = sorted({k[0] for k in cyc})
    print(f"## {path}")
    for fam in fams:
        benches = sorted({k[1] for k in cyc if k[0] == fam})
        print(f"\n{fam}  (n = rounds per cell)")
        print(f"{'benchmark':22s} {'n':>3s} {'stock Gcyc':>10s} {'off Gcyc':>9s} {'on Gcyc':>9s} {'on/off':>7s} {'stock/off':>9s}"
              f" {'ind_misp off':>13s} {'on':>11s} {'stock':>11s} {'ins on/off':>10s}")
        logs, logs_s = [], []
        for b in benches:
            g = lambda m, d=cyc: st.median(d[(fam, b, m)]) if d.get((fam, b, m)) else float('nan')
            off, on, stock = g('llcoff'), g('llcon'), g('stock')
            n = min(len(cyc.get((fam, b, m), [])) for m in ('stock', 'llcoff', 'llcon'))
            r = on / off - 1; rs = stock / off - 1
            if not math.isnan(r): logs.append(math.log(on / off))
            if not math.isnan(rs): logs_s.append(math.log(stock / off))
            io, ion, ist = g('llcoff', ind), g('llcon', ind), g('stock', ind)
            ri = g('llcon', ins) / g('llcoff', ins) - 1
            print(f"{b:22s} {n:3d} {stock/1e9:10.3f} {off/1e9:9.3f} {on/1e9:9.3f} {100*r:+6.1f}% {100*rs:+8.1f}%"
                  f" {io/1e6:12.2f}M {ion/1e6:10.2f}M {ist/1e6:10.2f}M {100*ri:+9.1f}%")
        gm = lambda v: 100 * (math.exp(st.mean(v)) - 1) if v else float('nan')
        if logs:
            print(f"{'geomean':22s} {'':3s} {'':10s} {'':9s} {'':9s} {gm(logs):+6.1f}%"
                  f" {gm(logs_s):+8.1f}%   ({sum(x < 0 for x in logs)}/{len(logs)} faster with the rule on)")
    print()
