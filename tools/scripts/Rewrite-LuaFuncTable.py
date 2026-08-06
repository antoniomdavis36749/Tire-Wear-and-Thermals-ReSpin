#!/usr/bin/env python3
"""Rewrite forward-declared locals onto a single F{} table to free main-chunk registers."""
from __future__ import annotations

import re
import sys
from pathlib import Path


def strip_spans(src: str) -> list[tuple[int, int, str]]:
    """Return list of (start, end, kind) for comments/strings to skip."""
    spans: list[tuple[int, int, str]] = []
    i = 0
    n = len(src)
    while i < n:
        if src[i] == "-" and i + 1 < n and src[i + 1] == "-":
            if i + 3 < n and src[i + 2] == "[" and src[i + 3] == "[":
                j = src.find("]]", i + 4)
                end = n if j < 0 else j + 2
                spans.append((i, end, "comment"))
                i = end
                continue
            j = src.find("\n", i)
            end = n if j < 0 else j
            spans.append((i, end, "comment"))
            i = end
            continue
        if src[i] in "\"'":
            q = src[i]
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                j += 1
            spans.append((i, j, "string"))
            i = j
            continue
        if src[i] == "[" and i + 1 < n and src[i + 1] == "[":
            j = src.find("]]", i + 2)
            end = n if j < 0 else j + 2
            spans.append((i, end, "string"))
            i = end
            continue
        i += 1
    return spans


def in_span(pos: int, spans: list[tuple[int, int, str]]) -> bool:
    # binary search
    lo, hi = 0, len(spans)
    while lo < hi:
        mid = (lo + hi) // 2
        s, e, _ = spans[mid]
        if pos < s:
            hi = mid
        elif pos >= e:
            lo = mid + 1
        else:
            return True
    return False


def main() -> int:
    path = Path(sys.argv[1])
    src = path.read_text(encoding="utf-8")
    lines = src.splitlines(keepends=True)

    fwd: list[str] = []
    fwd_start = fwd_end = None
    for i, l in enumerate(lines):
        if "Forward declarations of local functions" in l:
            fwd_start = i
            continue
        if fwd_start is not None and fwd_end is None:
            m = re.match(r"^local ([A-Za-z_][A-Za-z0-9_]*)\s*$", l)
            if m:
                fwd.append(m.group(1))
                continue
            if not fwd:
                continue
            # first non-decl line after decls
            fwd_end = i - 1
            while fwd_end > fwd_start and lines[fwd_end].strip() == "":
                fwd_end -= 1
            break

    if not fwd or fwd_start is None or fwd_end is None:
        print("Could not find forward declaration block", file=sys.stderr)
        return 1

    names = set(fwd)
    print(f"Transforming {len(fwd)} forward decls -> F table")

    # Replace forward decl block with F table
    replacement = (
        "-- Function table: one chunk local instead of N forward decls (Lua ~200 local cap)\n"
        "local F = {}\n"
    )
    new_lines = lines[:fwd_start] + [replacement] + lines[fwd_end + 1 :]
    text = "".join(new_lines)

    # Rewrite definitions: ^Name = function  -> F.Name = function
    def_re = re.compile(
        r"^(" + "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True)) + r")(\s*=\s*function\b)",
        re.M,
    )
    text2, n_defs = def_re.subn(r"F.\1\2", text)
    print(f"Rewrote {n_defs} function definitions")

    # Rewrite identifier references outside strings/comments
    spans = strip_spans(text2)
    # Match name not preceded by . or letter/_ and not followed by letter/_
    # Also skip if already F.name
    pattern = re.compile(
        r"(?<![A-Za-z0-9_.])("
        + "|".join(re.escape(n) for n in sorted(names, key=len, reverse=True))
        + r")(?![A-Za-z0-9_])"
    )

    out: list[str] = []
    last = 0
    n_refs = 0
    for m in pattern.finditer(text2):
        if in_span(m.start(), spans):
            continue
        # Skip if this is the definition we already rewrote as F.Name =
        # (pattern won't match F.Name because of lookbehind for .)
        # Skip table field keys like { update = } — still want F.update for values
        out.append(text2[last : m.start()])
        out.append("F." + m.group(1))
        last = m.end()
        n_refs += 1
    out.append(text2[last:])
    text3 = "".join(out)
    print(f"Rewrote {n_refs} identifier references")

    # Sanity: no bare forward-decl assignments left at line start
    bare = re.findall(
        r"^(" + "|".join(re.escape(n) for n in names) + r")\s*=\s*function\b",
        text3,
        re.M,
    )
    if bare:
        print("WARNING: bare defs remain:", bare[:10], file=sys.stderr)

    path.write_text(text3, encoding="utf-8")
    print(f"Wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
