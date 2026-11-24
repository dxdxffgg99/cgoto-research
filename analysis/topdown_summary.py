#!/usr/bin/env python3
"""usage: analysis/topdown_summary.py <topdown_file> [--ref VARIANT] [--pairs A:B,C:D] [--bench]

Summarises analysis/topdown.sh output (paper 5.3/5.4, task 2).  For each variant, the
median over rounds per benchmark, then the mean over benchmarks (each benchmark weighs
the same) of:
  TMA level 1/2 (% of slots, as perf computes them), IPC, DSB share of delivered uops,
  front-end stalls per 100 cycles (icache, resteer after clears, DSB->MITE switches),
  BACLEARS / indirect branches / indirect mispredicts per 1000 instructions,
  loads and stores per instruction, and cycles relative to --ref (geomean).
--pairs prints B minus A for each metric (B relative to A for cycles).
--bench also prints the per-benchmark cycles ratio and L1 deltas for each pair.
On Ice Lake / Tiger Lake (level 2 measured in a separate multiplexed run) level 2 is
rebuilt from the level-1 fractions and raw count ratios; see per_bench.
"""
import math, statistics, sys
from collections import defaultdict

path = sys.argv[1]
arg = lambda k, d=None: sys.argv[sys.argv.index(k) + 1] if k in sys.argv else d
ref = arg("--ref")
pairs = [p.split(":") for p in arg("--pairs", "").split(",") if p]

raw = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))  # var -> bench -> event -> [values]
for line in open(path):
    f = line.split()
    if len(f) < 6:
        continue
    _, bench, var, group, ev, val = f[:6]
    try:
        v = float(val)
    except ValueError:
        continue
    key = ev if not ev == "cycles" else f"cycles.{group}"
    raw[var][bench][key].append(v)

def m(var, bench, ev):
    xs = raw[var][bench].get(ev)
    return statistics.median(xs) if xs else float("nan")

def per_bench(var, bench):
    g = lambda e: m(var, bench, e)
    cyc = g("cycles.fe")
    ins = g("instructions")
    d = {
        "Ret": g("tma_retiring"), "BadSp": g("tma_bad_speculation"),
        "FE": g("tma_frontend_bound"), "BE": g("tma_backend_bound"),
        "FElat": g("tma_fetch_latency"), "FEbw": g("tma_fetch_bandwidth"),
        "BrMis": g("tma_branch_mispredicts"), "Clears": g("tma_machine_clears"),
        "Mem": g("tma_memory_bound"), "Core": g("tma_core_bound"),
        "IPC": ins / cyc,
        "DSB%": 100 * g("idq.dsb_uops") / (g("idq.dsb_uops") + g("idq.mite_uops") + g("idq.ms_uops")),
        "uop/ins": g("uops_issued.any") / ins,
        "icache%": 100 * g("icache_data.stalls") / g("cycles.stall"),
        "resteer%": 100 * g("int_misc.clear_resteer_cycles") / g("cycles.stall"),
        "d2m%": 100 * g("dsb2mite_switches.penalty_cycles") / g("cycles.stall"),
        "BACL/ki": 1000 * g("baclears.any") / ins,
        "ind/ki": 1000 * g("br_inst_retired.indirect") / ins,
        "indmis/ki": 1000 * g("br_misp_retired.indirect") / ins,
        "ld/ins": g("mem_inst_retired.all_loads") / ins,
        "st/ins": g("mem_inst_retired.all_stores") / ins,
        "_cyc": cyc, "_ins": ins,
        "_ld": g("mem_inst_retired.all_loads"), "_st": g("mem_inst_retired.all_stores"),
    }
    if not math.isnan(g("cycle_activity.stalls_mem_any")):
        # Ice Lake / Tiger Lake: level 2 comes from a separate, multiplexed run, where the
        # PERF_METRICS fractions (topdown-*) are wrong (bad-spec 44% of slots vs 13% in the
        # level-1 run).  Rebuild level 2 with perf's own formulas, taking the level-1
        # fractions from the unmultiplexed run and only count ratios from the level-2 run.
        bm, mc = g("br_misp_retired.all_branches"), g("machine_clears.count")
        st, b1, b2 = g("exe_activity.bound_on_stores"), g("exe_activity.1_ports_util"), g("exe_activity.2_ports_util")
        memf = (g("cycle_activity.stalls_mem_any") + st) / (g("cycle_activity.stalls_total") + b1 + d["Ret"] / 100 * b2 + st)
        felat = 100 * (5 * g("idq_uops_not_delivered.cycles_0_uops_deliv.core") - g("int_misc.uop_dropping")) / g("topdown.slots")
        d.update(FElat=felat, FEbw=max(0.0, d["FE"] - felat),
                 BrMis=d["BadSp"] * bm / (bm + mc), Clears=d["BadSp"] * mc / (bm + mc),
                 Mem=d["BE"] * memf, Core=d["BE"] * (1 - memf))
    return d

