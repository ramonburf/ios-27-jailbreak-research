#!/usr/bin/env python3
"""Mnemonic-level alignment of two kernelcache regions (addresses/operands stripped)
to locate inserted or deleted instructions."""
import difflib
import struct
import sys
from pathlib import Path

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
import capstone

BASE = Path("G:/iOS 27.0.1/iOS/firmware")
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)


def load(path):
    d = path.read_bytes()
    ncmds = struct.unpack_from('<I', d, 16)[0]
    off = 32
    segs = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', d, off)
        if cmd == 0x19:
            nm = d[off + 8:off + 24].rstrip(b'\0').decode(errors='replace')
            vm, vsz, fo, fsz = struct.unpack_from('<QQQQ', d, off + 24)
            segs.append((nm, vm, vsz, fo, fsz))
        off += cmdsize
    return d, segs


def v2o(segs, va):
    for nm, vm, vsz, fo, fsz in segs:
        if vm <= va < vm + vsz:
            return fo + (va - vm)
    raise KeyError(hex(va))


def dump_mnem(path, start, end):
    d, segs = load(path)
    o = v2o(segs, start)
    e = v2o(segs, end)
    out = []
    for ins in md.disasm(d[o:e], start):
        out.append(ins.mnemonic)
    return out


if __name__ == "__main__":
    a_start = int(sys.argv[1], 16)
    a_end = int(sys.argv[2], 16)
    b_start = int(sys.argv[3], 16)
    b_end = int(sys.argv[4], 16)
    A = dump_mnem(BASE / "24A446" / "kernelcache.release.macho", a_start, a_end)
    B = dump_mnem(BASE / "24B119" / "kernelcache.release.macho", b_start, b_end)
    print(f"--- 24A446 {a_start:#x}..{a_end:#x}: {len(A)} insns")
    print(f"--- 24B119 {b_start:#x}..{b_end:#x}: {len(B)} insns")
    sm = difflib.SequenceMatcher(a=A, b=B, autojunk=False)
    n = 0
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            continue
        n += 1
        ctx_a = A[max(0, i1 - 3):i1]
        ctx_b = B[max(0, j1 - 3):j1]
        print(f"\n### {tag} #{n}: A[{i1}:{i2}] ({i2-i1}) vs B[{j1}:{j2}] ({j2-j1})")
        print(f"   before: {' '.join(ctx_a)}")
        print(f"   A: {' '.join(A[i1:i2])}")
        print(f"   B: {' '.join(B[j1:j2])}")
    print(f"\ntotal diff blocks: {n}")
