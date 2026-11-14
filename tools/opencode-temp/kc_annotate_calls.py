#!/usr/bin/env python3
"""Annotate every BL target inside a function with the callee's strings and size."""
import sys, struct, bisect
from pathlib import Path

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/opencode-temp")
sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
from kc_fstarts import load_build, v2o, func_of, func_refs
import capstone


def main():
    build = sys.argv[1]
    va = int(sys.argv[2], 0)
    size = int(sys.argv[3], 0)
    b = load_build(build)
    md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)
    off = v2o(b, va)
    code = b["data"][off:off + size]
    starts = b["starts"]
    cache = {}
    for ins in md.disasm(code, va):
        if ins.mnemonic != "bl":
            continue
        try:
            tgt = int(ins.op_str.lstrip("#"), 0)
        except ValueError:
            continue
        fc = func_of(b, tgt)
        if not fc:
            print("%#x -> %#x  NOFUNC" % (ins.address, tgt))
            continue
        st = fc[0]
        sz = (fc[1] - st) if fc[1] else -1
        if st not in cache:
            cache[st] = sorted(func_refs(b, st, st + sz), key=len, reverse=True)[:4] if sz > 0 else []
        strs = "; ".join(s[:60] for s in cache[st])
        print("%#x -> %#x sz=%#x  %s" % (ins.address, st, sz, strs))


if __name__ == "__main__":
    main()
