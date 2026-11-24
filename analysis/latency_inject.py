"""Latency injection into the interpreter's pc chain (paper 5.4, -O0 mechanism).

usage: python3 -I latency_inject.py <in.s> <out.s> <mode> <k> [site=pc]
  in.s: x86-64 Intel-syntax assembly (-masm=intel) of src/*.c.
  site pc:  at every `pc += 3` update (the operand offsets of the bytecode make 3 unique to it).
  site val: before every store of a VM register value to ram[] (LOADI, MOV, ADDI, MULI,
            SHRI: `mov qword ptr [rA + rB(*8)], rV`, not rbp-relative), on rV: the chain
            ram[r] -> load -> op -> store -> ram[r] of the interpreted program's registers.
    mode chain: k x `imul R, R, 1` on the updated pc value: +3 cycles of latency each on
                the pc chain, one multiply-port uop each.
    mode ctrl:  k x `imul r10, r9, 1`: the same uops, off every chain (r9 is never written,
                r10 never read; r9/r10 are unused in the -O0 code of cgoto.c and musttail.c).
    mode split: k = 0 only; rewrites gcc's memory-destination add into load/add/store,
                the form the chain mode uses for it (checks that the rewrite alone is free).
  Update forms:  clang / gcc musttail:  add rX, 3          -> inject after it (on rX)
                 gcc cgoto/switch:      add QWORD PTR -N[rbp], 3
                                        -> mov r11, [..]; add r11, 3; <inject on r11>; mov [..], r11
If the pc chain is the critical path, cycles grow by ~3 per executed injection from k = 1;
if it has slack, cycles stay flat (chain) as for ctrl, until the slack is used up.
"""
import re
import sys

src, dst, mode, k = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
site = sys.argv[5] if len(sys.argv) > 5 else "pc"
assert mode in ("chain", "ctrl", "split") and site in ("pc", "val"), (mode, site)
STORE = re.compile(r"^(\s+)mov\s+(?:qword ptr|QWORD PTR) \[(?!rbp)[^\]]+\], (r[a-z0-9]+)$")
REG = re.compile(r"^(\s+)add\s+(r[a-z0-9]+), 3$")
MEM = re.compile(r"^(\s+)add\s+(QWORD PTR -\d+\[rbp\]), 3$")
out, n = [], 0
for ln in open(src).read().split("\n"):
    if re.search(r"\br(9|10|11)\b", ln):
        sys.exit(f"{src}: r9/r10/r11 already used: {ln.strip()}")
    if site == "val":
        st = STORE.match(ln)
        if st:
            ind, r = st.groups()
            n += 1
            for _ in range(k):
                out.append(f"{ind}imul\t{r}, {r}, 1" if mode == "chain" else f"{ind}imul\tr10, r9, 1")
        out.append(ln)
        continue
    m, mm = REG.match(ln), MEM.match(ln)
    if m:
        ind, r = m.groups()
        out.append(ln)
    elif mm and mode != "ctrl":
        ind, mem = mm.groups()
        r = "r11"
        out += [f"{ind}mov\tr11, {mem}", f"{ind}add\tr11, 3"]
    elif mm:
        ind = mm.group(1)
        out.append(ln)
    else:
        out.append(ln)
        continue
    n += 1
    for _ in range(k):
        out.append(f"{ind}imul\t{r}, {r}, 1" if mode == "chain" else f"{ind}imul\tr10, r9, 1")
    if mm and mode != "ctrl":
        out.append(f"{ind}mov\t{mem}, r11")
open(dst, "w").write("\n".join(out))
print(f"{n} sites", file=sys.stderr)
