#!/usr/bin/env python3
"""Extract the enclosing function around each vm_fault.c anchor, normalise it,
and produce a semantic diff between 27.0.1 and 27.2."""
import difflib
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
import capstone

BASE = Path("G:/iOS 27.0.1/iOS/firmware")
IMAGES = {"27.0.1": (BASE / "24A446" / "kernelcache.release.macho", 0xfffffe000ac891f8),
          "27.2":   (BASE / "24B119" / "kernelcache.release.macho", 0xfffffe000acda594)}
OUT = Path("G:/iOS 27.0.1/iOS/analysis/krw-leads")
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)


def load(p):
    d = p.read_bytes()
    ncmds = struct.unpack_from('<I', d, 16)[0]
    off = 32
    segs = []
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from('<II', d, off)
        if cmd == 0x19:
            nm = d[off + 8:off + 24].rstrip(b'\0').decode(errors='replace')
            vm, vsz, fo, fsz = struct.unpack_from('<QQQQ', data_off := d, off + 24) \
                if False else struct.unpack_from('<QQQQ', d, off + 24)
            segs.append((nm, vm, vsz, fo, fsz))
        off += cmdsize
    return d, segs


def norm(ins):
    """Normalise an instruction for cross-build comparison: drop line numbers and
    absolute addresses, keep operand structure."""
    s = f"{ins.mnemonic} {ins.op_str}"
    s = re.sub(r'#?0x[0-9a-f]{6,}', '#ADDR', s)     # absolute addresses
    s = re.sub(r'#[0-9]+', '#N', s)                 # immediates (incl. line numbers)
    s = re.sub(r'\b(x|w)\d+\b', r'\1R', s)          # register identity kept, number dropped
    return s


results = {}
for label, (path, anchor) in IMAGES.items():
    d, segs = load(path)
    seg = [s for s in segs if s[1] <= anchor < s[1] + s[2]][0]
    start = anchor - 0x800
    end = anchor + 0x1200
    fo = seg[3] + (start - seg[1])
    insns = list(md.disasm(d[fo:fo + (end - start)], start))
    # boundaries: nearest pacibsp before / after the anchor
    before = [i.address for i in insns if i.mnemonic == "pacibsp" and i.address <= anchor]
    after = [i.address for i in insns if i.mnemonic == "pacibsp" and i.address > anchor]
    fn_start = before[-1] if before else insns[0].address
    fn_end = after[0] if after else insns[-1].address
    body = [norm(i) for i in insns if fn_start <= i.address < fn_end]
    results[label] = (fn_start, fn_end, body)
    print(f"{label}: function {fn_start:#x}..{fn_end:#x}  ({len(body)} insns)")

a0, a1, body0 = results["27.0.1"]
b0, b1, body1 = results["27.2"]
diff = list(difflib.unified_diff(body0, body1, lineterm='', n=3,
                                 fromfile=f"27.0.1 {a0:#x}-{a1:#x}",
                                 tofile=f"27.2 {b0:#x}-{b1:#x}"))
print(f"\ndiff lines: {len(diff)}")
OUT.joinpath("vm_fault_func_diff.txt").write_text("\n".join(diff), encoding="utf-8")
print(f"wrote {OUT / 'vm_fault_func_diff.txt'}")
print("\n=== first 60 diff lines ===")
for line in diff[:60]:
    print(line)
