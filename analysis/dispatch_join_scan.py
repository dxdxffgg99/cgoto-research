#!/usr/bin/env python3
"""usage: analysis/dispatch_join_scan.py <objdump -d output, sections "=== <name>"> [full]

Static check for the Cortex-A76 collapse shape (paper 6.2d) in AArch64 code: for every
indirect `br`, find its basic block and the paths that join into it.  "A76-risky" = both
paths enter the join by a taken branch (1 vs 1, as clang -O2 jeven); "safe" = one path
falls through (as GCC).  Validated on the microbenchmark: clang -O2 2 risky (jeven, jnei),
-O3 0, gcc 0.  A risky join only matters if the dispatch target depends on the path;
paths that take different numbers of branches (1 vs 2) did not collapse (0/202,
results/analysis/layoutdist_cortex-a76_pathlen.txt), but are not separated here.
full: also list the functions with risky joins.
"""
import re, sys, collections
txt=open(sys.argv[1]).read()
COND=re.compile(r"^(b\.\w+|cbn?z|tbn?z)$")
def block_start(ins,k,tgts):
    j=k
    while j>0:
        pmn=ins[j-1][1]
        if ins[j][0] in tgts or pmn in ("b","br","ret") or COND.match(pmn): break
        j-=1
    return j
for part in txt.split("=== ")[1:]:
    name=part.split("\n",1)[0].strip()
    funcs=re.split(r"\n([0-9a-f]+) <([^>]+)>:\n", part)
    st=collections.Counter(); eq=[]; un=[]
    for i in range(1,len(funcs)-2,3):
        fname=funcs[i+1]; body=funcs[i+2].split("\n\n")[0]
        ins=[(int(m.group(1),16),m.group(2),m.group(3)) for m in (re.match(r"\s*([0-9a-f]+):\s+(\S+)\s*(.*)",l) for l in body.split("\n")) if m]
        if not ins: continue
        tgts=collections.Counter()
        for a,mn,op in ins:
            if mn=="b" or COND.match(mn):
                t=re.findall(r"(?:0x)?([0-9a-f]+) <",op)
                if t: tgts[int(t[-1],16)]+=1
        for k,(a,mn,op) in enumerate(ins):
            if mn!="br": continue
            st["br"]+=1
            j=block_start(ins,k,tgts); start=ins[j][0]
            taken=tgts.get(start,0)
            ft = j>0 and ins[j-1][1] not in ("b","br","ret")
            if taken+ft<2: continue
            # fall-through predecessor: entered by a taken branch (its block start is a branch target)?
            ft_by_branch=False
            if ft:
                jp=block_start(ins,j-1,tgts)
                ft_by_branch = ins[jp][0] in tgts and not COND.match(ins[j-1][1])
            equal = (ft and ft_by_branch and taken>=1) or (not ft and taken>=2)
            (eq if equal else un).append(fname)
    jv=lambda L: sorted({f for f in L if re.search(r"(EQ|LT|LE|TEST|JMP|LOOP|_IF|BR_)",f)})
    if len(sys.argv) > 2: print("   risky:", " ".join(sorted(set(eq))))
    print(f"{name:28} br {st['br']:4d} | joins where both paths take a branch (A76-risky): {len(eq):3d}  e.g. {', '.join(jv(eq)[:9])}")
    print(f"{'':28}          | joins where one path falls through (safe on A76): {len(un):3d}")
