#!/usr/bin/env python3
"""Extract / search the 27.0.1 AGXG18P disassembly (UTF-16LE text dump)."""
import re
import sys
from pathlib import Path

DISASM = Path(r"G:\iOS 27.0.1\iOS\analysis\agx\2701.disasm.txt")
ADDR_RE = re.compile(r"^0x([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*(\S.*)?$")


def load_lines():
    raw = DISASM.read_bytes()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        text = raw.decode("utf-16")
    else:
        text = raw.decode("utf-8", errors="replace")
    return text.splitlines()


def main():
    mode = sys.argv[1]
    lines = load_lines()

    if mode == "range":
        lo = int(sys.argv[2], 0)
        hi = int(sys.argv[3], 0)
        for ln in lines:
            m = ADDR_RE.match(ln)
            if not m:
                continue
            a = int(m.group(1), 16)
            if lo <= a < hi:
                print(ln)
    elif mode == "grep":
        pat = sys.argv[2]
        rx = re.compile(pat)
        for ln in lines:
            if rx.search(ln):
                print(ln)
    elif mode == "xref":
        # find branch instructions whose target == addr
        target = int(sys.argv[2], 0)
        for ln in lines:
            m = ADDR_RE.match(ln)
            if not m:
                continue
            body = m.group(3) or ""
            tm = re.search(r"(?:b|bl|blraa|b\.)\s+0x([0-9a-f]+)", body)
            if tm and int(tm.group(1), 16) == target:
                print(ln)
    elif mode == "func":
        # print the function that contains addr: walk backwards to a pacibsp/bti
        addr = int(sys.argv[2], 0)
        collected = []
        for ln in lines:
            m = ADDR_RE.match(ln)
            if not m:
                continue
            a = int(m.group(1), 16)
            if a <= addr:
                collected.append((a, ln))
        # find last 'pacibsp' or 'bti c' at or before addr -> function start
        start = None
        for a, ln in reversed(collected[-4000:]):
            if "pacibsp" in ln or re.search(r"\bbti\s+c", ln):
                start = a
                break
        if start is None:
            start = collected[-1][0] if collected else addr
        end = addr + 0x400
        for a, ln in collected:
            if a >= start:
                print(ln)
        # continue forward
        started = False
        for ln in lines:
            m = ADDR_RE.match(ln)
            if not m:
                continue
            a = int(m.group(1), 16)
            if a == start:
                started = True
            if started and a < end:
                print(ln)


if __name__ == "__main__":
    main()
