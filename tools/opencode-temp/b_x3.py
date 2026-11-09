import struct, sys
from capstone import *
from capstone.arm64 import ARM64_OP_IMM

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

# find string start va
def find_str(s):
    needle = s.encode() + b'\0'
    i = B.find(needle)
    if i < 0:
        return None
    for name, (vm, vs, fo, fs) in segs.items():
        if fo <= i < fo + fs:
            return vm + (i - fo)
    return None

targets = {}
for a in sys.argv[1:]:
    va = find_str(a)
    targets[va] = a
    print('STR %-40s 0x%x' % (a, va or 0))

md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
md.detail = True

for name, (tvm, tvs, tfo, tfs) in segs.items():
    if 'TEXT' not in name or tfs == 0:
        continue
    code = B[tfo:tfo+tfs]
    insns = list(md.disasm(code, tvm))
    for i, insn in enumerate(insns):
        if insn.mnemonic != 'adrp' or len(insn.operands) < 2:
            continue
        page = insn.operands[1].imm
        # look ahead 1..10 insns for add with matching low 12
        for j in range(i+1, min(i+11, len(insns))):
            n = insns[j]
            if n.mnemonic == 'add' and len(n.operands) == 3 and n.operands[2].type == ARM64_OP_IMM:
                val = page + n.operands[2].imm
                if val in targets:
                    print('XREF %s  adrp@0x%x+add@0x%x -> 0x%x  next: %s' % (
                        targets[val], insn.address, n.address, val, insns[j+1].mnemonic if j+1 < len(insns) else '?'))
