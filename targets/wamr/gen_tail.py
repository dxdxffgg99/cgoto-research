"""Turn WAMR's fast interpreter (labels-as-values mode) into a tail-call interpreter.

usage: python3 -I gen_tail.py mark <wasm_interp_fast.c> <marked.c>
       python3 -I gen_tail.py gen  <preprocessed.c> <out.c>

Step 1 (mark): replace HANDLE_OP / FETCH_OPCODE_AND_DISPATCH with marker tokens so
handler boundaries survive the C preprocessor.
Step 2 (gen): take the preprocessed translation unit (all #if resolved for the real
build configuration) and split wasm_interp_call_func_bytecode into one function per
handler / shared label. Handler bodies are copied verbatim; only control transfer and
the storage of shared locals change:
  dispatch        -> musttail call through the function pointer stored in the bytecode
  goto <label>    -> musttail call of the label's function
  fall-through    -> explicit musttail call of the next block
  hot state       -> 6 register arguments (S, frame_ip, frame_lp, memory, globals, global_data)
  other state     -> fields of a struct on the driver's stack (S->x)
  scratch locals  -> locals of each handler function
"""
import re
import sys

# ---------------------------------------------------------------- step 1: mark

def mark(src_path, out_path):
    src = open(src_path).read()
    a = "#define HANDLE_OP(opcode) HANDLE_##opcode:"
    assert src.count(a) == 2, "HANDLE_OP definitions changed"
    src = src.replace(a, "#define HANDLE_OP(opcode) __TC_OP(opcode)")
    b = ("#define FETCH_OPCODE_AND_DISPATCH()                    \\\n"
         "    do {                                               \\\n"
         "        const void *p_label_addr = *(void **)frame_ip; \\\n"
         "        frame_ip += sizeof(void *);                    \\\n"
         "        CHECK_INSTRUCTION_LIMIT();                     \\\n"
         "        goto *p_label_addr;                            \\\n"
         "    } while (0)")
    assert src.count(b) == 1, "FETCH_OPCODE_AND_DISPATCH (unaligned) changed"
    src = src.replace(b, "#define FETCH_OPCODE_AND_DISPATCH() __TC_DISPATCH()")
    open(out_path, "w").write(src)

# ---------------------------------------------------------------- helpers

TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[A-Za-z_]\w*')

def idents(text):
    """yield (start, end, name) for identifiers that are not member names"""
    for m in TOKEN.finditer(text):
        s = m.group(0)
        if s[0] in "\"'":
            continue
        before = text[:m.start()].rstrip()
        if before.endswith(".") or before.endswith("->"):
            continue
        yield m.start(), m.end(), s

def rename(text, mapping):
    out, last = [], 0
    for s, e, name in idents(text):
        if name in mapping:
            out.append(text[last:s]); out.append(mapping[name]); last = e
    out.append(text[last:])
    return "".join(out)

def first_use_is_read(text, name):
    for s, e, n in idents(text):
        if n == name:
            rest = text[e:].lstrip()
            return not (rest.startswith("=") and not rest.startswith("=="))
    return None  # not used

def match_brace(text, i):
    """index just past the brace matching text[i] == '{' (skips strings)"""
    depth = 0
    j = i
    while j < len(text):
        c = text[j]
        if c in "\"'":
            q = c; j += 1
            while text[j] != q:
                j += 2 if text[j] == "\\" else 1
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    raise ValueError("unbalanced")

def parse_decls(stmt):
    """'uint8 opcode = 0, local_type, *global_addr;' -> [(type, name, init)]"""
    stmt = stmt.strip().rstrip(";").replace("register ", "")
    m = re.match(r"((?:const\s+|unsigned\s+|struct\s+)*[A-Za-z_]\w*)\s+(.*)$", stmt, re.S)
    base, rest = m.group(1), m.group(2)
    parts, depth, cur = [], 0, ""
    for ch in rest:
        if ch in "([{": depth += 1
        if ch in ")]}": depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur); cur = ""
        else:
            cur += ch
    parts.append(cur)
    out = []
    for p in parts:
        name_part, _, init = p.partition("=")
        stars = name_part.count("*")
        name = name_part.replace("*", "").strip()
        assert re.fullmatch(r"[A-Za-z_]\w*", name), (stmt, name)
        out.append((base + " " + "*" * stars, name, init.strip() or None))
    return out

