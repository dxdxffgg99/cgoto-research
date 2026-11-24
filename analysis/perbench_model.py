"""usage: analysis/perbench_model.py

Why dispatch variants differ per benchmark (paper 5.3): per Lua benchmark, cycles of a
variant relative to cgoto (same compiler) against its instruction increase and the
front-end bound of cgoto (top-down runs, analysis/topdown.sh), least squares over
14 benchmarks x 6 pairs, per CPU.
output: results/analysis/perbench_model.txt
"""
import sys, math, runpy, io, contextlib, os
import numpy as np
for cpu in ["i9-14900k","i5-1135g7"]:
    sys.argv=["x", f"results/topdown_lua_{cpu}.txt"]
    with contextlib.redirect_stdout(io.StringIO()):
        g=runpy.run_path("analysis/topdown_summary.py")
    PB=g["PB"]
    print(f"===== {cpu}: per-benchmark baseline (cgoto) front-end detail")
    for v in ["lua_cgoto_gcc","lua_cgoto_clang"]:
        for b in ["Mandelbrot","NBody","Sieve","Storage","Richards"]:
            d=PB[v][b]
            print(f"  {v:16} {b:11} FE={d['FE']:5.1f} FElat={d['FElat']:5.1f} FEbw={d['FEbw']:5.1f} BE={d['BE']:5.1f} IPC={d['IPC']:4.2f} DSB%={d['DSB%']:5.1f} icache%={d['icache%']:4.1f} resteer%={d['resteer%']:4.1f} d2m%={d['d2m%']:4.1f} BACL/ki={d['BACL/ki']:5.2f} indmis/ki={d['indmis/ki']:5.2f}")
    print(f"--- {cpu}: regression over benchmarks x pairs:  dcyc% ~ a*dins% + b*FE_ref(%) + c")
    rows=[]
    pairs=[("lua_cgoto_gcc","lua_tail_gcc"),("lua_cgoto_gcc","lua_tailpn_gcc"),("lua_cgoto_clang","lua_tail_clang"),("lua_cgoto_clang","lua_tailpn_clang"),("lua_cgoto_gcc","lua_switch_gcc"),("lua_cgoto_clang","lua_switch_clang")]
    for a,b in pairs:
        for x in PB[a]:
            A,B=PB[a][x],PB[b][x]
            rows.append((100*(B['_cyc']/A['_cyc']-1), 100*(B['_ins']/A['_ins']-1), A['FE'], x, a, b))
    Y=np.array([r[0] for r in rows]); X1=np.array([r[1] for r in rows]); X2=np.array([r[2] for r in rows])
    for name,X in [("dins only",np.c_[X1,np.ones_like(X1)]),("dins + FE_ref",np.c_[X1,X2,np.ones_like(X1)])]:
        coef,res,_,_=np.linalg.lstsq(X,Y,rcond=None); pred=X@coef
        r2=1-((Y-pred)**2).sum()/((Y-Y.mean())**2).sum()
        print(f"   {name:14} coef={np.round(coef,3)}  R2={r2:.2f}  n={len(Y)}")
    # residuals with full model
    X=np.c_[X1,X2,np.ones_like(X1)]; coef=np.linalg.lstsq(X,Y,rcond=None)[0]; res=Y-X@coef
    worst=sorted(zip(res,rows),key=lambda t:-abs(t[0]))[:5]
    for r,row in worst: print(f"   largest residual {r:+5.1f}pp: {row[3]:11} {row[4]}->{row[5]} dcyc {row[0]:+5.1f}% dins {row[1]:+5.1f}% FE_ref {row[2]:4.1f}")
