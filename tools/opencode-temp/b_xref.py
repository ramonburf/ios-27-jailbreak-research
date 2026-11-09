import struct, sys
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN
from capstone.arm64 import ARM64_OP_REG, ARM64_OP_IMM

K = r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface'
B = open(K, 'rb').read()
ncmds = struct.unpack_from('<I', B, 16)[0]
segs = {}
off = 32
for _ in range(ncmds):
    cmd, cs = struct.unpack_from('<II', B, off)
    if cmd == 0x19:
        name = B[off+8:off+24].rstrip(b'\0').decode('utf-8', 'replace')
        vm, vs, fo, fs = struct.unpack_from('<QQQQ', B, off+24)
        segs[name] = (vm, vs, fo, fs)
    off += cs

def va2off(va):
    for name, (vm, vs, fo, fs) in segs.items():
        if vm <= va < vm + fs:
            return fo + (va - vm)
    return None

def off2va(o):
    for name, (vm, vs, fo, fs) in segs.items():
        if fo <= o < fo + fs:
            return vm + (o - fo)
    return None

def find_str(s):
    needle = s.encode() + b'\0'
    idx = B.find(needle)
    while idx != -1:
        va = off2va(idx)
        if va is not None:
            # ensure it's in a readable segment
            return va
        idx = B.find(needle, idx + 1)
    return None

md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
md.detail = True

targets = {}
for s in sys.argv[1:]:
    va = find_str(s)
    targets[va] = s
    print('STR %-45s 0x%x' % (s, va if va else 0))

print('--- segments ---')
for name, (vm, vs, fo, fs) in segs.items():
    if fs:
        print('%-20s vm=0x%x size=0x%x' % (name, vm, fs))

print('--- xrefs ---')
for name, (tvm, tvs, tfo, tfs) in segs.items():
    if 'TEXT' not in name or tfs == 0:
        continue
    pending = {}
    idx = 0
    for insn in md.disasm(B[tfo:tfo+tfs], tvm):
        idx += 1
        m = insn.mnemonic
        ops = insn.operands
        if m == 'adrp' and len(ops) == 2 and ops[0].type == ARM64_OP_REG and ops[1].type == ARM64_OP_IMM:
            pending[ops[0].reg] = (insn.address, ops[1].imm, idx)
        elif m == 'add' and len(ops) == 3 and ops[0].type == ARM64_OP_REG and ops[1].type == ARM64_OP_REG and ops[2].type == ARM64_OP_IMM:
            if ops[1].reg in pending:
                a0, page, i0 = pending[ops[1].reg]
                if idx - i0 <= 12:
                    val = page + ops[2].imm
                    if val in targets:
                        print('XREF 0x%x -> %s  (seg %s adrp 0x%x)' % (a0, targets[val], name, a0))
