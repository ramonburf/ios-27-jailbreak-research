#!/usr/bin/env python3
"""Align every function in a region across two builds by exact normalized stream."""
import sys, hashlib
from pathlib import Path

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/opencode-temp")
sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
from kc_fstarts import load_build, funcs_in
from kc_norm_diff import norm_func


def main():
    alo, ahi = int(sys.argv[1], 0), int(sys.argv[2], 0)
    blo, bhi = int(sys.argv[3], 0), int(sys.argv[4], 0)
    A = load_build("24A446")
    B = load_build("24B119")
    amap = {}
    bmap = {}
    for tag, bd, lo, hi, mp in (("A", A, alo, ahi, amap), ("B", B, blo, bhi, bmap)):
        n = 0
        for st, nx in funcs_in(bd, lo, hi):
            size = nx - st if nx else 0x400
            lines = norm_func(bd, st, size)
            h = hashlib.md5("\n".join(lines).encode()).hexdigest()
            mp.setdefault(h, []).append((st, size, len(lines)))
            n += 1
        print("%s: %d functions in [%#x,%#x)" % (tag, n, lo, hi))
    ah = set(amap); bh = set(bmap)
    common = ah & bh
    print("exact-normalized matches: %d" % len(common))
    print("\n--- A-only functions (changed or unmatched) ---")
    for h in sorted(ah - bh):
        for st, size, ln in amap[h]:
            print("  A %#x sz %#x insns %d" % (st, size, ln))
    print("\n--- B-only functions (changed or unmatched) ---")
    for h in sorted(bh - ah):
        for st, size, ln in bmap[h]:
            print("  B %#x sz %#x insns %d" % (st, size, ln))


if __name__ == "__main__":
    main()
