"""Randomly perturb code placement in a compiler-generated assembly file.

usage: python3 -I perturb.py <in.s> <out.s> <seed> [max_pad=63] [mode=fixed]

Before every code label that cannot be reached by falling through (the previous
instruction is an unconditional jmp / ret / ud2, or it is a function entry), insert
`.nops R` with R uniform in [0, max_pad]. The padding is never executed, so the
program executes exactly the same instructions; only their addresses change.
Applies the same rule to switch, computed-goto and tail-call code, for gcc and clang
output. seed 0 = no padding (original layout).
AArch64 (detected from the assembly): the dead-end instructions are b / br / ret / brk /
udf, and the padding is R//4 `nop`s (instructions stay 4-byte aligned), so the maximum
shift in bytes is the same.

mode fixed (default): when several labels share one address (no instruction, data or
alignment between them), only the first of the run is padded.  Padding a later label
of the run puts the padding between labels, so every jump to an earlier label runs
through it: clang's address-taken `.LtmpN:` directly followed by `.LBB0_k:` (computed
goto targets, musttail_args), and gcc's function label `f:` directly followed by
`.LFBn:` (musttail functions).  mode orig: the earlier behaviour that pads every label
of a run; it reproduces the layouts of the layout experiments measured before
2026-11-23 (results/analysis/layout_*.txt, layoutdist_i5-1135g7.txt,
layoutdist_i9-14900k.txt).  Under orig, cgoto clang, musttail gcc and musttail_args gcc
execute the padding (retired instructions vary by layout, up to +80%); for the other
variants the two modes give the same output.
"""
import random
import re
import sys

src, dst, seed = sys.argv[1], sys.argv[2], int(sys.argv[3])
max_pad = int(sys.argv[4]) if len(sys.argv) > 4 else 63
mode = sys.argv[5] if len(sys.argv) > 5 else "fixed"
assert mode in ("fixed", "orig"), mode
rng = random.Random(seed)

text = open(src).read()
lines = text.split("\n")
aarch64 = re.search(r"^\s+(stp|ldp|adrp)\s", text, re.M) is not None
DEAD = re.compile(r"(b|br|ret|brk|udf)$" if aarch64 else r"(jmp|ret|ud2)[wlq]?$")
# directives that emit bytes, align, or switch section: they end a run of same-address
# labels (unknown directives do not, which can only remove a padding point)
BREAK = re.compile(r"\.(p2align\w*|align|balign\w*|prefalign|nops|rept|byte|short|word|hword|"
                   r"[248]byte|long|int|quad|xword|dword|octa|string|asciz|ascii|zero|skip|space|"
                   r"fill|inst|section|text|data|bss)\b")
out = []
section_text = True
prev_insn = None        # mnemonic of the last real instruction in .text
pending_func = set()    # names declared @function, waiting for their label
run_open = False        # a label was seen and nothing has been emitted since
n_pad = 0

label_re = re.compile(r"^([.\w$]+):")
for ln in lines:
    s = ln.strip()
    if s.startswith(".section") or s in (".text", ".data", ".bss") or s.startswith(".text."):
        section_text = s == ".text" or s.startswith(".text") or ".text" in s.split(",")[0]
    m = re.match(r"\.type\s+([.\w$]+),\s*[@%]function", s)
    if m:
        pending_func.add(m.group(1))
    lm = label_re.match(s)
    if lm and section_text and seed != 0:
        name = lm.group(1)
        is_func = name in pending_func
        dead = prev_insn is not None and DEAD.match(prev_insn)
        if (is_func or dead) and not (mode == "fixed" and run_open):
            r = rng.randint(0, max_pad)
            if aarch64:
                r //= 4
                if r:
                    out.append(f"\t.rept {r}\n\tnop\n\t.endr")
            elif r:
                out.append(f"\t.nops {r}")
            n_pad += bool(r)
        pending_func.discard(name)
    out.append(ln)
    # track last instruction (skip labels, directives, comments, blank lines)
    body = label_re.sub("", s).strip()
    if lm:
        run_open = True
    if body and not body.startswith(("#", "/", ";", "@")):
        if not body.startswith(".") or BREAK.match(body):
            run_open = False
    if section_text and body and not body.startswith((".", "#", "/", ";", "@")):
        prev_insn = body.split()[0]

open(dst, "w").write("\n".join(out))
print(f"padded {n_pad} labels", file=sys.stderr)
