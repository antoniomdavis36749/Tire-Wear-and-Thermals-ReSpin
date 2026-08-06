#!/usr/bin/env python3
"""Wrap ctwIntegrateThermals prepare section in do-end; bridge via ctw scratch."""
from __future__ import annotations

import re
import sys
from pathlib import Path

# Params already in scope for whole function — no need to bridge
PARAMS = {"wheelID", "dt", "localEnvTemp", "wd", "w", "data", "mods"}


def parse_names(part: str) -> list[str]:
    part = part.split("=")[0]
    out = []
    for tok in part.split(","):
        tok = tok.strip()
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", tok) and tok != "_":
            out.append(tok)
    return out


def main() -> int:
    path = Path(sys.argv[1])
    lines = path.read_text(encoding="utf-8").splitlines(keepends=True)

    start = next(i for i, l in enumerate(lines) if l.startswith("F.ctwIntegrateThermals"))
    snap = bridge = end = None
    for i in range(start, len(lines)):
        if snap is None and "Snapshot nodes before coupled" in lines[i]:
            snap = i
        if "Bridge locals into ctw scratch for wear helper" in lines[i]:
            bridge = i
        if bridge and i > bridge and lines[i].rstrip() == "end":
            end = i
            break

    local_re = re.compile(r"^\s*local\s+(?!function\b)(.+)$")
    for_re = re.compile(r"^\s*for\s+(.+?)\s+(?:in|=)")
    ident = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\b")

    pre_locals: set[str] = set()
    for i in range(start, snap):
        m = local_re.match(lines[i])
        if m:
            pre_locals.update(parse_names(m.group(1)))
        m = for_re.match(lines[i])
        if m:
            pre_locals.update(parse_names(m.group(1)))
    pre_locals |= PARAMS

    used: set[str] = set()
    for i in range(snap, bridge):
        line = lines[i].split("--")[0]
        used.update(ident.findall(line))

    # Also keep prepare fields that wear bridge still reads at end
    for i in range(bridge, end):
        line = lines[i].split("--")[0]
        used.update(ident.findall(line))

    needed = sorted(
        n
        for n in used
        if n in pre_locals and n not in PARAMS
    )

    # Body structure:
    # start: header
    # start+1 .. snap-1: prepare (wrap in do)
    # snap .. end-1: nodes + wear bridge
    # end: end

    prepare = lines[start + 1 : snap]
    rest = lines[snap:end]

    store = ["\n", "        -- Persist prepare outputs for node/wear scopes\n"]
    for n in needed:
        store.append(f"        ctw.{n} = {n}\n")

    load = ["\n", "    -- Restore prepare outputs (prepare locals ended with do-end)\n"]
    for n in needed:
        load.append(f"    local {n} = ctw.{n}\n")
    load.append("\n")

    new_fn = (
        [lines[start], "    do\n"]
        + prepare
        + store
        + ["    end\n"]
        + load
        + rest
        + [lines[end]]
    )

    out = lines[:start] + new_fn + lines[end + 1 :]
    path.write_text("".join(out), encoding="utf-8")
    print(f"Wrapped prepare do-end; bridged {len(needed)} fields")
    for n in needed:
        print(f"  {n}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
