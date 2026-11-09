import struct, sys, os
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN

K = r'G:\iOS 27.0.1\iOS\tools\agx-reach\kernel_analysis\kexts\com.apple.kernel'
B = open(K, 'rb').read()
ncmds = struct.unpack_from('<I', B, 16)[0]
segs = {}
off = 32
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', B, off)
    if cmd == 0x19:
        name = B[off+8:off+24].rstrip(b'\0').decode('utf-8','replace')
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', B, off+24)
        segs[name] = (vmaddr, vmsize, fileoff, filesize)
    off += cmdsize

def va2off(va):
    for name,(vmaddr,vmsize,fileoff,filesize) in segs.items():
        if vmaddr <= va < vmaddr + filesize:
            return fileoff + (va - vmaddr)
    return None

for va in [0xfffffe0007044828, 0xfffffe0007044820, 0xfffffe0007044830]:
    fo = va2off(va)
    print('%x -> fileoff %x' % (va, fo) if fo is not None else '%x -> unmapped' % va)
    if fo is not None:
        b = B[fo:fo+48]
        print('  hex  :', b.hex())
        print('  ascii:', ''.join(chr(c) if 32 <= c < 127 else '.' for c in b))

print()
md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
for va in [int(x,16) for x in sys.argv[1:]] or [0xfffffe000b2aaaa4]:
    fo = va2off(va)
    print('='*20, hex(va), '='*20)
    n = 0
    for insn in md.disasm(B[fo:fo+1600], va):
        print('  %018x: %-8s %s' % (insn.address, insn.mnemonic, insn.op_str))
        n += 1
        if n > 110:
            break
