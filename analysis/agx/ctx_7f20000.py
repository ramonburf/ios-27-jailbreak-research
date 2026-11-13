#!/usr/bin/env python3
"""Show context around every adrp into the 0xfffffe0007f20000 page (the AGX
__DATA_CONST page holding the AGXDeviceUserClient vtable at 0x7f20270 and the
external-method dispatch tables)."""
import re
import sys
from pathlib import Path

DISASM = Path(r"G:\iOS 27.0.1\iOS\analysis\agx\2701.disasm.txt")
ADDR_RE = re.compile(r"^0x([0-9a-f]+):\s+((?:[0-9a-f]{2} )+)\s*(\S.*)?$")
PAGE = "0xfffffe0007f20000"


def main():
    raw = DISASM.read_bytes()
    lines = raw.decode("utf-16").splitlines()
    parsed = []
    for ln in lines:
        m = ADDR_RE.match(ln)
        if m:
            parsed.append((int(m.group(1), 16), m.group(3) or "", ln))
    idx = {a: i for i, (a, _, _) in enumerate(parsed)}

    want = int(sys.argv[1], 0) if len(sys.argv) > 1 else None
    for i, (a, body, ln) in enumerate(parsed):
        if PAGE not in body:
            continue
        if want is not None and a != want:
            continue
        print(f"\n----- {ln} -----")
        for j in range(i, min(i + 14, len(parsed))):
            print("   ", parsed[j][2])


if __name__ == "__main__":
    main()
