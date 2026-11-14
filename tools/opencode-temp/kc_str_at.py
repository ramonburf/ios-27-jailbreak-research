import struct
import sys
from pathlib import Path

BASE = Path("G:/iOS 27.0.1/iOS/firmware")


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


for sub, vas in (("24A446", [0xfffffe00070a69e0, 0xfffffe00070a6a0e, 0xfffffe00070a6abd, 0xfffffe0007094a4b]),
                 ("24B119", [0xfffffe00070a73fe, 0xfffffe00070a742c, 0xfffffe00070a74db, 0xfffffe00070953e4])):
    p = BASE / sub / "kernelcache.release.macho"
    d, segs = load(p)
    print("==", sub)
    for va in vas:
        o = v2o(segs, va)
        e = d.find(b"\0", o, o + 200)
        print(f"   {va:#x}: {d[o:e]!r}")
