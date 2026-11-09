import struct

K = r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface'
B = open(K, 'rb').read()

BASE = 0xFFFFFE0007004000
TBL = 0x46638

for i in range(60):
    o = TBL + i * 0x28
    if o + 0x28 > len(B):
        break
    a = struct.unpack_from('<Q', B, o)[0]
    sin, stin, sout, stout = struct.unpack_from('<IIII', B, o + 8)
    h = a & 0xFFFFFFFF
    print('sel %2d: action=%016x handler=0x%x sIn=%u stIn=0x%x sOut=%u stOut=0x%x' % (
        i, a, BASE + h, sin, stin, sout, stout))
