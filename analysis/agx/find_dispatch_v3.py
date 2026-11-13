#!/usr/bin/env python3
"""Locate the AGXG18P IOExternalMethodDispatch table by searching for known
handler addresses inside the kext's data segments."""
import struct
import sys
from pathlib import Path

KERNEL_BASE = 0xFFFFFE0007000000

KNOWN = {
    0xFFFFFE00084F0FF0: "sel0x109 handler",
    0xFFFFFE00084F0B98: "sel0x10d entitlement check",
    0xFFFFFE00084F16C8: "sel0x105 dispatcher owner check",
    0xFFFFFE00084E83EC: "command-processing helper",
    0xFFFFFE00084E8914: "sel0x110 handler",
    0xFFFFFE00084E88AC: "sel0x100 branch",
    0xFFFFFE0008556F54: "OOB helper (bitmap reserve)",
    0xFFFFFE000856A5E8: "slot allocator helper",
    0xFFFFFE00084ECFBC: "impl of dispatch idx1 (5-entry table)",
}


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


def main(path):
    data, segs = parse_macho(Path(path))
    targets = {}
    for va, label in KNOWN.items():
        targets[va & 0xFFFFFFFF] = label
        targets[va] = label

    hits = []
    for seg in segs:
        start = seg["fileoff"]
        end = min(seg["fileoff"] + seg["filesize"], len(data))
        for off in range(start, end - 7, 8):
            v = struct.unpack_from("<Q", data, off)[0]
            for key, label in targets.items():
                if v == key:
                    va = seg["vmaddr"] + (off - seg["fileoff"])
                    hits.append((va, off, seg["name"], label, v))
    print(f"# hits for known handlers: {len(hits)}")
    for va, off, segn, label, v in hits:
        print(f"  {va:#018x} (file {off:#x}) seg={segn:14s} -> {label}")

    # For each hit, show the surrounding 48-byte "entry" starting 32 bytes before
    print("\n# context: treat hit as the `implementation` field (entry+32)")
    for va, off, segn, label, v in hits:
        eoff = off - 32
        if eoff < 0:
            continue
        s = struct.unpack_from("<IIII", data, eoff)
        res = struct.unpack_from("<IIII", data, eoff + 16)
        rsv = struct.unpack_from("<Q", data, off + 8)[0]
        eva = None
        for seg in segs:
            if seg["fileoff"] <= eoff < seg["fileoff"] + seg["filesize"]:
                eva = seg["vmaddr"] + (eoff - seg["fileoff"])
        print(f"  entry@{eva:#018x}: scalarIn={s[0]} scalarOut={s[1]} "
              f"structIn={s[2]} structOut={s[3]} reserved={res} rsvPtr={rsv:#x}  [{label}]")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else
         r"G:\iOS 27.0.1\iOS\analysis\agx\2701\com.apple.AGXG18P")
