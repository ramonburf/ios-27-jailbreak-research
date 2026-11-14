#!/usr/bin/env python3
"""Boundary-free comparison: list every string referenced by code (ADRP+ADD) in a
window around each anchor, in address order. Relocation-invariant."""
import re
import struct
from pathlib import Path

BASE = Path("G:/iOS 27.0.1/iOS/firmware")
IMAGES = {"27.0.1": (BASE / "24A446" / "kernelcache.release.macho", 0xfffffe000ac891f8),
          "27.2":   (BASE / "24B119" / "kernelcache.release.macho", 0xfffffe000acda594)}
SPAN = 0x900


def sx(v, b):
    return v - (1 << b) if v & (1 << (b - 1)) else v


def run(path, anchor):
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

    def va_to_off(va):
        for nm, vm, vsz, fo, fsz in segs:
            if vm <= va < vm + vsz:
                return fo + (va - vm)
        return None

    text = [s for s in segs if 'TEXT' in s[0]]
    found = []       # (code_va, string)
    for nm, vm, vsz, fo, fsz in text:
        lo = max(vm, anchor - SPAN)
        hi = min(vm + vsz, anchor + SPAN)
        start = ((lo - vm) + 3) & ~3
        end = (hi - vm) & ~3
        code = d[fo + start:fo + end]
        for i in range(0, len(code) - 24, 4):
            w = struct.unpack_from('<I', code, i)[0]
            if (w & 0x9F000000) != 0x90000000:
                continue
            rd = w & 0x1F
            page = ((vm + start + i) & ~0xFFF) + \
                   (sx((((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3), 21) << 12)
            for j in range(1, 6):
                w2 = struct.unpack_from('<I', code, i + 4 * j)[0]
                if (w2 & 0xFFC00000) == 0x91000000:
                    if ((w2 >> 5) & 0x1F) == rd:
                        t = page + ((w2 >> 10) & 0xFFF)
                        o = va_to_off(t)
                        if o:
                            e = d.find(b'\0', o)
                            s = d[o:e]
                            if 3 <= len(s) <= 160 and all(32 <= c < 127 for c in s):
                                found.append((vm + start + i, s.decode()))
                    break
                if (w2 & 0xFFC00000) not in (0xF9000000, 0xB9000000,
                                             0x91000000, 0x79000000):
                    break
    found.sort()
    seen = set()
    out = []
    for a, s in found:
        if s not in seen:
            seen.add(s)
            out.append((a, s))
    return out


for label, (path, anchor) in IMAGES.items():
    print(f"\n===== {label} =====")
    for a, s in run(path, anchor):
        mark = ""
        if s.startswith(("External objects", "vm_fault_page")):
            mark = "   <<<"
        print(f"  {a:#x}  {s}{mark}")
