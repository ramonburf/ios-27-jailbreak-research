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
            return vm + (o - fo)
    return None

needle = sys.argv[1].encode()
start = 0
seen = set()
while True:
    i = B.find(needle, start)
    if i < 0:
        break
    start = i + 1
    # back up to preceding NUL
    s = B.rfind(b'\0', 0, i)
    s = s + 1 if s >= 0 else 0
    e = B.find(b'\0', i)
    va = off2va(s)
    if va is None or va in seen:
        continue
    seen.add(va)
    print('0x%x: %r' % (va, B[s:e][:220]))
