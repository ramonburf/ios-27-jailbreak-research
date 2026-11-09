import struct

B = open(r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface','rb').read()

# __DATA_CONST __const
CONST_OFF  = 0x44120
CONST_ADDR = 0xfffffe000837d4f8
CONST_SIZE = 0x46f8
# __TEXT_EXEC __text
TEXT_OFF   = 0x8000
TEXT_ADDR  = 0xfffffe000a3257c0
TEXT_SIZE  = 0x3461c
BASE       = 0xfffffe0007004000

def decode(w):
    return BASE + (w & 0xffffffff)

def va2off(va):
    return TEXT_OFF + (va - TEXT_ADDR)

def is_bti(va):
    if not (TEXT_ADDR <= va < TEXT_ADDR + TEXT_SIZE):
        return False
    off = va2off(va)
    # 'bti c' = 5f 24 03 d5
    return B[off:off+4] == b'\x5f\x24\x03\xd5'

# entry 0 at CONST_ADDR + (0x837fa10-0x837d4f8) = 0x2518
entry0_off = CONST_OFF + 0x2518
STRIDE = 0x28
VAR = 0xffffffff

print('sel  handler            sIn stIn       sOut stOut      bti')
print('-'*70)
for s in range(60):
    off = entry0_off + s*STRIDE
    if off + STRIDE > CONST_OFF + CONST_SIZE:
        break
    w = struct.unpack_from('<Q', B, off)[0]
    sIn, stIn, sOut, stOut = struct.unpack_from('<IIII', B, off+8)
    hv = decode(w)
    print('%3d  %018x  %3d  %08x  %3d  %08x  %s' % (
        s, hv, sIn, stIn, sOut, stOut, 'YES' if is_bti(hv) else 'no'))
