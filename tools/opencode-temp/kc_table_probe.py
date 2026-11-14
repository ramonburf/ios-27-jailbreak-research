#!/usr/bin/env python3
"""Analyse the decoded chained-pointer runs: stride, and whether the suspected
bsd_syscall_table address resolves to a text pointer."""
import struct
from pathlib import Path

KC = Path("G:/iOS 27.0.1/iOS/firmware/24A446/kernelcache.release.macho")
data = KC.read_bytes()
ncmds = struct.unpack_from('<I', data, 16)[0]
off = 32
segs = []
cf_off = None
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', data, off)
    if cmd == 0x19:
        nm = data[off + 8:off + 24].rstrip(b'\0').decode(errors='replace')
        vm, vsz, fo, fsz = struct.unpack_from('<QQQQ', data, off + 24)
        segs.append((nm, vm, vsz, fo, fsz))
    elif cmd == 0x80000034:
        cf_off, cf_size = struct.unpack_from('<II', data, off + 8)
    off += cmdsize

sioff = cf_off + struct.unpack_from('<I', data, cf_off + 4)[0]
seg_count = struct.unpack_from('<I', data, sioff)[0]
text = [s for s in segs if s[0] == '__TEXT_EXEC'][0]
tvm, tvs = text[1], text[2]

def decode_segment(i):
    ent_off = struct.unpack_from('<I', data, sioff + 4 + 4 * i)[0]
    if ent_off == 0:
        return {}
    p = sioff + ent_off
    page_size, pf = (struct.unpack_from('<H', data, p + 4)[0],
                     struct.unpack_from('<H', data, p + 6)[0])
    page_count = struct.unpack_from('<H', data, p + 20)[0]
    stride = 4 if pf in (7, 10) else 8
    base_fo = segs[i][3]
    out = {}
    for j in range(page_count):
        ps = struct.unpack_from('<H', data, p + 22 + 2 * j)[0]
        if ps == 0xFFFF:
            continue
        cur = j * page_size + ps
        guard = 0
        while guard < 100000:
            guard += 1
            fo = base_fo + cur
            if fo + 8 > len(data):
                break
            raw = struct.unpack_from('<Q', data, fo)[0]
            nxt = (raw >> 51) & 0x7FF
            auth = (raw >> 63) & 1
            if auth:
                val = segs[i][1] + (raw & 0xFFFFFFFF)
            else:
                lo = raw & ((1 << 42) - 1)
                hi = (raw >> 42) & 0xFF
                cand_a = (lo << 8) | hi
                cand_b = (hi << 56) | lo
                val = cand_a if (tvm <= cand_a < tvm + tvs) else cand_b
            out[cur] = val
            if nxt == 0:
                break
            cur += nxt * stride
    return out

# analyse the longest text-pointer run found previously
i = [k for k, s in enumerate(segs) if s[0] == '__DATA_CONST'][0]
res = decode_segment(i)
items = sorted(res.items())
run, best = [], []
for o, v in items:
    if tvm <= v < tvm + tvs:
        run.append((o, v))
    else:
        if len(run) > len(best):
            best = run
        run = []
if len(run) > len(best):
    best = run

print(f"longest run: {len(best)} entries, offsets {best[0][0]:#x}..{best[-1][0]:#x}")
deltas = {}
for a, b in zip(best, best[1:]):
    d = b[0] - a[0]
    deltas[d] = deltas.get(d, 0) + 1
print("delta histogram:", sorted(deltas.items(), key=lambda kv: -kv[1])[:5])

# probe the address claimed by the older symbol dump for bsd_syscall_table
suspect = 0xfffffe0007eaee90
so = suspect - segs[i][1]
print(f"\nsuspected bsd_syscall_table seg offset {so:#x}")
if so in res:
    print(f"  resolves to {res[so]:#x}  in_text={tvm <= res[so] < tvm + tvs}")
else:
    print("  no chained entry at that offset (may not be a pointer slot)")

# dump the 16 quadwords around the suspected table, resolving those that are chains
for k in range(-2, 18):
    o = so + k * 8
    raw = struct.unpack_from('<Q', data, segs[i][3] + o)[0]
    tag = ""
    if o in res:
        tag = f" -> {res[o]:#x}"
    print(f"  +{k*8:#05x}: {raw:#018x}{tag}")
