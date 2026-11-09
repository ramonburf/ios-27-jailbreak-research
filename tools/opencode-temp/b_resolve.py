import struct, sys
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN

KX = r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface'
KK = r'G:\iOS 27.0.1\iOS\tools\agx-reach\kernel_analysis\kexts\com.apple.kernel'

def load(path):
    B = open(path, 'rb').read()
    ncmds = struct.unpack_from('<I', B, 16)[0]
    segs = {}
    off = 32
    for _ in range(ncmds):
        cmd, cs = struct.unpack_from('<II', B, off)
        if cmd == 0x19:
            name = B[off+8:off+24].rstrip(b'\0').decode('utf-8','replace')
            vm, vs, fo, fs = struct.unpack_from('<QQQQ', B, off+24)
            segs[name] = (vm, vs, fo, fs)
        off += cs
    return B, segs

XB, XS = load(KX)
KB, KS = load(KK)

def xoff(va):
    for name,(vm,vs,fo,fs) in XS.items():
        if vm <= va < vm+fs:
            return fo + (va-vm)
    return None

def koff(va):
    for name,(vm,vs,fo,fs) in KS.items():
        if vm <= va < vm+fs:
            return fo + (va-vm)
    return None

md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)

BASE = 0xfffffe0007004000

for s in sys.argv[1:]:
    va = int(s, 16)
    fo = xoff(va)
    insns = list(md.disasm(XB[fo:fo+16], va))
    # find add x17,x17,#imm
    imm = None
    page = 0xfffffe0008383000
    for i in insns:
        if i.mnemonic == 'add' and 'x17' in i.op_str and '#' in i.op_str:
            try: imm = int(i.op_str.split('#')[-1], 0)
            except: pass
    got = page + (imm or 0)
    gfo = xoff(got)
    raw = struct.unpack_from('<Q', XB, gfo)[0]
    target = (raw & 0xffffffff) + BASE
    print('stub %x  got=%x raw=%016x high=%08x target=%x' % (va, got, raw, raw>>32, target))
    kfo = koff(target)
    if kfo is None:
        print('   target unmapped'); continue
    n = 0
    for insn in md.disasm(KB[kfo:kfo+400], target):
        print('   %018x: %-8s %s' % (insn.address, insn.mnemonic, insn.op_str))
        n += 1
        if n >= 25:
            break
    print()
