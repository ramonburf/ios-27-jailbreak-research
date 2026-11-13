#!/usr/bin/env python3
"""Find IOExternalMethodDispatch tables using the correct XNU layout.

XNU layout (IOKit/IOUserClient.h):
  struct IOExternalMethodArguments {
      uint32_t scalarInputCount;
      uint32_t scalarOutputCount;
      uint32_t structureInputSize;
      uint32_t structureOutputSize;
      uint32_t reserved[4];
  };
  struct IOExternalMethodDispatch {
      IOExternalMethodArguments selector;   // 32 bytes
      IOExternalMethodDispatchImplementation implementation; // +32
      const char *(*reserved)(void);        // +40
  };                                        // 48 bytes total

The previous scanner used a bogus [func_ptr][u32 x4] layout, which is why it
never found the AGX dispatch table.
"""
import struct
import sys
from pathlib import Path

KERNEL_BASE = 0xFFFFFE0007000000


def parse_macho(path):
    data = path.read_bytes()
    magic = struct.unpack_from("<I", data, 0)[0]
    assert magic == 0xFEEDFACF, hex(magic)
    ncmds = struct.unpack_from("<I", data, 16)[0]
    sections = []
    segs = []
    off = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x19:  # LC_SEGMENT_64
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


def main(path):
    data, segs = parse_macho(Path(path))
    print(f"# {path}")
    for s in segs:
        print(f"SEG {s['name']:16s} vm={s['vmaddr']:#018x} vmsize={s['vmsize']:#x} "
              f"fileoff={s['fileoff']:#x} filesize={s['filesize']:#x}")
        for sc in s["sections"]:
            print(f"    {sc['seg']},{sc['sect']:20s} addr={sc['addr']:#018x} "
                  f"size={sc['size']:#x} off={sc['offset']:#x}")
    print()

    # Collect all executable ranges in this file (for pointer validation)
    exec_ranges = []
    for s in segs:
        for sc in s["sections"]:
            if sc["seg"] in ("__TEXT_EXEC", "__TEXT", "__PRELINK_TEXT") and sc["size"]:
                exec_ranges.append((sc["addr"], sc["addr"] + sc["size"]))

    def looks_like_ptr(v):
        if v == 0:
            return False
        low = v & 0xFFFFFFFF
        for lo, hi in exec_ranges:
            if lo <= low < hi:
                return True
        # also accept base+low32
        t = KERNEL_BASE + low
        for lo, hi in exec_ranges:
            if lo <= t < hi:
                return True
        return False

    # Candidate scan: look for 48-byte dispatch entries
    results = []
    for s in segs:
        if s["name"] not in ("__DATA_CONST", "__DATA", "__PRELINK_DATA", "__LINKEDIT"):
            continue
        start = s["fileoff"]
        end = s["fileoff"] + s["filesize"]
        if end > len(data):
            end = len(data)
        for off in range(start, end - 47, 4):
            s0, s1, s2, s3 = struct.unpack_from("<IIII", data, off)
            if not (s0 <= 0x40 and s1 <= 0x40 and s2 <= 0x1000 and s3 <= 0x1000):
                continue
            # reserved[4] must be small/zero
            res = struct.unpack_from("<IIII", data, off + 16)
            if any(r > 0x10 for r in res):
                continue
            impl = struct.unpack_from("<Q", data, off + 32)[0]
            if not looks_like_ptr(impl):
                continue
            rsv = struct.unpack_from("<Q", data, off + 40)[0]
            if rsv != 0 and not looks_like_ptr(rsv):
                continue
            va = None
            for seg in segs:
                if seg["fileoff"] <= off < seg["fileoff"] + seg["filesize"]:
                    va = seg["vmaddr"] + (off - seg["fileoff"])
            results.append((va, off, s0, s1, s2, s3, impl, rsv))

    print(f"# candidate dispatch entries: {len(results)}")
    # Group into consecutive runs (stride 48)
    results.sort(key=lambda r: r[1])
    groups = []
    for r in results:
        if groups and r[1] - groups[-1][-1][1] == 48:
            groups[-1].append(r)
        else:
            groups.append([r])
    print(f"# groups: {len(groups)}")
    for g in groups:
        if len(g) < 2:
            continue
        print(f"\nTABLE @ {g[0][0]:#018x}  entries={len(g)}")
        for i, (va, off, s0, s1, s2, s3, impl, rsv) in enumerate(g):
            impl_va = impl if impl > 0xFFFF000000000000 else KERNEL_BASE + (impl & 0xFFFFFFFF)
            print(f"  idx {i:3d} va={va:#018x} scalarIn={s0} scalarOut={s1} "
                  f"structIn={s2} structOut={s3} impl={impl_va:#018x}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         r"G:\iOS 27.0.1\iOS\analysis\agx\2701\com.apple.AGXG18P")
