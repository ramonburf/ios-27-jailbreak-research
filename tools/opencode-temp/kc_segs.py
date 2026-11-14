import struct
from pathlib import Path

for sub in ("24A446", "24B119"):
    p = Path("firmware") / sub / "kernelcache.release.macho"
    d = p.read_bytes()
    ncmds = struct.unpack_from('<I', d, 16)[0]
    off = 32
    print("==", sub)
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', d, off)
        if cmd == 0x19:
            nm = d[off + 8:off + 24].rstrip(b'\0').decode(errors='replace')
            vm, vsz, fo, fsz = struct.unpack_from('<QQQQ', d, off + 24)
            if 0xfffffe000b1a0000 <= vm <= 0xfffffe000b1e0000 or 'TEXT' in nm:
                print(f"   {nm:20s} vm={vm:#x} vsz={vsz:#x} fo={fo:#x} fsz={fsz:#x}")
        off += cmdsize
