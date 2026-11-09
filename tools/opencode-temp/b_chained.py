import struct

B = open(r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface','rb').read()

ncmds = struct.unpack_from('<I', B, 16)[0]
off = 32
segments = {}
chained = None
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', B, off)
    if cmd == 0x19:  # LC_SEGMENT_64
        segname = B[off+8:off+24].rstrip(b'\0').decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from('<QQQQ', B, off+24)
        segments[segname] = (vmaddr, vmsize, fileoff, filesize)
    elif cmd == 0x80000034:  # LC_DYLD_CHAINED_FIXUPS
        dataoff, datasize = struct.unpack_from('<II', B, off+8)
        chained = (dataoff, datasize)
    off += cmdsize

print('segments:', {k: (hex(v[0]), hex(v[3])) for k, v in segments.items()})
print('chained:', chained)

dataoff, datasize = chained
fixups_version, starts_offset, imports_offset, symbols_offset, imports_count, imports_format, symbols_format = struct.unpack_from('<IIIIIII', B, dataoff)
print('imports_count=%d format=%d symbols_format=%d' % (imports_count, imports_format, symbols_format))

imps = []
base = dataoff + imports_offset
symbase = dataoff + symbols_offset
for i in range(imports_count):
    if imports_format == 1 or imports_format == 2:
        v = struct.unpack_from('<I', B, base + 4*i)[0]
        lib = v & 0xff
        weak = (v >> 8) & 1
        name_off = (v >> 9) & 0x7fffff
    elif imports_format == 3:
        v = struct.unpack_from('<Q', B, base + 8*i)[0]
        lib = v & 0xffff
        weak = (v >> 16) & 1
        name_off = (v >> 32) & 0xffffffff
    else:
        raise SystemExit('unknown import format')
    s = B[symbase+name_off:].split(b'\0')[0].decode('utf-8', 'replace')
    imps.append(s)

# starts-in-image -> pointer format per segment
starts = dataoff + starts_offset
seg_count = struct.unpack_from('<I', B, starts)[0]
print('seg_count', seg_count)
pointer_formats = {}
seg_order = []
for i in range(seg_count):
    so = struct.unpack_from('<I', B, starts + 4 + 4*i)[0]
    if so == 0:
        seg_order.append(None); continue
    p = starts + so
    size, page_size, pointer_format, segment_offset, max_valid_pointer, page_count = struct.unpack_from('<IHHQIH', B, p)
    pointer_formats[i] = (pointer_format, segment_offset, page_count)
    seg_order.append((pointer_format, segment_offset, page_count))

# map segment index in chained image to segment name (order = load order)
seg_names = []
off = 32
for _ in range(ncmds):
    cmd, cmdsize = struct.unpack_from('<II', B, off)
    if cmd == 0x19:
        seg_names.append(B[off+8:off+24].rstrip(b'\0').decode())
    off += cmdsize

for i, info in enumerate(seg_order):
    if info:
        print('seg %s format=%d seg_offset=0x%x pages=%d' % (seg_names[i] if i < len(seg_names) else '?', info[0], info[1], info[2]))

def fileoff_of(va):
    for name, (vmaddr, vmsize, fileoff, filesize) in segments.items():
        if vmaddr <= va < vmaddr + filesize:
            return fileoff + (va - vmaddr)
    return None

def decode_bind(w, fmt):
    if fmt in (1, 7, 9, 10, 12):  # arm64e family
        if (w >> 63) & 1:  # auth
            if (w >> 62) & 1:  # auth bind
                ordinal = w & 0xffff
                return ('auth_bind', ordinal)
            else:
                target = w & 0xffffffff
                return ('auth_rebase', target)
        else:
            if (w >> 62) & 1:  # bind
                ordinal = w & 0xffff
                return ('bind', ordinal)
            else:
                target = w & 0xffffffff
                return ('rebase', target)
    return ('?', w)

for va in [0xfffffe0008383498, 0xfffffe0008383550, 0xfffffe0008383490, 0xfffffe0008383558]:
    fo = fileoff_of(va)
    w = struct.unpack_from('<Q', B, fo)[0]
    print('\nGOT va=%x fileoff=%x raw=%016x' % (va, fo, w))
    for fmt in (7, 9, 1):
        kind, val = decode_bind(w, fmt)
        if kind in ('bind', 'auth_bind') and val < len(imps):
            print('  fmt=%d %s -> [%d] %s' % (fmt, kind, val, imps[val]))
        else:
            print('  fmt=%d %s %s' % (fmt, kind, hex(val) if isinstance(val, int) else val))

# also print a few imports for sanity
print('\nfirst 10 imports:', imps[:10])
