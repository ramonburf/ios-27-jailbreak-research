#!/usr/bin/env python3
"""General ADRP+ADD cross-referencer for kernelcache strings.
Usage: kc_xref.py <needle1> [needle2 ...]
Bitmask scan (no capstone), reliable against embedded data."""
import struct
import sys
from pathlib import Path

KC = Path("firmware/24A446/kernelcache.release.macho")
data = KC.read_bytes()

ncmds = struct.unpack_from('<I', data, 16)[0]
off = 32
segs = []
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', data, off)
    if cmd == 0x19:
        nm = data[off + 8:off + 24].rstrip(b'\0').decode(errors='replace')
        vm, vsz, fo, fsz = struct.unpack_from('<QQQQ', data, off + 24)
        segs.append((nm, vm, vsz, fo, fsz))
    off += cmdsize


def sx(v, b):
    return v - (1 << b) if v & (1 << (b - 1)) else v


def va_of_file(pos):
    for nm, vm, vsz, fo, fsz in segs:
        if fo <= pos < fo + fsz:
            return vm + (pos - fo)
    return None


def find_refs(needle):
    pos = data.find(needle)
    if pos <= 0:
        return None, []
    target = va_of_file(pos)
    hits = []
    for nm, vm, vsz, fo, fsz in segs:
        if 'TEXT' not in nm:
            continue
        code = data[fo:fo + fsz]
        for i in range(0, len(code) - 24, 4):
            w = struct.unpack_from('<I', code, i)[0]
            if (w & 0x9F000000) != 0x90000000:
                continue
            rd = w & 0x1F
            page = ((vm + i) & ~0xFFF) + \
                   (sx((((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3), 21) << 12)
            for j in range(1, 6):
                w2 = struct.unpack_from('<I', code, i + 4 * j)[0]
                if (w2 & 0xFFC00000) == 0x91000000:
                    if ((w2 >> 5) & 0x1F) == rd and \
                       page + ((w2 >> 10) & 0xFFF) == target:
                        hits.append(vm + i)
                    break
                if (w2 & 0xFFC00000) not in (0xF9000000, 0xB9000000,
                                             0x91000000, 0x79000000):
                    break
    return target, hits


for needle in sys.argv[1:]:
    nb = needle.encode()
    tgt, hits = find_refs(nb)
    if tgt is None:
        print(f"{needle!r}: NOT FOUND")
        continue
    print(f"{needle!r}\n  VA {tgt:#x}  refs {[hex(h) for h in hits[:8]]}"
          f"  ({len(hits)} total)")
