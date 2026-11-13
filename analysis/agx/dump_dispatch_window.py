#!/usr/bin/env python3
"""Dump every 48-byte slot in a VA window of the AGXG18P kext, decoding the
XNU IOExternalMethodDispatch layout, with NO filtering so we can see the true
table shape including entries the heuristics rejected."""
import struct
import sys
from pathlib import Path

KERNEL_BASE = 0xFFFFFE0007000000
TEXT_LO = 0xFFFFFE00084B1960
TEXT_HI = 0xFFFFFE0008589960

MACHO = Path(r"G:\iOS 27.0.1\iOS\analysis\agx\2701\com.apple.AGXG18P")


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
            segs.append({"name": segname, "vmaddr": vmaddr, "vmsize": vmsize,
                         "fileoff": fileoff, "filesize": filesize})
        off += cmdsize
    return data, segs


def va_to_off(segs, va):
    for seg in segs:
        if seg["vmaddr"] <= va < seg["vmaddr"] + seg["vmsize"]:
            return seg["fileoff"] + (va - seg["vmaddr"])
    return None


def main():
    lo_va = int(sys.argv[1], 0) if len(sys.argv) > 1 else 0xFFFFFE0007F20800
    hi_va = int(sys.argv[2], 0) if len(sys.argv) > 2 else 0xFFFFFE0007F20E00
    data, segs = parse_macho(MACHO)
    off0 = va_to_off(segs, lo_va)
    print(f"# window {lo_va:#x}..{hi_va:#x} fileoff={off0:#x}")
    va = lo_va
    while va + 48 <= hi_va:
        off = va_to_off(segs, va)
        s = struct.unpack_from("<IIII", data, off)
        res = struct.unpack_from("<IIII", data, off + 16)
        impl_raw = struct.unpack_from("<Q", data, off + 32)[0]
        rsv = struct.unpack_from("<Q", data, off + 40)[0]
        itgt = KERNEL_BASE + (impl_raw & 0xFFFFFFFF) if impl_raw else 0
        rtgt = KERNEL_BASE + (rsv & 0xFFFFFFFF) if rsv else 0
        marker = ""
        if TEXT_LO <= itgt < TEXT_HI:
            marker = " *IMPL*"
        print(f"{va:#018x}: sIn={s[0]:<3} sOut={s[1]:<3} stIn={s[2]:<5} stOut={s[3]:<5} "
              f"res={list(res)} impl={itgt:#018x}{marker} rsv={rtgt:#x}")
        va += 48


if __name__ == "__main__":
    main()
