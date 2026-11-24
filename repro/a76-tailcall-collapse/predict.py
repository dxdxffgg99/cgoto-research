#!/usr/bin/env python3
"""usage: predict.py <binary>   (AArch64; needs objdump or llvm-objdump)

Prints the jeven dispatch shape and whether the collapse rule predicts a collapse.
Rule (Cortex-A76, found on 202 layouts and confirmed on 200 new ones): with
footprint(pc, target) = ((pc >> 1) ^ target) & 0xffc, the merged indirect branch of jeven
mispredicts ~half the time iff footprint(tbnz) == footprint(b), i.e. the two paths into it
leave the same path history.  If jeven has one `br` per path (tail-duplicated), its
targets are fixed and no history is needed.
"""
import re, shutil, subprocess, sys
od = shutil.which("llvm-objdump") or shutil.which("objdump")
dis = subprocess.run([od, "-d", "--no-show-raw-insn", sys.argv[1]], capture_output=True, text=True).stdout
body = re.split(r"<jeven>:\n", dis)[1].split("\n\n")[0]
br, n_br = {}, 0
for ln in body.split("\n"):
    m = re.match(r"\s*([0-9a-f]+):\s+(tbnz|tbz|b|br)\s+(.*)", ln)
    if not m:
        continue
    op = "tb" if m.group(2) in ("tbnz", "tbz") else m.group(2)
    if op == "br":
        n_br += 1
    elif op not in br:
        br[op] = (int(m.group(1), 16), int(re.findall(r"(?:0x)?([0-9a-f]+) <", m.group(3))[-1], 16))
if n_br > 1 or "b" not in br:
    print(f"split dispatch ({n_br} br): no collapse possible")
else:
    fp = lambda a: ((a[0] >> 1) ^ a[1]) & 0xffc
    (t, tt), (b, bt) = br["tb"], br["b"]
    print(f"merged dispatch: tbnz {t:#x}->{tt:#x} b {b:#x}->{bt:#x} footprints {fp(br['tb']):#x} {fp(br['b']):#x}: "
          + ("COLLAPSE predicted" if fp(br["tb"]) == fp(br["b"]) else "no collapse predicted"))
