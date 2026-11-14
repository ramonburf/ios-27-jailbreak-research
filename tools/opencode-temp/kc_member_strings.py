#!/usr/bin/env python3
"""Dump printable strings belonging to one kernelcache MH_FILESET member,
excluding the shared __LINKEDIT region.  Usage: kc_member_strings.py <member-name>
"""
import re
import struct
import sys
from pathlib import Path

ROOT = Path(r"G:\iOS 27.0.1\iOS")
KC = ROOT / "firmware" / "24A446" / "kernelcache.release.macho"
LC_FILESET_ENTRY = 0x80000035
LC_SEGMENT_64 = 0x19


def cstring_at(data, off, limit=512):
    end = data.find(b"\x00", off, off + limit)
    if end < 0:
        end = off + limit
    return data[off:end].decode("ascii", "replace")


def parse_fileset(data):
    off = 32
    entries = []
    ncmds = struct.unpack_from("<I", data, 16)[0]
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmdsize == 0 or off + 8 > len(data):
            break
        if cmd == LC_FILESET_ENTRY:
            vmaddr = struct.unpack_from("<Q", data, off + 8)[0]
            fileoff = struct.unpack_from("<Q", data, off + 16)[0]
            name = cstring_at(data, off + 32)
            entries.append((name, fileoff, vmaddr))
        off += cmdsize
    return entries


def segments(data, foff):
    ncmds = struct.unpack_from("<I", data, foff + 16)[0]
    eoff = foff + 32
    out = []
    for _ in range(ncmds):
        if eoff + 72 > len(data):
            break
        cmd, cmdsize = struct.unpack_from("<II", data, eoff)
        if cmd == LC_SEGMENT_64:
            nm = data[eoff + 8:eoff + 24].rstrip(b"\x00").decode("ascii", "replace")
            vm, vsz, fo, fsz = struct.unpack_from("<QQQQ", data, eoff + 24)
            out.append((nm, vm, vsz, fo, fsz))
        eoff += cmdsize
    return out


def main():
    want = sys.argv[1] if len(sys.argv) > 1 else "com.apple.filesystems.lifs"
    data = KC.read_bytes()
    ent = [e for e in parse_fileset(data) if want in e[0]]
    if not ent:
        print(f"no member matching {want!r}")
        return
    name, foff, vm = ent[0]
    segs = segments(data, foff)
    print(f"# member {name}  fileoff={foff:#x} vmaddr={vm:#x}")
    STR = re.compile(rb"[\x20-\x7e]{4,}")
    seen = set()
    for nm, svm, svsz, sfo, sfsz in segs:
        if nm == "__LINKEDIT":
            continue
        if sfsz == 0 or sfo + sfsz > len(data):
            continue
        blob = data[sfo:sfo + sfsz]
        base_va = svm
        for m in STR.finditer(blob):
            s = m.group().decode("ascii")
            va = base_va + m.start()
            key = (s, nm)
            if key in seen:
                continue
            seen.add(key)
            print(f"{va:#018x} {nm:12s} {s}")


if __name__ == "__main__":
    main()
