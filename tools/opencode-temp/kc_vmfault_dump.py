#!/usr/bin/env python3
"""Dump the vm_fault.c CoW-assertion region from 27.0.1 and locate the matching
region in 27.2 via the surviving vm_fault_page() panic string."""
import struct
import sys
from pathlib import Path

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
import capstone

BASE = Path("G:/iOS 27.0.1/iOS/firmware")
IMAGES = {"27.0.1": BASE / "24A446" / "kernelcache.release.macho",
          "27.2":   BASE / "24B119" / "kernelcache.release.macho"}
OUT = Path("G:/iOS 27.0.1/iOS/analysis/krw-leads")

md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)


def load(p):
    d = p.read_bytes()
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


def seg_at(segs, va):
    return [s for s in segs if s[1] <= va < s[1] + s[2]][0]


def sx(v, b):
    return v - (1 << b) if v & (1 << (b - 1)) else v


def xref(d, segs, needle):
    pos = d.find(needle)
    if pos <= 0:
        return None
    target = None
    for nm, vm, vsz, fo, fsz in segs:
        if fo <= pos < fo + fsz:
            target = vm + (pos - fo)
            break
    hits = []
    for nm, vm, vsz, fo, fsz in [s for s in segs if 'TEXT' in s[0]]:
        code = d[fo:fo + fsz]
        for i in range(0, len(code) - 24, 4):
            w = struct.unpack_from('<I', code, i)[0]
            if (w & 0x9F000000) != 0x90000000:
                continue
            rd = w & 0x1F
            page = ((vm + i) & ~0xFFF) + (sx((((w >> 5) & 0x7FFFF) << 2) |
                                             ((w >> 29) & 3), 21) << 12)
            for j in range(1, 6):
                w2 = struct.unpack_from('<I', code, i + 4 * j)[0]
                if (w2 & 0xFFC00000) == 0x91000000:
                    if ((w2 >> 5) & 0x1F) == rd and page + ((w2 >> 10) & 0xFFF) == target:
                        hits.append(vm + i)
                    break
                if (w2 & 0xFFC00000) not in (0xF9000000, 0xB9000000, 0x91000000, 0x79000000):
                    break
    return target, hits


def dump(d, segs, start, end, out_path, title):
    seg = seg_at(segs, start)
    fo = seg[3] + (start - seg[1])
    lines = [title, ""]
    for ins in md.disasm(d[fo:fo + (end - start)], start):
        lines.append(f"{ins.address:#018x}  {ins.bytes.hex():<8}  {ins.mnemonic:<9} {ins.op_str}")
    out_path.write_text("\n".join(lines), encoding="utf-8")
    print(f"wrote {out_path} ({len(lines)-2} instructions)")


NEEDLE = b'vm_fault_page(): unexpected error %d from vm_compressor_pager_get()'

for label, path in IMAGES.items():
    d, segs = load(path)
    t, hits = xref(d, segs, NEEDLE)
    print(f"{label}: string VA {t if t is None else hex(t)}, xrefs {[hex(h) for h in hits[:5]]}")

# 27.0.1: the known pre-fix site
d_old, segs_old = load(IMAGES["27.0.1"])
dump(d_old, segs_old, 0xfffffe000ac89000, 0xfffffe000ac89260,
     OUT / "vm_fault_cow_27.0.1.txt", "# vm_fault.c CoW assertion region -- iOS 27.0.1 (24A446)\n")

# 27.2: locate via the surviving sibling string
d_new, segs_new = load(IMAGES["27.2"])
t, hits = xref(d_new, segs_new, NEEDLE)
print("27.2 anchor:", hex(hits[0]) if hits else None)
if hits:
    c = hits[0]
    dump(d_new, segs_new, c - 0x120, c + 0x140,
         OUT / "vm_fault_cow_27.2.txt", "# vm_fault.c region -- iOS 27.2 (24B119), located via sibling string\n")
