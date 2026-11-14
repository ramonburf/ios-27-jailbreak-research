#!/usr/bin/env python3
"""For a given A function, find best B counterpart by ref-set overlap and print score."""
import sys
from pathlib import Path

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/opencode-temp")
from kc_fstarts import load_build, func_of, func_refs

A = load_build("24A446")
B = load_build("24B119")
for a in sys.argv[1:]:
    va = int(a, 0)
    fc = func_of(A, va)
    if not fc:
        print("%#x: no A func" % va); continue
    st = fc[0]; sz = (fc[1] - st) if fc[1] else 0x400
    siga = func_refs(A, st, st + sz)
    best = None
    for bst in B["starts"]:
        if not (0xfffffe000b180000 <= bst < 0xfffffe000b1f0000):
            continue
        nxt = None
        # cheap: size from starts list
        i = B["starts"].index(bst)
        nx = B["starts"][i + 1] if i + 1 < len(B["starts"]) else None
        bsz = (nx - bst) if nx else 0x400
        sigb = func_refs(B, bst, bst + bsz)
        if not sigb:
            continue
        inter = len(siga & sigb)
        jac = inter / len(siga | sigb)
        cand = (jac, inter, -abs(bsz - sz))
        if best is None or cand > best[0]:
            best = (cand, bst, bsz, sorted(siga & sigb, key=len, reverse=True)[:3])
    if best:
        cand, bst, bsz, common = best
        print("A %#x sz %#x -> B %#x sz %#x jac %.2f n=%d" % (st, sz, bst, bsz, cand[0], cand[1]))
        for s in common:
            print("     %s" % s[:100])
    else:
        print("A %#x sz %#x -> no B candidate" % (st, sz))
