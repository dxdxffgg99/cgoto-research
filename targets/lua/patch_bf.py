#!/usr/bin/env python3
"""Branch-free dispatch for Lua's computed-goto interpreter (mode "cgotobf").

usage: patch_bf.py <src_dir>      (patches lvm.c and ljumptab.h in place)

Stock Lua 5.4 dispatches with
    vmbreak = if (trap) { trap = luaG_traceexec(L, pc); updatebase(ci); }
              i = *(pc++); goto *disptab[GET_OPCODE(i)];
The conditional in front of the indirect jump lets gcc/clang tail-merge the
per-handler copies back into a few shared dispatch blocks (6 jumps with gcc,
46 with clang at -O2).  Here the trap test is folded into the table index
instead, as CPython does by swapping its dispatch table:
    vmbreak = i = *(pc++); goto *disptab[GET_OPCODE(i) | ((trap != 0) << 7)];
Entries 128..255 point to L_vmtrap, which undoes the fetch, runs the hook
exactly as before and dispatches the same instruction again.  Behaviour is
unchanged: the hook runs at the same points with the same pc.
"""
import sys
from pathlib import Path


def sub(text, old, new, path):
    if text.count(old) != 1:
        sys.exit(f"patch_bf: expected exactly one match in {path}: {old!r}")
    return text.replace(old, new)


d = Path(sys.argv[1])

p = d / "ljumptab.h"
t = p.read_text()
t = sub(t, "#define vmbreak\t\tvmfetch(); vmdispatch(GET_OPCODE(i));",
        "#define vmbreak\t\t{ i = *(pc++); "
        "goto *disptab[GET_OPCODE(i) | ((trap != 0) << 7)]; }", p)
t = sub(t, "static const void *const disptab[NUM_OPCODES] = {",
        "static const void *const disptab[256] = {", p)
t = sub(t, "&&L_OP_EXTRAARG\n\n};",
        "&&L_OP_EXTRAARG,\n[128 ... 255] = &&L_vmtrap\n};", p)
p.write_text(t)

p = d / "lvm.c"
t = p.read_text()
t = sub(t, "    vmdispatch (GET_OPCODE(i)) {\n",
        "    vmdispatch (GET_OPCODE(i)) {\n"
        "      L_vmtrap: {  /* hooks or stack reallocation (patch_bf.py) */\n"
        "        pc--;  /* undo the fetch done by 'vmbreak' */\n"
        "        trap = luaG_traceexec(L, pc);\n"
        "        updatebase(ci);\n"
        "        i = *(pc++);\n"
        "        goto *disptab[GET_OPCODE(i)];\n"
        "      }\n", p)
p.write_text(t)
