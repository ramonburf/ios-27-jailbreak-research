#!/usr/bin/env python3
"""Improved normalized diff: masks global-base (adrp-derived) memory displacements."""
import sys, re, difflib

sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/opencode-temp")
sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
from kc_fstarts import load_build, v2o
import capstone

ABSKVA = re.compile(r"#0xfffffe[0-9a-f]+")
TOK = re.compile(r"(#0x[0-9a-f]+|#\-?\d+)")
MEM = re.compile(r"\[([a-z][a-z0-9]*|\w+)((?:,[^\]]*)?)\]")
LOADS = {"ldr", "ldp", "ldur", "ldurs", "ldrsw", "ldrb", "ldrsb", "ldrh",
         "ldrsh", "ldar", "ldarb", "ldarh", "ldxr", "ldxp", "ldadd", "ldadda"}


def reg_name(md, op):
    try:
        return md.reg_name(op.reg)
    except Exception:
        return None


def norm_func(b, va, size):
    md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_LITTLE_ENDIAN)
    md.detail = True
    off = v2o(b, va)
    code = b["data"][off:off + size]
    end = va + size
    glob = set()
    out = []
    for ins in md.disasm(code, va):
        mn = ins.mnemonic
        ops = ins.op_str
        if mn == "adrp":
            rd = reg_name(md, ins.operands[0]) if ins.operands else None
            if rd:
                glob.add(rd)
            out.append("adrp %s,#A" % (rd or "?"))
            continue
        # branch targets
        def repl(m):
            tok = m.group(0)
            try:
                tgt = int(tok.lstrip("#"), 0)
            except ValueError:
                return tok
            if tgt >= 0xfffffe0000000000:
                if va <= tgt < end:
                    return "L%+d" % (tgt - va)
                return "E"
            return tok
        ops = TOK.sub(repl, ops)
        # mask memory displacement when base is a global base
        def memrepl(m):
            base = m.group(1)
            if base in glob:
                return "[%s,#G]" % base
            return m.group(0)
        ops = MEM.sub(memrepl, ops)
        ops = ABSKVA.sub("#A", ops)
        # mask displacement of an adrp+add pair building a global address
        if mn == "add" and len(ins.operands) >= 3 and \
           ins.operands[1].type == capstone.arm64.ARM64_OP_REG and \
           ins.operands[2].type == capstone.arm64.ARM64_OP_IMM:
            base = reg_name(md, ins.operands[1])
            dst = reg_name(md, ins.operands[0])
            if base in glob:
                ops = "add %s,%s,#S" % (dst, base)
        out.append("%s %s" % (mn, ops))
        # update glob set based on writes
        if not ins.operands:
            continue
        op0 = ins.operands[0]
        dst = reg_name(md, op0) if op0.type == capstone.arm64.ARM64_OP_REG else None
        if mn in LOADS:
            continue
        if mn in ("str", "stp", "stur", "sturb", "sturh", "strb", "strh", "stlr",
                  "stlrb", "stlrh", "stxr", "stxp", "swpal", "casa", "casl", "cas"):
            continue
        if dst:
            if dst in glob:
                glob.discard(dst)
            # propagation for address arithmetic / moves
            if mn in ("add", "sub", "orr", "and", "eor", "bic", "mov", "movz",
                      "movk", "adrl", "adr", "csel", "lsl", "lsr", "asr"):
                srcs = [reg_name(md, o) for o in ins.operands[1:]
                        if o.type == capstone.arm64.ARM64_OP_REG]
                if any(s in glob for s in srcs):
                    glob.add(dst)
    return out


def main():
    A = load_build("24A446")
    B = load_build("24B119")
    for spec in sys.argv[1:]:
        parts = [int(x, 0) for x in spec.split(",")]
        a, bsz, sza = parts[0], parts[1], parts[2]
        szb = parts[3] if len(parts) > 3 else sza
        na = norm_func(A, a, sza)
        nb = norm_func(B, bsz, szb)
        if na == nb:
            print("=== A %#x vs B %#x : IDENTICAL (%d insns)" % (a, bsz, len(na)))
            continue
        diff = list(difflib.unified_diff(na, nb, lineterm="", n=2))
        print("=== A %#x (%d) vs B %#x (%d) : %d diff lines" % (a, len(na), bsz, len(nb), len(diff)))
        for line in diff[:80]:
            print("   " + line)


if __name__ == "__main__":
    main()
