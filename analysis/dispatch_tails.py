#!/usr/bin/env python3
"""usage: dispatch_tails.py <binary-or-object> <function> [k=3]

Counts the indirect jumps in <function> and how many distinct dispatch tails they
have: the last k instructions before each indirect jump (jmp *... on x86-64, br on
AArch64; on AArch32 bx/ldr pc/mov pc/add pc/tbb/tbh, not returns), with branch targets
dropped.  env OBJDUMP selects the objdump (arm-none-eabi-objdump, llvm-objdump).
Identical tails are what the compilers' tail merging (gcc cross-jumping, LLVM BranchFolder) can fold back together.
"""
import os, re, subprocess, sys
from collections import Counter

path, func = sys.argv[1], sys.argv[2]
k = int(sys.argv[3]) if len(sys.argv) > 3 else 3
od = os.environ.get("OBJDUMP", "objdump")
sel = f"--disassemble-symbols={func}" if "llvm" in od else f"--disassemble={func}"
dis = subprocess.run([od, "-d", "--no-show-raw-insn", sel, path],
                     capture_output=True, text=True, check=True).stdout
ins = []
for line in dis.splitlines():
    m = re.match(r"\s+[0-9a-f]+:\s+(.*)", line)
    if m:
        s = re.sub(r"\s+<.*>$", "", m.group(1)).strip()
        s = re.sub(r"\s*#.*$", "", s)                      # relocation/target comments
        s = re.sub(r"-?0x[0-9a-f]+\(%rip\)", "SYM(%rip)", s)  # same symbol, site-relative offset
        s = re.sub(r"\s+", " ", s)
        if s.startswith(("nop", "xchg %ax,%ax", "data16", "cs nop")):
            continue
        ins.append(s)
tails = Counter()
for i, s in enumerate(ins):
    if re.match(r"(jmp\s+\*|br\s+x|bx(\.n)?\s+(r\d+|ip)\b|(ldr|mov|add)(\.w)?\s+pc,|tb[bh](\.w)?\s)", s):
        tails[tuple(ins[max(0, i - k):i + 1])] += 1
n = sum(tails.values())
top = tails.most_common(1)[0][1] if tails else 0
print(f"jumps={n} distinct_tails(k={k})={len(tails)} largest_group={top}")
if "-v" in sys.argv:
    for t, c in tails.most_common(5):
        print(f"  {c:4}  " + " ; ".join(t))
