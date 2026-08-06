#!/usr/bin/env python3
"""Estimate Lua 5.1 peak *active* locals (nactvar) per function/chunk.

Mirrors Lua 5.1 parser behavior: locals leave the active set when their
enclosing block ends (do/if/for/while/repeat/function). The 200 limit
checks simultaneous actives, not lifetime totals.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

IDENT = r"[A-Za-z_][A-Za-z0-9_]*"


def strip_noise(s: str) -> str:
    out: list[str] = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == "-" and i + 1 < n and s[i + 1] == "-":
            if i + 3 < n and s[i + 2] == "[" and s[i + 3] == "[":
                j = s.find("]]", i + 4)
                i = n if j < 0 else j + 2
            else:
                while i < n and s[i] != "\n":
                    i += 1
            continue
        if c in "\"'":
            q = c
            i += 1
            while i < n:
                if s[i] == "\\":
                    i += 2
                    continue
                if s[i] == q:
                    i += 1
                    break
                i += 1
            continue
        if c == "[" and i + 1 < n and s[i + 1] == "[":
            j = s.find("]]", i + 2)
            i = n if j < 0 else j + 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def parse_names(part: str) -> list[str]:
    part = part.split("=")[0]
    names: list[str] = []
    for tok in part.split(","):
        tok = tok.strip()
        m = re.match(rf"^({IDENT})$", tok)
        if m and m.group(1) != "_":
            names.append(m.group(1))
    return names


class Block:
    __slots__ = ("kind", "nact_at_entry", "pending_else", "is_loop")

    def __init__(self, kind: str, nact: int, is_loop: bool = False):
        self.kind = kind  # function|do|if|for|while|repeat
        self.nact_at_entry = nact
        self.pending_else = False
        self.is_loop = is_loop


class Func:
    __slots__ = (
        "name",
        "start",
        "end",
        "peak",
        "peak_line",
        "peak_names",
        "total_declared",
        "blocks",
        "actives",  # list of names currently active
        "declared",
    )

    def __init__(self, name: str, start: int):
        self.name = name
        self.start = start
        self.end = None
        self.peak = 0
        self.peak_line = start
        self.peak_names: list[str] = []
        self.total_declared = 0
        self.blocks: list[Block] = [Block("function", 0)]
        self.actives: list[str] = []
        self.declared: set[str] = set()


def main() -> int:
    path = Path(sys.argv[1])
    src = strip_noise(path.read_text(encoding="utf-8"))
    lines = src.splitlines()

    funcs: list[Func] = []
    chunk = Func("<chunk>", 1)
    funcs.append(chunk)
    stack = [chunk]

    local_func_re = re.compile(rf"^\s*local\s+function\s+({IDENT})\s*\(([^)]*)\)")
    func_re = re.compile(rf"^\s*function\s+({IDENT}(?:\.{IDENT})*)\s*\(([^)]*)\)")
    assign_func_re = re.compile(rf"^\s*(?:local\s+)?({IDENT})\s*=\s*function\s*\(([^)]*)\)")
    local_decl_re = re.compile(r"^\s*local\s+(?!function\b)(.+)$")
    for_num_re = re.compile(rf"^\s*for\s+({IDENT})\s*=")
    for_in_re = re.compile(rf"^\s*for\s+(.+?)\s+in\b")

    # Token patterns for control flow
    # We'll scan tokens left-to-right per line.

    def note_peak(f: Func, ln: int) -> None:
        n = len(f.actives)
        if n > f.peak:
            f.peak = n
            f.peak_line = ln
            f.peak_names = list(f.actives)

    def add_locals(f: Func, names: list[str], ln: int) -> None:
        for name in names:
            f.actives.append(name)
            f.declared.add(name)
            f.total_declared += 1
        note_peak(f, ln)

    def open_func(name: str, params: str, ln: int, bind_local: bool) -> None:
        parent = stack[-1]
        if bind_local:
            short = name.split(".")[-1]
            add_locals(parent, [short], ln)
        f = Func(name, ln)
        funcs.append(f)
        stack.append(f)
        plist = parse_names(params.replace("...", ""))
        if plist:
            add_locals(f, plist, ln)

    def close_to_nact(f: Func, nact: int) -> None:
        # remove locals introduced in this block
        while len(f.actives) > nact:
            f.actives.pop()

    def pop_block(f: Func, ln: int) -> bool:
        """Pop one block. Return True if function itself closed."""
        if len(f.blocks) <= 1:
            # closing the function
            f.end = ln
            stack.pop()
            if not stack:
                stack.append(chunk)
            return True
        blk = f.blocks.pop()
        close_to_nact(f, blk.nact_at_entry)
        return False

    i = 0
    while i < len(lines):
        line = lines[i]
        ln = i + 1
        f = stack[-1]

        m = local_func_re.match(line)
        if m:
            open_func(m.group(1), m.group(2), ln, True)
            i += 1
            continue
        m = func_re.match(line)
        if m:
            open_func(m.group(1), m.group(2), ln, False)
            i += 1
            continue
        m = assign_func_re.match(line)
        if m:
            is_local = line.lstrip().startswith("local ")
            open_func(m.group(1), m.group(2), ln, is_local)
            i += 1
            continue

        # mid-line anonymous function
        if re.search(r"\bfunction\s*\(", line) and not re.search(rf"\bfunction\s+{IDENT}", line):
            if not assign_func_re.match(line):
                pm = re.search(r"function\s*\(([^)]*)\)", line)
                params = pm.group(1) if pm else ""
                open_func(f"<anon@{ln}>", params, ln, False)

        f = stack[-1]

        # Local decls / for vars — happen at statement start, before block opens for for
        lm = local_decl_re.match(line)
        if lm:
            add_locals(f, parse_names(lm.group(1)), ln)

        # for-loop: vars enter before the for-block opens
        # We handle for via tokens below, but need to capture vars.
        # Actually process tokens carefully.

        # Tokenize
        tokens = re.findall(rf"{IDENT}|==|~=|<=|>=|\.\.\.|[\(\)\[\]]|[^\s\w]", line)
        # Simpler word tokens
        words = re.findall(rf"{IDENT}", line)

        # Use a more careful scan with word list and positions
        # Process structural keywords in order of appearance
        # For accuracy: walk regex finds of keywords

        # Special: for statement on this line
        fm = for_num_re.match(line)
        fim = for_in_re.match(line)
        if fm or fim:
            if fm:
                add_locals(f, [fm.group(1)], ln)
            else:
                add_locals(f, parse_names(fim.group(1)), ln)
            # for-block opens at do (may be same line)
            # mark that next 'do' opens for-block; handled below

        # Scan keywords
        # Find all keyword occurrences with simple split preserving order
        parts = re.findall(rf"{IDENT}", line)
        # Also need to know about 'else'/'elseif' which adjust actives

        # pending flags on function via blocks
        idx = 0
        # Re-scan using finditer on keywords
        for km in re.finditer(
            r"\b(function|if|then|else|elseif|for|while|do|repeat|until|end)\b", line
        ):
            kw = km.group(1)
            # Skip the 'function' that opened this function on its header line
            if kw == "function" and (local_func_re.match(line) or func_re.match(line) or assign_func_re.match(line)):
                continue
            if kw == "function":
                # nested already opened above for anon; skip structural
                continue
            if kw == "if":
                # block officially starts at then; record pending
                f.blocks.append(Block("if-pending", len(f.actives)))
            elif kw == "then":
                # convert pending if
                if f.blocks and f.blocks[-1].kind == "if-pending":
                    f.blocks[-1].kind = "if"
                else:
                    f.blocks.append(Block("if", len(f.actives)))
            elif kw == "elseif":
                # close previous if-branch locals, keep if block
                if f.blocks and f.blocks[-1].kind in ("if", "elseif"):
                    close_to_nact(f, f.blocks[-1].nact_at_entry)
                    f.blocks[-1].kind = "elseif"
                else:
                    f.blocks.append(Block("elseif", len(f.actives)))
            elif kw == "else":
                if f.blocks and f.blocks[-1].kind in ("if", "elseif"):
                    close_to_nact(f, f.blocks[-1].nact_at_entry)
                    f.blocks[-1].kind = "else"
                else:
                    f.blocks.append(Block("else", len(f.actives)))
            elif kw == "for":
                # vars already added; open block at do
                f.blocks.append(Block("for-pending", len(f.actives), is_loop=True))
            elif kw == "while":
                f.blocks.append(Block("while-pending", len(f.actives), is_loop=True))
            elif kw == "do":
                if f.blocks and f.blocks[-1].kind in ("for-pending", "while-pending"):
                    f.blocks[-1].kind = f.blocks[-1].kind.replace("-pending", "")
                else:
                    f.blocks.append(Block("do", len(f.actives)))
            elif kw == "repeat":
                f.blocks.append(Block("repeat", len(f.actives), is_loop=True))
            elif kw == "until":
                if f.blocks and f.blocks[-1].kind == "repeat":
                    blk = f.blocks.pop()
                    close_to_nact(f, blk.nact_at_entry)
            elif kw == "end":
                closed_fn = pop_block(f, ln)
                if closed_fn:
                    f = stack[-1]
            idx += 1

        note_peak(stack[-1], ln)
        i += 1

    chunk.end = len(lines)

    rows = sorted(
        [(fn.peak, fn.total_declared, fn.start, fn.end or "?", fn.name, fn) for fn in funcs],
        reverse=True,
    )

    print(f"File: {path}")
    print(f"{'peak':>5} {'decl':>5} {'start':>6} {'end':>6}  name")
    print("-" * 72)
    for peak, decl, start, end, name, fn in rows:
        mark = ""
        if peak >= 190:
            mark = " *** CRITICAL"
        elif peak >= 160:
            mark = " ** HIGH"
        elif peak >= 120:
            mark = " * elevated"
        print(f"{peak:5d} {decl:5d} {start:6d} {str(end):>6}  {name}{mark}")

    print()
    print("Detail for peak >= 100:")
    for peak, decl, start, end, name, fn in rows:
        if peak < 100:
            break
        print(f"\n=== {name} @ {start}-{end} peak={peak} (lifetime decls={decl}) @ L{fn.peak_line} ===")
        # show actives at peak in order
        for j, n in enumerate(fn.peak_names, 1):
            print(f"  {j:3d}. {n}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
