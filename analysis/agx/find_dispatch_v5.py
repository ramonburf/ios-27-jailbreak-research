#!/usr/bin/env python3
"""Full AGXG18P IOExternalMethodDispatch scan.

Accepts impl pointers into ANY kernel text range (AGXG18P __TEXT_EXEC,
__PRELINK_TEXT of the kernel collection, and the 0xa0/0xa1/0xb2/0xb3 helper
regions), because AGXDeviceUserClient's dispatch thunks are not all inside
the AGXG18P kext itself.

Also prints, for each contiguous run, the implied selector mapping assuming
the run's first entry is selector 0x100.
"""
import struct
from pathlib import Path

KB = 0xFFFFFE0007000000
MACHO = Path(r"G:\iOS 27.0.1\iOS\analysis\agx\2701\com.apple.AGXG18P")

# (lo, hi) virtual-address ranges that contain kernel code
TEXT_RANGES = [
    (0xFFFFFE00084B1960, 0xFFFFFE0008589960),  # AGXG18P __TEXT_EXEC
    (0xFFFFFE000A000000, 0xFFFFFE000A100000),  # small helper kexts
    (0xFFFFFE000B200000, 0xFFFFFE000B400000),  # __PRELINK_TEXT
]


def parse(path):
    data = path.read_bytes()
    ncmds = struct.unpack_from("<I", data, 16)[0]
    segs, off = [], 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmd == 0x19:
            segname = data[off + 8:off + 24].rstrip(b"\0").decode(errors="replace")
            vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", data, off + 24)
            segs.append({"name": segname, "vmaddr": vmaddr, "vmsize": vmsize,
                         "fileoff": fileoff, "filesize": filesize})
        off += cmdsize
    return data, segs


def dec(v):
    return KB + (v & 0xFFFFFFFF) if v else 0


def in_text(va):
    return any(lo <= va < hi for lo, hi in TEXT_RANGES)


def main():
    data, segs = parse(MACHO)
    rows = []
    for seg in segs:
        if seg["name"] not in ("__DATA_CONST", "__DATA"):
            continue
        base_off = seg["fileoff"]
        n = seg["filesize"]
        for i in range(0, n - 47, 8):
            o = base_off + i
            s = struct.unpack_from("<IIII", data, o)
            impl = dec(struct.unpack_from("<Q", data, o + 32)[0])
            if not in_text(impl):
                continue
            if s[0] > 8 or s[1] > 8 or s[2] > 0x400 or s[3] > 0x400:
                continue
            res = struct.unpack_from("<IIII", data, o + 16)
            if any(r > 0x1000 for r in res):
                continue
            rows.append((seg["vmaddr"] + i, s, impl, res))

    rows.sort()
    runs = []
    for r in rows:
        if runs and r[0] - runs[-1][-1][0] == 48:
            runs[-1].append(r)
        else:
            runs.append([r])

    print(f"# candidate slots: {len(rows)}   runs: {len(runs)}")
    for g in sorted(runs, key=lambda x: -len(x)):
        if len(g) < 2:
            continue
        print(f"\nRUN base={g[0][0]:#018x}  n={len(g)}")
        for i, (va, s, impl, res) in enumerate(g):
            sel = 0x100 + i if g[0][0] == 0xFFFFFE0007F20950 else None
            tag = f" sel?=0x{sel:x}" if sel is not None else ""
            print(f"  [{i:2d}] {va:#018x}{tag} sIn={s[0]} sOut={s[1]} stIn={s[2]} "
                  f"stOut={s[3]} res0={res[0]} impl={impl:#018x}")


if __name__ == "__main__":
    main()
