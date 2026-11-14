#!/usr/bin/env python3
"""Evidence check: is __TEXT_EXEC plaintext code or ciphertext?
Disassemble a large sample and measure how many words decode to real AArch64."""
import struct
import sys
from pathlib import Path

KC = Path("G:/iOS 27.0.1/iOS/firmware/24A446/kernelcache.release.macho")
data = KC.read_bytes()
ncmds = struct.unpack_from('<I', data, 16)[0]
off = 32
segs = []
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', data, off)
    if cmd == 0x19:
        nm = data[off + 8:off + 24].rstrip(b'\0').decode(errors='replace')
        vm, vsz, fo, fsz = struct.unpack_from('<QQQQ', data, off + 24)
        segs.append((nm, vm, vsz, fo, fsz))
    off += cmdsize

text = [s for s in segs if s[0] == '__TEXT_EXEC'][0]
blob = data[text[3]:text[3] + text[4]]

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
import capstone
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)

# sample windows spread across the segment
sample_windows = [(int(len(blob) * f), 4096) for f in (0.05, 0.25, 0.45, 0.65, 0.85)]
total = ok = 0
for start, size in sample_windows:
    chunk = blob[start:start + size]
    good = 0
    n = 0
    for ins in md.disasm(chunk, text[1] + start):
        n += 1
        if ins.size == 4:
            good += 1
    total += n
    ok += good
    print(f"  window @file {text[3]+start:#x}: {good}/{n} valid 4-byte instructions")

print(f"\noverall: {ok}/{total} = {100.0*ok/max(total,1):.1f}% decode cleanly")

# entropy comparison: code should be lower than random ciphertext
import math
from collections import Counter
c = Counter(blob[:1 << 20])
ent = -sum((v / (1 << 20)) * math.log2(v / (1 << 20)) for v in c.values())
print(f"byte entropy of first 1 MiB of __TEXT_EXEC: {ent:.2f} bits/byte "
      f"(random/ciphertext would be ~8.0)")
