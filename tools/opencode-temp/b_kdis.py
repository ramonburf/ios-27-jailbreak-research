import struct, sys, os
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN

K = r'G:\iOS 27.0.1\iOS\tools\agx-reach\kernel_analysis\kexts\com.apple.kernel'
print('size', os.path.getsize(K))
B = open(K, 'rb').read()

magic = struct.unpack_from('<I', B, 0)[0]
print('magic', hex(magic))
ncmds = struct.unpack_from('<I', B, 16)[0]
print('ncmds', ncmds)

segs = {}
off = 32
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', B, off)
    if cmd == 0x19:
        name = B[off+8:off+24].rstrip(b'\0').decode('utf-8','replace')
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', B, off+24)
        segs[name] = (vmaddr, vmsize, fileoff, filesize)
    off += cmdsize

for name,(vmaddr,vmsize,fileoff,filesize) in segs.items():
    print('%-16s vmaddr=%016x vmsize=%x fileoff=%x filesize=%x' % (name, vmaddr, vmsize, fileoff, filesize))

def va2off(va):
    for name,(vmaddr,vmsize,fileoff,filesize) in segs.items():
        if vmaddr <= va < vmaddr + filesize:
            return fileoff + (va - vmaddr)
    return None

md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
for va in [int(x,16) for x in sys.argv[1:]] or [0xfffffe000b2a99e4, 0xfffffe000b2616c0]:
    fo = va2off(va)
    print('\n' + '='*20, hex(va), 'fileoff', hex(fo) if fo is not None else None, '='*20)
    if fo is None:
        print('  VA not mapped'); continue
    n = 0
    for insn in md.disasm(B[fo:fo+2000], va):
        print('  %018x: %-8s %s' % (insn.address, insn.mnemonic, insn.op_str))
        n += 1
        if insn.mnemonic in ('retab','ret') or n > 120:
            break
