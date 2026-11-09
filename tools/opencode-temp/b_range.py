import struct, sys, os
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN

K = r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface'
B = open(K, 'rb').read()
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

def va2off(va):
    for name,(vm,vs,fo,fs) in segs.items():
        if vm <= va < vm+fs:
            return fo + (va-vm)
    return None

start = int(sys.argv[1], 16)
end = int(sys.argv[2], 16)
fo = va2off(start)
n = end - start
md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
md.detail = False
out = []
for insn in md.disasm(B[fo:fo+n], start):
    out.append('  %018x: %-8s %s' % (insn.address, insn.mnemonic, insn.op_str))
print('\n'.join(out))
