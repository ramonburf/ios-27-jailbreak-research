import struct

B = open(r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface','rb').read()

ncmds = struct.unpack_from('<I', B, 16)[0]
off = 32
segs = {}
symtab = None
dysymtab = None
for i in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', B, off)
    name = {
        0x19: 'LC_SEGMENT_64', 0x2: 'LC_SYMTAB', 0xb: 'LC_DYSYMTAB',
        0x80000022: 'LC_DYLD_INFO_ONLY', 0x22: 'LC_DYLD_INFO',
        0x26: 'LC_FUNCTION_STARTS', 0x29: 'LC_DATA_IN_CODE',
        0x80000034: 'LC_DYLD_CHAINED_FIXUPS', 0x80000033: 'LC_DYLD_EXPORTS_TRIE',
        0x1d: 'LC_CODE_SIGNATURE', 0x2a: 'LC_SOURCE_VERSION',
        0x32: 'LC_BUILD_VERSION', 0x24: 'LC_VERSION_MIN_MACOSX',
        0x25: 'LC_VERSION_MIN_IPHONEOS',
    }.get(cmd, hex(cmd))
    print('%2d off=0x%06x cmd=%-28s size=%d' % (i, off, name, cmdsize))
    if cmd == 0x19:
        segname = B[off+8:off+24].rstrip(b'\0').decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', B, off+24)
        segs[segname] = (vmaddr, vmsize, fileoff, filesize)
        print('     seg %-14s vmaddr=%x vmsize=%x fileoff=%x filesize=%x' % (segname, vmaddr, vmsize, fileoff, filesize))
    elif cmd == 0x2:
        symtab = struct.unpack_from('<IIII', B, off+8)
        print('     symoff=%x nsyms=%d stroff=%x strsize=%x' % symtab)
    elif cmd == 0xb:
        dysymtab = struct.unpack_from('<IIIIIIIIIIIIIIIIII', B, off+8)
        print('     dysymtab:', dysymtab)
    off += cmdsize

print('\n--- GOT slots ---')
def fileoff_of(va):
    for name, (vmaddr, vmsize, fileoff, filesize) in segs.items():
        if vmaddr <= va < vmaddr + max(filesize, 1):
            return fileoff + (va - vmaddr)
    return None
for va in [0xfffffe0008383490,0xfffffe0008383498,0xfffffe00083834a0,0xfffffe0008383548,0xfffffe0008383550,0xfffffe0008383558]:
    fo = fileoff_of(va)
    if fo is None:
        print('%x: no file mapping' % va); continue
    w = struct.unpack_from('<Q', B, fo)[0]
    print('%x: fileoff=%x raw=%016x' % (va, fo, w))

if symtab:
    symoff, nsyms, stroff, strsize = symtab
    print('\n--- symbols (%d) ---' % nsyms)
    for i in range(nsyms):
        n_strx, n_type, n_sect, n_desc, n_value = struct.unpack_from('<IBBHQ', B, symoff + 16*i)
        s = B[stroff+n_strx:].split(b'\0')[0].decode('utf-8','replace')
        print('%3d type=%02x sect=%d desc=%04x value=%016x %s' % (i, n_type, n_sect, n_desc, n_value, s))
