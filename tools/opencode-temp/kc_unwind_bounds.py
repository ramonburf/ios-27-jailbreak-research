#!/usr/bin/env python3
"""Recover exact function boundaries from __unwind_info and report the function
containing each anchor."""
import struct
from pathlib import Path

BASE = Path("G:/iOS 27.0.1/iOS/firmware")
IMAGES = {"27.0.1": (BASE / "24A446" / "kernelcache.release.macho", 0xfffffe000ac891f8),
          "27.2":   (BASE / "24B119" / "kernelcache.release.macho", 0xfffffe000acda594)}


def parse(path, anchor):
    d = path.read_bytes()
    ncmds = struct.unpack_from('<I', d, 16)[0]
    off = 32
    segs = []
    secs = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', d, off)
        if cmd == 0x19:
            segname = d[off + 8:off + 24].rstrip(b'\0').decode(errors='replace')
            vm, vsz, fo, fsz = struct.unpack_from('<QQQQ', d, off + 24)
            segs.append((segname, vm, vsz, fo, fsz))
            nsects = struct.unpack_from('<I', d, off + 64)[0]
            sp = off + 72
            for _ in range(nsects):
                sn = d[sp:sp + 16].rstrip(b'\0').decode(errors='replace')
                sg = d[sp + 16:sp + 32].rstrip(b'\0').decode(errors='replace')
                svm, ssz, sfo = struct.unpack_from('<QQI', d, sp + 32)
                secs.append((sg, sn, svm, ssz, sfo))
                sp += 80
        off += cmdsize

    text = [s for s in segs if s[0] == '__TEXT_EXEC'][0]
    rel = anchor - text[1]

    uw = [s for s in secs if s[1] == '__unwind_info' and s[0] == '__TEXT_EXEC']
    if not uw:
        return None
    _, _, uvm, usz, ufo = uw[0]
    hdr = struct.unpack_from('<7I', d, ufo)
    version, enc_off, enc_cnt, pers_off, pers_cnt, idx_off, idx_cnt = hdr
    print(f"  unwind: version={version} encodings={enc_cnt} pages={idx_cnt}")

    # second level pages are keyed by 4 KB pages
    page = rel // 4096
    idx = struct.unpack_from('<III', d, ufo + idx_off + page * 12)
    fn_off, second_off, lsda_off = idx
    if second_off == 0 or second_off == 0xFFFFFFFF:
        return None
    p = ufo + second_off
    second_version, nelem, encidx_off = struct.unpack_from('<HHI', d, p)
    entries = []
    for i in range(nelem):
        w = struct.unpack_from('<I', d, ufo + encidx_off + 4 * i)[0]
        foff = w & 0xFFFFFF
        entries.append(foff)
    entries.sort()
    base = page * 4096
    inside = [e for e in entries if e <= (rel - base)]
    if not inside:
        return None
    start = base + inside[-1]
    # end = next entry after this one, or page end
    after = [e for e in entries if e > (rel - base)]
    end = base + (after[0] if after else 4096)
    return (text[1] + start, text[1] + min(end, start + 0x4000))


for label, (path, anchor) in IMAGES.items():
    r = parse(path, anchor)
    if r:
        s, e = r
        print(f"{label}: anchor {anchor:#x} -> function {s:#x}..{e:#x}  "
              f"({(e-s)//4} insns)")
    else:
        print(f"{label}: could not resolve (no unwind info for that page)")
