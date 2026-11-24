#!/usr/bin/env python3
"""usage: analysis/collapse_geometry_a64.py

ARM counterpart of collapse_geometry.py (paper 6.2c): rebuilds the Galaxy layouts locally from
the saved base assembly (results/analysis/layoutdist_galaxy-s25edge_asm/) with perturb.py
(mode fixed, max pad 63) and clang --target=aarch64-linux-android -c, and records every
branch offset in .text per seed with the cycles of that layout relative to the median.
On the device, linked addresses = these offsets + 0x4840 (checked on seeds 0 and 33).
output: results/analysis/collapse_geometry_galaxy.json
"""
import json, re, statistics, subprocess, sys, tempfile
W=tempfile.mkdtemp()
base="results/analysis/layoutdist_galaxy-s25edge_asm/O2_%s.s"
rows=[l.split() for l in open("results/analysis/layoutdist_galaxy-s25edge.txt") if not l.startswith("#")]
out={}
for v in ["musttail_clang","mtargs_clang","cgoto_clang"]:
    cyc={int(r[2]):float(r[3]) for r in rows if r[1]==v}; med=statistics.median(cyc.values())
    out[v]={}
    for s in range(101):
        subprocess.run([sys.executable,"-I","analysis/perturb.py",base%v,f"{W}/p.s",str(s),"63","fixed"],check=True,capture_output=True)
        subprocess.run(["clang","--target=aarch64-linux-android","-c","-o",f"{W}/p.o",f"{W}/p.s"],check=True)
        dis=subprocess.run(["llvm-objdump","-d","--no-show-raw-insn",f"{W}/p.o"],capture_output=True,text=True).stdout
        sym=None; br=[]
        for ln in dis.split("\n"):
            m=re.match(r"^([0-9a-f]+) <([^>]+)>:",ln)
            if m: sym=m.group(2); continue
            m=re.match(r"^\s*([0-9a-f]+):\s+(br|b|b\.\w+|tbn?z|cbn?z|ret|bl|blr)\s",ln)
            if m: br.append((int(m.group(1),16),sym,m.group(2)))
        out[v][s]={"ratio":cyc[s]/med,"br":br}
json.dump(out,open("results/analysis/collapse_geometry_galaxy.json","w"))
