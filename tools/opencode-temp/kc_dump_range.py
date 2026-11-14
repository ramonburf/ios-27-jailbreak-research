#!/usr/bin/env python3
"""Dump a kernelcache address range. usage: kc_dump_range.py <24A446|24B119> <start> <end>"""
import struct
import sys
from pathlib import Path

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
import capstone

BASE = Path("G:/iOS 27.0.1/iOS/firmware")
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)

sub = sys.argv[1]
start = int(sys.argv[2], 16)
end = int(sys.argv[3], 16)
p = BASE / sub / "kernelcache.release.macho"
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


def v2o(va):
    for nm, vm, vsz, fo, fsz in segs:
        if vm <= va < vm + vsz:
            return fo + (va - vm)
    raise KeyError(hex(va))


for ins in md.disasm(d[v2o(start):v2o(end)], start):
    print(f"{ins.address:#018x}  {ins.mnemonic:<8} {ins.op_str}")
