#!/usr/bin/env python3
"""Validate CVE-2026-112514: disassemble soclose_locked / sofree in the 24A446
kernelcache and look for the inlined sb* ops that lack a usecount check."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
_extra = Path(__file__).resolve().parent.parent / "pylibs"
if _extra.is_dir():
    sys.path.insert(0, str(_extra))
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from kc_iosurface import parse_fileset, member_segments, function_starts

KC = sys.argv[1] if len(sys.argv) > 1 else "G:/iOS 27.0.1/iOS/firmware/24A446/kernelcache.release.macho"
TARGETS = [int(a, 16) for a in sys.argv[2:]] or [0xfffffff00b153a3c]

data = Path(KC).read_bytes()
entries, _ = parse_fileset(data)
e = [x for x in entries if x["name"] == "com.apple.kernel"][0]
segs = member_segments(data, e["fileoff"])
print("segments:", {k: [hex(v) for v in v] for k, v in segs.items()})
seg = segs.get("__TEXT_EXEC") or segs.get("__TEXT")
base = seg[0]
foff, fsize = seg[2], seg[3]
text = data[foff:foff + fsize]
print("text base %#x size %#x" % (base, len(text)))

fstarts = function_starts(data, e["fileoff"], e["vmaddr"])
md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
md.detail = False

for addr in TARGETS:
    off = addr - base
    if off < 0 or off >= len(text):
        print("%#x: outside __TEXT" % addr)
        continue
    # find enclosing function start
    fs = max([s for s in fstarts if s <= addr], default=None)
    print("\n==== %#x  (func start %#x) ====" % (addr, fs or 0))
    start = fs if fs else addr
    o = start - base
    cnt = 0
    for ins in md.disasm(text[o:o + 0x800], start):
        print("%#014x  %-10s %s" % (ins.address, ins.mnemonic, ins.op_str))
        cnt += 1
        if cnt > 90:
            break
