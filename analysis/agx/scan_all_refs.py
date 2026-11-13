#!/usr/bin/env python3
"""Scan every Mach-O section for 8-byte words encoding a target address.

The kexts use arm64e chained fixups whose low 32 bits are the target offset from
the kernel image base (0xfffffe0007000000 for the t8150 27.x kernelcache).
"""
import argparse
import struct


def parse(path):
    data = open(path, "rb").read()
    magic, _, _, _, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != 0xFEEDFACF:
        raise SystemExit("not a little-endian 64-bit Mach-O")
    off = 32
    sections = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x19:
            segname = data[off + 8:off + 24].rstrip(b"\0").decode()
            nsects = struct.unpack_from("<I", data, off + 64)[0]
            so = off + 72
            for _ in range(nsects):
                sectname = data[so:so + 16].rstrip(b"\0").decode()
                addr, size = struct.unpack_from("<QQ", data, so + 32)
                offset = struct.unpack_from("<I", data, so + 48)[0]
                sections.append((segname, sectname, addr, size, offset))
                so += 80
        off += cmdsize
    return data, sections


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("macho")
    ap.add_argument("target", type=lambda s: int(s, 0))
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0xFFFFFE0007000000)
    ap.add_argument("--slack", type=lambda s: int(s, 0), default=0)
    args = ap.parse_args()

    data, sections = parse(args.macho)
    rel = (args.target - args.base) & 0xFFFFFFFF
    print(f"target {args.target:#x}; encoded low32 {rel:#010x}; base {args.base:#x}")
    total = 0
    for seg, sect, addr, size, off in sections:
        for i in range(0, size - 7, 8):
            (val,) = struct.unpack_from("<Q", data, off + i)
            low = val & 0xFFFFFFFF
            if abs(low - rel) <= args.slack:
                print(f"{addr+i:#018x}  {val:#018x}  low={low:#010x}  {seg}.{sect}")
                total += 1
    print(f"hits: {total}")


if __name__ == "__main__":
    main()
