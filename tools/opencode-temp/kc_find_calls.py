#!/usr/bin/env python3
"""Find all BL targets to a given VA across the kernelcache and print preceding context."""
import sys, struct
from pathlib import Path

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/opencode-temp")
sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
from kc_fstarts import load_build, v2o
import capstone

target = int(sys.argv[1], 0)
A = load_build("24A446")
b = A
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)
data = b["data"]
# scan text segments
for nm, (vm, vsz, fo, fsz) in b["segs"].items():
    if 'TEXT_EXEC' not in nm:
        continue
    code = data[fo:fo + fsz]
    n = len(code) // 4
    for i in range(0, n * 4 - 4, 4):
        w = struct.unpack_from('<I', code, i)[0]
        if (w & 0xFC000000) != 0x94000000:
            continue
        imm = (w & 0x03FFFFFF)
        if imm & 0x02000000:
            imm |= ~0x03FFFFFF
        tgt = (vm + i) + imm * 4
        if tgt != target:
            continue
        site = vm + i
        start = max(fo, fo + i - 8 * 4)
        snippet = data[start:fo + i + 4]
        inslist = list(md.disasm(snippet, vm + i - 8 * 4))
        print("site %#x" % site)
        for ins in inslist[-8:]:
            print("   %016x  %-8s %s" % (ins.address, ins.mnemonic, ins.op_str))
        print()
