#!/usr/bin/env python3
"""Find all IOExternalMethodDispatch tables in the AGXG18P kext.

Key detail: the kext stores function pointers as arm64e chained fixups:
    raw = 0x8060705d_014ecff0  ->  target VA = (raw & 0xFFFFFFFF) + 0x7000000

XNU layout of one dispatch entry (48 bytes):
    u32 scalarInputCount, scalarOutputCount, structureInputSize, structureOutputSize
    u32 reserved[4]
    u64 implementation (chained ptr)
    u64 reserved
"""
import struct
import sys
from pathlib import Path

KERNEL_BASE = 0xFFFFFE0007000000


def parse_macho(path):
    data = path.read_bytes()
    ncmds = struct.unpack_from("<I", data, 16)[0]
    segs = []
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x19:
            segname = data[off + 8:off + 24].rstrip(b"\0").decode(errors="replace")
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, off + 24)
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            so = off + 72
            seg = {"name": segname, "vmaddr": vmaddr, "vmsize": vmsize,
                   "fileoff": fileoff, "filesize": filesize, "sections": []}
            for _ in range(nsects):
                sectname = data[so:so + 16].rstrip(b"\0").decode(errors="replace")
                segn = data[so + 16:so + 32].rstrip(b"\0").decode(errors="replace")
                addr, size = struct.unpack_from("<QQ", data, so + 32)
                offset = struct.unpack_from("<I", data, so + 48)[0]
                seg["sections"].append({"seg": segn, "sect": sectname, "addr": addr,
                                        "size": size, "offset": offset})
                so += 80
            segs.append(seg)
        off += cmdsize
    return data, segs


def decode_ptr(v):
    """Return target VA if v is a kernel chained pointer, else None."""
    if v == 0:
        return None
    low = v & 0xFFFFFFFF
    if (v >> 63) & 1:  # chained
        return KERNEL_BASE + low
    if v > 0xFFFF000000000000:
        return v
    return KERNEL_BASE + low


def main(path):
    data, segs = parse_macho(Path(path))

    text_ranges = []
    for seg in segs:
        for sc in seg["sections"]:
            if sc["seg"] in ("__TEXT_EXEC", "__TEXT", "__PRELINK_TEXT") and sc["size"]:
                text_ranges.append((sc["addr"], sc["addr"] + sc["size"]))

    def in_text(va):
        return any(lo <= va < hi for lo, hi in text_ranges)

    # ---- pass 1: find every plausible dispatch entry -------------------
    entries = []
    for seg in segs:
        if seg["name"] not in ("__DATA_CONST", "__DATA"):
            continue
        start = seg["fileoff"]
        end = min(seg["fileoff"] + seg["filesize"], len(data))
        for off in range(start, end - 47, 8):
            s0, s1, s2, s3 = struct.unpack_from("<IIII", data, off)
            if s0 > 0x20 or s1 > 0x40 or s2 > 0x1000 or s3 > 0x1000:
                continue
            impl_raw = struct.unpack_from("<Q", data, off + 32)[0]
            impl = decode_ptr(impl_raw)
            if impl is None or not in_text(impl):
                continue
            rsv = struct.unpack_from("<Q", data, off + 40)[0]
            if rsv != 0:
                r = decode_ptr(rsv)
                if r is None or not in_text(r):
                    continue
            va = seg["vmaddr"] + (off - seg["fileoff"])
            entries.append((va, off, s0, s1, s2, s3, impl))

    # ---- pass 2: group consecutive entries (stride 48) -----------------
    entries.sort(key=lambda e: e[1])
    groups = []
    for e in entries:
        if groups and e[1] - groups[-1][-1][1] == 48:
            groups[-1].append(e)
        else:
            groups.append([e])

    print(f"# dispatch entries found: {len(entries)}  groups: {len(groups)}")
    tables = []
    for g in groups:
        if len(g) < 2:
            continue
        tables.append(g)

    print(f"# tables with >=2 entries: {len(tables)}")
    for g in sorted(tables, key=lambda x: -len(x)):
        print(f"\nTABLE @ {g[0][0]:#018x}  entries={len(g)}")
        for i, (va, off, s0, s1, s2, s3, impl) in enumerate(g):
            print(f"  idx {i:3d} scalarIn={s0} scalarOut={s1} structIn={s2} "
                  f"structOut={s3}  impl={impl:#018x}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         r"G:\iOS 27.0.1\iOS\analysis\agx\2701\com.apple.AGXG18P")