# ---------------------------------------------------------------- step 2: gen

HOT = [("uint8 *", "frame_ip"), ("uint32 *", "frame_lp"),
       ("WASMMemoryInstance *", "memory"), ("WASMGlobalInstance *", "globals"),
       ("uint8 *", "global_data")]

def gen(pre_path, out_path):
    text = open(pre_path).read()
    sig = re.search(r"static void\s+wasm_interp_call_func_bytecode\(WASMModuleInstance \*module,"
                    r"[^)]*\)\s*\{", text)
    fstart, bopen = sig.start(), sig.end() - 1
    fend = match_brace(text, bopen)
    body = text[bopen + 1:fend - 1]

    # ---- prologue: declarations up to the first dispatch
    entry = "goto *handle_table[WASM_OP_IMPDEP];"
    pi = body.index(entry)
    prologue, rest = body[:pi], body[pi + len(entry):]
    tbl = re.search(r"static const void \* handle_table\[256\] = \{(.*?)\};;", prologue, re.S)
    table_items = [x.strip() for x in tbl.group(1).split(",") if x.strip()]
    prologue = prologue[:tbl.start()] + prologue[tbl.end():]
    prologue = prologue.replace("global_handle_table = (void **)handle_table;",
                                "global_handle_table = (void **)tc_handle_table;")

    decls = {}  # name -> (type, init)
    for t, n in [("WASMModuleInstance *", "module"), ("WASMExecEnv *", "exec_env"),
                 ("WASMFunctionInstance *", "cur_func"), ("WASMInterpFrame *", "prev_frame")]:
        decls[n] = (t, None)
    for stmt in re.findall(r"^\s*((?:register\s+)?(?:uint8|uint16|uint32|uint64|int16|int32|int64|bool|"
                           r"WASM\w+)\s+\**\s*\w+[^;(]*(?:\([^;]*\))?[^;]*;)", prologue, re.M):
        for t, n, init in parse_decls(stmt):
            decls[n] = (t, init)

    # ---- split the rest into segments at top level
    seg_re = re.compile(r"__TC_OP\((\w+)\)|^\s*([a-z_]\w*):\s*$", re.M)
    segments = []      # [name, aliases, code]
    pending = []
    pos = 0
    depth_at = []
    # compute brace depth for every position cheaply
    depth, d = 0, [0] * (len(rest) + 1)
    k = 0
    while k < len(rest):
        c = rest[k]
        if c in "\"'":
            q = c; d[k] = depth; k += 1
            while rest[k] != q:
                d[k] = depth; k += 2 if rest[k] == "\\" else 1
        elif c == "{": depth += 1
        elif c == "}": depth -= 1
        d[k] = depth; k += 1
    cur = None
    for m in seg_re.finditer(rest):
        if d[m.start()] != 0:
            continue
        if cur is not None:
            cur[2] = rest[pos:m.start()]
        if m.group(1):
            name = m.group(1)
            if cur is not None and cur[2].strip() == "":   # alias of following body
                cur[1].append(name)
                pos = m.end()
                continue
            cur = [name, [name], ""]
        else:
            cur = [m.group(2), [m.group(2)], ""]
        segments.append(cur)
        pos = m.end()
    cur[2] = rest[pos:]

    labels = {s[0] for s in segments}
    alias_of = {a: s[0] for s in segments for a in s[1]}
    goto_targets = set(re.findall(r"goto (\w+);", rest))

    # ---- split handlers at inner labels that are goto targets from elsewhere
    out_segs = []
    for name, aliases, code in segments:
        inner = [m for m in re.finditer(r"^\s*([a-z_]\w*):\s*$", code, re.M)
                 if m.group(1) in goto_targets and m.group(1) not in labels]
        if not inner:
            out_segs.append([name, aliases, code]); continue
        assert len(inner) == 1, (name, [m.group(1) for m in inner])
        m = inner[0]
        lbl = m.group(1)
        depth = code[:m.start()].count("{") - code[:m.start()].count("}")
        head = code[:m.start()] + f"\n TC_GOTO({lbl});\n" + "}" * depth
        tail = "{" * depth + code[m.end():]
        out_segs.append([name, aliases, head])
        out_segs.append([lbl, [lbl], tail])
        labels.add(lbl)
    segments = out_segs
    names = [s[0] for s in segments]

    # ---- classify locals
    state = set()
    for n in decls:
        for _, _, code in segments:
            r = first_use_is_read(code, n)
            if r:
                state.add(n); break
    hot = {n for _, n in HOT}
    state -= hot
    scratch = set(decls) - state - hot - {"opcode_IMPDEP"}
    state.discard("opcode_IMPDEP")
    mapping = {n: f"S->{n}" for n in state}

    # ---- emit
    o = []
    o.append(text[:fstart])
    o.append("""
/* ===== tail-call dispatch, generated by targets/wamr/gen_tail.py ===== */
#define MUSTTAIL __attribute__((musttail))
#ifdef WAMR_TAIL_PRESERVE_NONE
#define PN __attribute__((preserve_none))
#else
#define PN
#endif
typedef struct tc_state {""")
    for n in sorted(state):
        o.append(f"    {decls[n][0]}{n};")
    o.append("} tc_state;")
    params = "tc_state *S, " + ", ".join(f"{t}{n}" for t, n in HOT)
    args = "S, " + ", ".join(n for _, n in HOT)
    o.append(f"#define TC_PARAMS {params}")
    o.append(f"#define TC_ARGS {args}")
    o.append("typedef void (PN *tc_fn)(TC_PARAMS);")
    o.append("#define TC_GOTO(f) do { MUSTTAIL return tc_##f(TC_ARGS); } while (0)")
    o.append("#define TC_DISPATCH() do { tc_fn tc_f_ = *(tc_fn *)frame_ip; "
             "frame_ip += sizeof(void *); MUSTTAIL return tc_f_(TC_ARGS); } while (0)")
    for n in names:
        o.append(f"static void PN tc_{n}(TC_PARAMS);")
    items = []
    for it in table_items:
        m = re.match(r"(\[\w+\]\s*=\s*)?&&HANDLE_(\w+)$", it)
        assert m, it
        items.append(f"{m.group(1) or ''}(void *)tc_{alias_of[m.group(2)]}")
    o.append("static void *tc_handle_table[256] = {\n    " + ",\n    ".join(items) + "\n};")

    for i, (name, aliases, code) in enumerate(segments):
        code = code.replace("__TC_DISPATCH()", "TC_DISPATCH()")
        code = re.sub(r"goto (\w+);",
                      lambda m: f"TC_GOTO({m.group(1)});" if m.group(1) in labels else m.group(0),
                      code)
        used = {n for _, _, n in idents(code)}
        loc = []
        for n in sorted(scratch & used):
            t, init = decls[n]
            loc.append(f"    {t}{n}{' = ' + init if init else ''};")
        code = rename(code, mapping)
        nxt = f"TC_GOTO({names[i + 1]});" if i + 1 < len(names) else "return;"
        o.append(f"\n/* {' '.join(aliases)} */\nstatic void PN tc_{name}(TC_PARAMS)\n{{")
        o += loc
        o.append(code)
        o.append(f"    {nxt}\n}}")

    # driver: original prologue, then hand over to the IMPDEP handler
    o.append(text[fstart:bopen + 1])
    o.append(prologue)
    o.append("    tc_state st_, *S = &st_;\n    __builtin_memset(&st_, 0, sizeof(st_));")
    for n in sorted(state):
        if n in ("module", "exec_env", "cur_func", "prev_frame") or decls[n][1] is not None:
            o.append(f"    S->{n} = {n};")
    o.append(f"    tc_{alias_of['WASM_OP_IMPDEP']}({args});")
    for n in sorted(scratch):
        o.append(f"    (void){n};")
    o.append("}")
    o.append(text[fend:])
    open(out_path, "w").write("\n".join(o))
    print(f"{len(segments)} functions, state={sorted(state)}, scratch={len(scratch)}",
          file=sys.stderr)

if __name__ == "__main__":
    {"mark": mark, "gen": gen}[sys.argv[1]](sys.argv[2], sys.argv[3])
