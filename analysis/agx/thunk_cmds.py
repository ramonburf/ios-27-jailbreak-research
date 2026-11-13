#!/usr/bin/env python3
"""Map AGXG18P dispatch-table impl thunks -> internal command IDs (w1)."""
import re
import sys
from pathlib import Path

DISASM = Path(r"G:\iOS 27.0.1\iOS\analysis\agx\2701.disasm.txt")
ADDR_RE = re.compile(r"^0x([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*(\S.*)?$")

IMPLS = [
    0xFFFFFE00084EDDAC, 0xFFFFFE00084EDD78, 0xFFFFFE00084EDD44,
    0xFFFFFE00084EDD10, 0xFFFFFE00084ED4D4, 0xFFFFFE00084ED4A0,
    0xFFFFFE00084ECFF0, 0xFFFFFE00084ECFBC, 0xFFFFFE00084ECFAC,
    0xFFFFFE00084ECF9C, 0xFFFFFE00084ECB54, 0xFFFFFE00084ECB20,
    0xFFFFFE00084ECAEC, 0xFFFFFE00084ECAB8, 0xFFFFFE00084EDDE0,
    0xFFFFFE00084ECA54, 0xFFFFFE00084EC948, 0xFFFFFE00084EC730,
    0xFFFFFE00084EC904, 0xFFFFFE00084EC718,
]


def main():
    raw = DISASM.read_bytes()
    text = raw.decode("utf-16")
    lines = text.splitlines()

    index = {}
    order = []
    for ln in lines:
        m = ADDR_RE.match(ln)
        if m:
            a = int(m.group(1), 16)
            index[a] = ln
            order.append(a)

    for impl in IMPLS:
        print(f"\n=== impl {impl:#018x} ===")
        found = False
        for a in order:
            if impl <= a < impl + 0x30:
                print("   ", index[a])
                found = True
        if not found:
            print("    (not found in disasm)")


if __name__ == "__main__":
    main()
