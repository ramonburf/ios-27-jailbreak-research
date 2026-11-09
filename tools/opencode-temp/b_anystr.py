import struct, sys, os

FILES = [
    r'G:\iOS 27.0.1\iOS\tools\agx-reach\kernel_analysis\kexts\com.apple.kernel',
    r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface',
]

def load(path):
    B = open(path, 'rb').read()
    if B[:4] != b'\xcf\xfa\xed\xfe':
        return None
    ncmds = struct.unpack_from('<I', B, 16)[0]
    segs = []
    off = 32
    for _ in range(ncmds):
        cmd, cs = struct.unpack_from('<II', B, off)
        if cmd == 0x19:
            name = B[off+8:off+24].rstrip(b'\0').decode('utf-8', 'replace')
            vm, vs, fo, fs = struct.unpack_from('<QQQQ', B, off+24)
            segs.append((name, vm, vs, fo, fs))
        off += cs
    return B, segs

IMGS = []
for f in FILES:
    try:
        r = load(f)
        if r:
            IMGS.append((f, r[0], r[1]))
    except Exception as e:
        print('skip', f, e)

def va2off(va):
    for f, B, segs in IMGS:
        for name, vm, vs, fo, fs in segs:
            if vm <= va < vm + fs:
                return f, B, fo + (va - vm)
    return None, None, None

for arg in sys.argv[1:]:
    va = int(arg, 16)
    f, B, o = va2off(va)
    if o is None:
        print('%x: NOT MAPPED' % va)
        continue
    end = B.index(b'\0', o)
    print('%x: %r   [%s]' % (va, B[o:end][:200], os.path.basename(f)))
