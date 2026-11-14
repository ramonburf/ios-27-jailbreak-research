#!/usr/bin/env python3
"""Find inline code references (ADRP+ADD) to the soclose panic string."""
import struct
from pathlib import Path

KC = Path("G:/iOS 27.0.1/iOS/firmware/24A446/kernelcache.release.macho")
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

needle = b'soclose: so=%p refcount=0 @%s:%d'
pos = data.find(needle)
print(f"string found at file {pos:#x}" if pos > 0 else "string NOT FOUND")
if pos <= 0:
    raise SystemExit
target = None
for nm, vm, vsz, fo, fsz in segs:
    if fo <= pos < fo + fsz:
        target = vm + (pos - fo)
        break
print(f"VA {target:#x}")

def sext(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v

hits = []
for nm, vm, vsz, fo, fsz in [s for s in segs if 'TEXT' in s[0]]:
    code = data[fo:fo + fsz]
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
print(f"{len(hits)} references")
for h in hits[:10]:
    print(f"  {h:#x}")
Path("kc_hits.txt").write_text("\n".join(hex(h) for h in hits))
