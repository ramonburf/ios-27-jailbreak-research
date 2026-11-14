#!/usr/bin/env python3
"""Decode LC_DYLD_CHAINED_FIXUPS in the iOS 27.0.1 kernelcache and hunt for
tables of pointers into __TEXT_EXEC (i.e. the BSD syscall table)."""
import struct
from pathlib import Path

KC = Path("G:/iOS 27.0.1/iOS/firmware/24A446/kernelcache.release.macho")
data = KC.read_bytes()

ncmds = struct.unpack_from('<I', data, 16)[0]
off = 32
segs = []
cf_off = cf_size = None
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', data, off)
    if cmd == 0x19:
        nm = data[off + 8:off + 24].rstrip(b'\0').decode(errors='replace')
        vm, vsz, fo, fsz = struct.unpack_from('<QQQQ', data, off + 24)
        segs.append((nm, vm, vsz, fo, fsz))
    elif cmd == 0x80000034:
        cf_off, cf_size = struct.unpack_from('<II', data, off + 8)
    off += cmdsize

print(f"chained fixups blob at file {cf_off:#x} size {cf_size:#x}")

hdr = struct.unpack_from('<7I', data, cf_off)
ver, starts_off, imports_off, symbols_off, exports_off, lookup_fmt, hint = hdr
print(f"header ver={ver} starts={starts_off:#x} imports={imports_off:#x} "
      f"exports={exports_off:#x} lookup_fmt={lookup_fmt}")
sioff = cf_off + starts_off
seg_count = struct.unpack_from('<I', data, sioff)[0]
print(f"starts_in_image seg_count={seg_count}")

# text range
text = [s for s in segs if s[0] == '__TEXT_EXEC'][0]
tvm, tvs = text[1], text[2]

resolved = {}   # (seg_index, offset_in_seg) -> value

def uleb(p):
    v = 0; s = 0
    while True:
        b = data[p]; p += 1
        v |= (b & 0x7F) << s
        if not (b & 0x80):
            return v, p
        s += 7

for i in range(min(seg_count, len(segs))):
    ent_off = struct.unpack_from('<I', data, sioff + 4 + 4 * i)[0]
    if ent_off == 0:
        continue
    p = sioff + ent_off
    size, page_size, pf, seg_offset, maxvp, page_count = (
        struct.unpack_from('<I', data, p)[0],
        struct.unpack_from('<H', data, p + 4)[0],
        struct.unpack_from('<H', data, p + 6)[0],
        struct.unpack_from('<Q', data, p + 8)[0],
        struct.unpack_from('<I', data, p + 16)[0],
        struct.unpack_from('<H', data, p + 20)[0])
    stride = 4 if pf in (7, 10) else 8
    seg_vm = segs[i][1]
    print(f"  seg[{i}] {segs[i][0]:<16} pf={pf} page_size={page_size:#x} "
          f"stride={stride} pages={page_count}")
    for j in range(page_count):
        ps = struct.unpack_from('<H', data, p + 22 + 2 * j)[0]
        if ps == 0xFFFF:
            continue
        addr = j * page_size + ps
        n = 0
        while True:
            raw = struct.unpack_from('<Q', data, cf_off + 0, ) if False else None
            fpos = segs[i][3] + (seg_offset - segs[i][1]) + addr if False else None
            break
        # absolute file position: segment fileoff corresponds to seg_offset in memory
        base_fo = segs[i][3]
        cur = addr
        guard = 0
        while guard < 10000:
            guard += 1
            fo = base_fo + cur
            if fo + 8 > len(data):
                break
            raw = struct.unpack_from('<Q', data, fo)[0]
            nxt = (raw >> 51) & 0x7FF
            bind = (raw >> 62) & 1
            auth = (raw >> 63) & 1
            if auth:
                tgt = raw & 0xFFFFFFFF
                val = seg_vm + tgt
            else:
                lo = raw & ((1 << 42) - 1)
                hi = (raw >> 42) & 0xFF
                cand_a = (lo << 8) | hi          # ipsw style
                cand_b = (hi << 56) | lo         # alternative
                val = cand_a if (tvm <= cand_a < tvm + tvs) else cand_b
            resolved[(i, cur)] = (val, bind, auth)
            if nxt == 0:
                break
            cur += nxt * stride
        if n:
            pass

print(f"\ndecoded {len(resolved)} chained pointers")

# look for runs of pointers into __TEXT_EXEC within the __DATA_CONST segment
di = [i for i, s in enumerate(segs) if s[0] == '__DATA_CONST']
if di:
    i = di[0]
    items = sorted((o, v) for (si, o), (v, b, a) in resolved.items() if si == i)
    run = []
    best = []
    for o, v in items:
        if tvm <= v < tvm + tvs:
            run.append(o)
        else:
            if len(run) > len(best):
                best = run
            run = []
    if len(run) > len(best):
        best = run
    print(f"__DATA_CONST: longest run of text pointers = {len(best)}")
    if best:
        first = best[0]
        vals = [v for o, v in items if o in set(best[:40])]
        print(f"  starts at seg offset {first:#x} -> vm {segs[i][1] + first:#x}")
        print(f"  first few values: {[hex(v) for v in vals[:8]]}")
