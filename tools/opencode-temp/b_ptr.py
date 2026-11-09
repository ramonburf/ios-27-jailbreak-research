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

def off2va(o):
    for name, (vm, vs, fo, fs) in segs.items():
        if fo <= o < fo + fs:
            return name, vm + (o - fo)
    return None, None

def find_str(s):
    needle = s.encode() + b'\0'
    i = B.find(needle)
    if i < 0:
        return None
    return off2va(i)[1]

for s in sys.argv[1:]:
    va = find_str(s)
    if va is None:
        print('NOTFOUND', s); continue
    pat = struct.pack('<Q', va)
    print('=== %s  0x%x ===' % (s, va))
    start = 0
    while True:
        i = B.find(pat, start)
        if i < 0: break
        start = i + 1
        name, pva = off2va(i)
        print('  ptr at file 0x%x seg %s va 0x%x' % (i, name, pva or 0))
