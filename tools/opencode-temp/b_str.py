import struct, sys

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

for arg in sys.argv[1:]:
    va = int(arg, 16)
    o = va2off(va)
    if o is None:
        print('%x: NOT MAPPED' % va)
        continue
    end = B.index(b'\0', o)
    s = B[o:end]
    print('%x: %r' % (va, s[:200]))
