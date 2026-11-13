#!/usr/bin/env python3
"""Scan a Mach-O for data words that encode a target virtual address.

iOS arm64e kexts use chained fixups.  For the AGX kexts in this workspace the
encoded target is the low 32 bits of (target - image_base), where image_base is
the start of the kext's __TEXT segment rounded down to 0x1000000.
"""
import argparse
import struct
import sys


def parse(path):
    data = open(path, "rb").read()
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, _ = struct.unpack_from(
        "<IiiIIIII", data, 0
    )
    if magic != 0xFEEDFACF:
        raise SystemExit("not a little-endian 64-bit Mach-O")
    off = 32
    segments = []
    sections = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = data[off + 8:off + 24].rstrip(b"\0").decode()
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, off + 24)
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            segments.append((segname, vmaddr, vmsize, fileoff, filesize))
            so = off + 72
            for _ in range(nsects):
                sectname = data[so:so + 16].rstrip(b"\0").decode()
                seg = data[so + 16:so + 32].rstrip(b"\0").decode()
                addr, size = struct.unpack_from("<QQ", data, so + 32)
                offset = struct.unpack_from("<I", data, so + 48)[0]
                sections.append((seg, sectname, addr, size, offset))
                so += 80
        off += cmdsize
    return data, segments, sections


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("macho")
    ap.add_argument("target", type=lambda s: int(s, 0))
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0xFFFFFE0007000000)
    args = ap.parse_args()

    data, segments, sections = parse(args.macho)
    rel = (args.target - args.base) & 0xFFFFFFFF
    candidates = {rel, args.target & 0xFFFFFFFF}
    print(f"image base  : {args.base:#x}")
    print(f"target      : {args.target:#x}")
    print(f"encoded low32: {rel:#010x} (also {args.target & 0xFFFFFFFF:#010x})")

    hits = []
    for seg, sect, addr, size, off in sections:
        if seg not in ("__DATA_CONST", "__DATA"):
            continue
        for i in range(0, size - 7, 8):
            (val,) = struct.unpack_from("<Q", data, off + i)
            if (val & 0xFFFFFFFF) in candidates:
                hits.append((addr + i, val, seg, sect))
    for va, val, seg, sect in hits:
        print(f"{va:#018x}  {val:#018x}  {seg}.{sect}")
    print(f"hits: {len(hits)}")

    # Also print every section range for convenience.
    print("\nsections:")
    for seg, sect, addr, size, off in sections:
        if seg in ("__DATA_CONST", "__DATA"):
            print(f"  {seg}.{sect:24s} {addr:#018x} size {size:#x} fileoff {off:#x}")


if __name__ == "__main__":
    main()
