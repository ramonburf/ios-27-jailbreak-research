#!/usr/bin/env python3
"""Find ADRP+ADD code references to a target VA inside a kernelcache."""
import struct
import sys
from pathlib import Path

BASE = Path("G:/iOS 27.0.1/iOS/firmware")


def sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


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


def xrefs(d, segs, target):
    hits = []
    for nm, vm, vsz, fo, fsz in [s for s in segs if 'TEXT' in s[0]]:
        code = d[fo:fo + fsz]
        n = len(code) // 4
        for i in range(0, n * 4 - 16, 4):
            w = struct.unpack_from('<I', code, i)[0]
            if (w & 0x9F000000) != 0x90000000:
                continue
            rd = w & 0x1F
            imm = sext((((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3), 21) << 12
            page = ((vm + i) & ~0xFFF) + imm
            for j in range(1, 6):
                w2 = struct.unpack_from('<I', code, i + 4 * j)[0]
                if (w2 & 0xFFC00000) == 0x91000000:
                    if ((w2 >> 5) & 0x1F) == rd and page + ((w2 >> 10) & 0xFFF) == target:
                        hits.append(vm + i)
                    break
                if (w2 & 0xFFC00000) not in (0xF9000000, 0xB9000000, 0x91000000, 0x79000000):
                    break
    return sorted(set(hits))


if __name__ == "__main__":
    target = int(sys.argv[1], 16)
    label = sys.argv[2] if len(sys.argv) > 2 else ""
    p = BASE / "24A446" / "kernelcache.release.macho"
    if len(sys.argv) > 3:
        p = BASE / sys.argv[3] / "kernelcache.release.macho"
    d, segs = load(p)
    h = xrefs(d, segs, target)
    print(f"== {p.parent.name} {label}: {len(h)} xref(s) to {target:#x}")
    for a in h:
        print(f"   {a:#x}")
