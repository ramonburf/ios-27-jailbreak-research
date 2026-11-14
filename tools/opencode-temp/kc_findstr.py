#!/usr/bin/env python3
"""Locate a byte string in a kernelcache, print every occurrence VA and the
segment it lands in, plus a short hex context."""
import struct
import sys
from pathlib import Path

BASE = Path("G:/iOS 27.0.1/iOS/firmware")


def segs_of(path):
    d = path.read_bytes()
    ncmds = struct.unpack_from('<I', d, 16)[0]
    off = 32
    out = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', d, off)
        if cmd == 0x19:
            nm = d[off + 8:off + 24].rstrip(b'\0').decode(errors='replace')
            vm, vsz, fo, fsz = struct.unpack_from('<QQQQ', d, off + 24)
            out.append((nm, vm, vsz, fo, fsz))
        off += cmdsize
    return d, out


def find_all(d, segs, needle):
    res = []
    start = 0
    while True:
        i = d.find(needle, start)
        if i < 0:
            break
        va = None
        for nm, vm, vsz, fo, fsz in segs:
            if fo <= i < fo + fsz:
                va = vm + (i - fo)
                res.append((i, va, nm))
                break
        if va is None:
            res.append((i, None, '?'))
        start = i + 1
    return res


if __name__ == "__main__":
    needle = sys.argv[1].encode()
    for label, sub in (("27.0.1", "24A446"), ("27.2", "24B119")):
        p = BASE / sub / "kernelcache.release.macho"
        d, segs = segs_of(p)
        hits = find_all(d, segs, needle)
        print(f"== {label} ({p.name}) : {len(hits)} occurrence(s) of {needle!r}")
        for fo, va, nm in hits[:12]:
            print(f"   file {fo:#x}  va {va if va is None else hex(va)}  seg {nm}")
