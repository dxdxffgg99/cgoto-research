#!/usr/bin/env python3
"""usage: analysis/a76_collapse_rule.py <first_seed> <last_seed> [labels_file]

Cortex-A76 collapse rule (paper 6.2d).  In clang's AArch64 tail-call code the jeven
handler merges its two outcomes into one `br` reached by two paths with one taken branch
each: odd = `tbnz` -> T_target, even = `b` -> B_target.  Rule found on seeds 0-100: the
indirect prediction collapses iff the two taken branches leave the same path-history
footprint, footprint(pc, target) = ((pc >> 1) ^ target) on bits 2..11.
Rebuilds the layouts of musttail_clang and mtargs_clang (perturb.py fixed, max pad 63) from
results/analysis/layoutdist_cortex-a76_asm/, locates jeven's tbnz/b with llvm-objdump of the
assembled object (clang --target=aarch64-linux-gnu -c), shifts them to the linked addresses
(seed-0 tbnz in the Pi binaries: musttail 0x984, mtargs 0x930) and prints, per seed, the
prediction; with a labels file (layoutdist format) it also prints the observation.
"""
import re, subprocess, sys, tempfile
lo, hi = int(sys.argv[1]), int(sys.argv[2])
obs = {}
if len(sys.argv) > 3:
    for l in open(sys.argv[3]):
        f = l.split()
        if l.startswith("#") or len(f) < 8: continue
        obs[f[1], int(f[2])] = float(f[6]) > 10e6
REAL = {"musttail_clang": 0x984, "mtargs_clang": 0x930}
MASK = ((1 << 12) - 1) & ~3
W = tempfile.mkdtemp()

def jeven(v, seed):
    subprocess.run([sys.executable, "-I", "analysis/perturb.py", f"results/analysis/layoutdist_cortex-a76_asm/O2_{v}.s",
                    f"{W}/p.s", str(seed), "63", "fixed"], check=True, capture_output=True)
    subprocess.run(["clang", "--target=aarch64-linux-gnu", "-c", "-o", f"{W}/p.o", f"{W}/p.s"], check=True)
    dis = subprocess.run(["llvm-objdump", "-d", "--no-show-raw-insn", f"{W}/p.o"], capture_output=True, text=True).stdout
    br = {}
    for ln in dis.split("<jeven>:")[1].split("\n\n")[0].split("\n"):
        m = re.match(r"\s*([0-9a-f]+):\s+(tbnz|b)\s+(.*)", ln)
        if m and m.group(2) not in br:
            br[m.group(2)] = (int(m.group(1), 16), int(re.findall(r"(?<![#+])0x([0-9a-f]+) <", m.group(3))[-1], 16))
    return br

print(f"# variant seed predicted observed   rule: ((pc>>1)^target) & {MASK:#x} equal for jeven's tbnz and b")
for v in REAL:
    base = REAL[v] - jeven(v, 0)["tbnz"][0]
    for s in range(lo, hi + 1):
        br = jeven(v, s)
        (t, tt), (b, bt) = br["tbnz"], br["b"]
        pred = ((((t + base) >> 1) ^ (tt + base)) & MASK) == ((((b + base) >> 1) ^ (bt + base)) & MASK)
        print(v, s, int(pred), int(obs[v, s]) if (v, s) in obs else "NA")
