#!/usr/bin/env python3
"""Bootstrap confidence intervals for "variant vs reference" geometric means.

usage: bootstrap.py [--ref VARIANT] [--metric cycles|time] [--only V1,V2,..]
                    [--skip-bench B1,B2] [-B 10000] [--seed 1] FILE...

Input formats (detected per file):
  *.json   pyperf/pyperformance result; variant = file stem, benchmark = name,
           sample = mean of one run's values (time only)
  *.csv    bench/to_csv.sh runs file (one program, "collatz")
  *.txt    raw runner output:
             round benchmark variant time cycles ...   (targets/*/run.sh)
             round variant time cycles ...             (bench/android_run.sh, micro)

Per benchmark the estimate is the median of the samples (the mean for pyperf,
as pyperf reports).  The point estimate is the geometric mean over benchmarks of
est(variant) / est(ref), printed as a percent change (negative = faster).

Two 95% percentile intervals:
  noise  resample the samples of every benchmark (benchmarks fixed):
         is the difference larger than run-to-run noise?
  bench  additionally resample the benchmarks: would another benchmark set of
         the same kind likely give the same sign?
"wins" = benchmarks where the variant's estimate is below the reference's.
"""
import argparse, json, re, sys
from collections import defaultdict
from pathlib import Path
import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("files", nargs="+")
ap.add_argument("--ref", default="cgoto_gcc")
ap.add_argument("--metric", default="cycles", choices=["cycles", "time"])
ap.add_argument("--only", default="")
ap.add_argument("--skip-bench", default="")
ap.add_argument("-B", type=int, default=10000)
ap.add_argument("--seed", type=int, default=1)
a = ap.parse_args()

num = re.compile(r"^-?[0-9.]+(e[-+]?[0-9]+)?$")
data = defaultdict(lambda: defaultdict(list))   # variant -> bench -> samples
use_mean = False
for f in a.files:
    p = Path(f)
    if p.suffix == ".json":
        if a.metric != "time":
            sys.exit("pyperf files only have time")
        use_mean = True
        for b in json.load(open(p))["benchmarks"]:
            name = b["metadata"]["name"]
            for r in b["runs"]:
                if r.get("values"):
                    data[p.stem][name].append(float(np.mean(r["values"])))
    elif p.suffix == ".csv":
        lines = p.read_text().splitlines()
        h = lines[0].split(",")
        iv, im = h.index("variant"), h.index("cycles" if a.metric == "cycles" else "time_s")
        for line in lines[1:]:
            x = line.split(",")
            data[x[iv]]["collatz"].append(float(x[im]))
    else:
        for line in p.read_text().splitlines():
            x = line.split()
            if not x or x[0].startswith("#"):
                continue
            if not num.match(x[1]) and not num.match(x[2]):      # round bench variant time cycles
                bench, var, t, c = x[1], x[2], x[3], x[4]
            else:                                               # round variant time cycles
                bench, var, t, c = "collatz", x[1], x[2], x[3]
            var = re.sub(r"^(lua|iwasm)_", "", var)          # lua_cgoto_gcc -> cgoto_gcc
            data[var][bench].append(float(c if a.metric == "cycles" else t))

ref = a.ref
if ref not in data:
    sys.exit(f"reference {ref} not found; variants: {sorted(data)}")
skip = set(filter(None, a.skip_bench.split(",")))
only = [v for v in a.only.split(",") if v] or sorted(v for v in data if v != ref)
est = (lambda s, axis=None: np.mean(s, axis=axis)) if use_mean else (lambda s, axis=None: np.median(s, axis=axis))
rng = np.random.default_rng(a.seed)

def boot(samples):
    s = np.asarray(samples)
    return est(s[rng.integers(0, len(s), size=(a.B, len(s)))], axis=1)

print(f"# ref={ref} metric={a.metric} estimator={'mean' if use_mean else 'median'} B={a.B} files={' '.join(Path(f).name for f in a.files)}")
print(f"# {'variant':22} {'n':>3} {'geomean':>8}   {'noise 95% CI':>18}   {'bench 95% CI':>18}  wins")
for v in only:
    if v not in data:
        print(f"  {v:22} (missing)")
        continue
    benches = sorted(b for b in data[v] if b in data[ref] and b not in skip)
    if not benches:
        continue
    point = np.array([np.log(est(data[v][b]) / est(data[ref][b])) for b in benches])
    lr = np.stack([np.log(boot(data[v][b]) / boot(data[ref][b])) for b in benches], axis=1)  # (B, nb)
    noise = lr.mean(axis=1)
    pick = rng.integers(0, len(benches), size=(a.B, len(benches)))
    bench = np.take_along_axis(lr, pick, axis=1).mean(axis=1)
    pct = lambda z: 100 * (np.exp(z) - 1)
    g = pct(point.mean())
    nl, nh = pct(np.percentile(noise, [2.5, 97.5]))
    bl, bh = pct(np.percentile(bench, [2.5, 97.5]))
    wins = int((point < 0).sum())
    mark = "*" if (nh < 0 or nl > 0) else " "
    mark += "*" if (bh < 0 or bl > 0) else " "
    print(f"  {v:22} {len(benches):>3} {g:+7.1f}%   [{nl:+6.1f}%, {nh:+6.1f}%]   [{bl:+6.1f}%, {bh:+6.1f}%]  {wins}/{len(benches)} {mark}")
print("# marks: first * = noise CI excludes 0, second * = bench CI excludes 0")
