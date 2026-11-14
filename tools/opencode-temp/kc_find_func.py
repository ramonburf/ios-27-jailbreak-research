#!/usr/bin/env python3
"""Find functions whose bodies reference a given string substring."""
import sys, re, bisect
from pathlib import Path

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/opencode-temp")
sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
from kc_fstarts import load_build, v2o, funcs_in
import struct


def sx(v, b):
    return v - (1 << b) if v & (1 << (b - 1)) else v


def cstr_at(b, va, limit=120):
    try:
        off = v2o(b, va)
    except KeyError:
        return None
    ok = False
    for nm, (vm, vsz, fo, fsz) in b["segs"].items():
        if vm <= va < vm + vsz and 'TEXT' in nm:
            ok = True; break
    if not ok:
        return None
    data = b["data"]
    end = data.find(b"\x00", off, off + limit)
    if end < 0:
        end = off + limit
    raw = data[off:end]
    if len(raw) < 4:
        return None
    try:
        s = raw.decode("ascii")
    except UnicodeDecodeError:
        return None
    if all(32 <= ord(c) < 127 for c in s):
        return s
    return None


def func_refs(b, start, end):
    off_s = v2o(b, start); off_e = v2o(b, end)
    code = b["data"][off_s:off_e]
    out = set()
    n = len(code) // 4
    for i in range(0, n * 4 - 24, 4):
        w = struct.unpack_from('<I', code, i)[0]
        if (w & 0x9F000000) != 0x90000000:
            continue
        rd = w & 0x1F
        imm = sx((((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3), 21) << 12
        page = ((start + i * 4) & ~0xFFF) + imm
        for j in range(1, 9):
            if i + 4 * j + 4 > len(code):
                break
            w2 = struct.unpack_from('<I', code, i + 4 * j)[0]
            top = w2 & 0xFFC00000
            if top in (0x91000000, 0xB1000000):
                if ((w2 >> 5) & 0x1F) == rd:
                    sh = 12 if (top == 0xB1000000 and (w2 & 0x80000000)) else 0
                    tgt = page + (((w2 >> 10) & 0xFFF) << sh)
                    s = cstr_at(b, tgt)
                    if s:
                        out.add(s)
                break
            if top in (0x14000000, 0xB4000000, 0x94000000, 0x12000000,
                       0x54000000, 0xF4000000, 0x52800000, 0x10000000):
                break
    return out


def main():
    build = sys.argv[1]
    lo = int(sys.argv[2], 0); hi = int(sys.argv[3], 0)
    needles = sys.argv[4:]
    b = load_build(build)
    idx = {}
    for st, nx in funcs_in(b, lo, hi):
        size = nx - st if nx else 0x400
        for s in func_refs(b, st, st + size):
            idx.setdefault(s, []).append((st, size))
    for nd in needles:
        print("--- needle: %r" % nd)
        found = []
        for s, fl in idx.items():
            if nd.lower() in s.lower():
                for st, size in fl:
                    found.append((st, size, s))
        for st, size, s in sorted(set(found)):
            print("  %#018x sz %#x  <- %s" % (st, size, s[:110]))


if __name__ == "__main__":
    main()