COLS = ["Ret", "BadSp", "FE", "BE", "FElat", "FEbw", "BrMis", "Mem", "Core", "IPC", "DSB%",
        "uop/ins", "icache%", "resteer%", "d2m%", "BACL/ki", "ind/ki", "indmis/ki", "ld/ins", "st/ins"]
variants = sorted(raw)
benches = sorted({b for v in variants for b in raw[v]})
PB = {v: {b: per_bench(v, b) for b in benches if b in raw[v]} for v in variants}

def mean(v, c):
    xs = [PB[v][b][c] for b in PB[v] if not math.isnan(PB[v][b][c])]
    return sum(xs) / len(xs) if xs else float("nan")

def gm_ratio(a, b, key="_cyc"):
    common = [x for x in PB[a] if x in PB[b]]
    return math.exp(sum(math.log(PB[b][x][key] / PB[a][x][key]) for x in common) / len(common))

fmt = lambda x: "   n/a" if math.isnan(x) else (f"{x:6.2f}" if abs(x) < 10 else f"{x:6.1f}")
print(f"# {path}: mean over {len(benches)} benchmark(s) of per-benchmark medians")
hdr = f"{'variant':22}" + ("  cyc/ref" if ref else "") + "".join(f"{c:>10}" for c in COLS)
print(hdr)
for v in variants:
    r = f"  {100 * (gm_ratio(ref, v) - 1):+6.1f}%" if ref and ref in PB else ""
    print(f"{v:22}{r}" + "".join(f"{fmt(mean(v, c)):>10}" for c in COLS))
if len(benches) == 1:   # microbenchmark: absolute counts matter
    print("\n# absolute (billions): cycles, instructions, loads, stores")
    for v in variants:
        d = PB[v][benches[0]]
        print(f"{v:22} {d['_cyc'] / 1e9:8.2f} {d['_ins'] / 1e9:8.2f} {d['_ld'] / 1e9:8.2f} {d['_st'] / 1e9:8.2f}")
for a, b in pairs:
    if a not in PB or b not in PB:
        continue
    print(f"\n# {b} minus {a}: cycles {100 * (gm_ratio(a, b) - 1):+.1f}%, instructions {100 * (gm_ratio(a, b, '_ins') - 1):+.1f}%")
    print("  " + "".join(f"{c:>10}" for c in COLS))
    print("  " + "".join(f"{fmt(mean(b, c) - mean(a, c)):>10}" for c in COLS))
    if "--bench" in sys.argv:
        for x in benches:
            if x in PB[a] and x in PB[b]:
                A, B = PB[a][x], PB[b][x]
                print(f"    {x:11} cyc {100 * (B['_cyc'] / A['_cyc'] - 1):+6.1f}%  ins {100 * (B['_ins'] / A['_ins'] - 1):+6.1f}%  "
                      + " ".join(f"{c} {B[c] - A[c]:+5.1f}" for c in ("Ret", "BadSp", "FE", "BE", "FElat", "Mem", "Core")))
