from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN
import struct

B = open(r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface','rb').read()
TEXT_OFF  = 0x8000
TEXT_ADDR = 0xfffffe000a3257c0
TEXT_SIZE = 0x3461c

def va2off(va):
    return TEXT_OFF + (va - TEXT_ADDR)

md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)

handlers = {
    0:  0xfffffe000a349114,
    9:  0xfffffe000a3493b4,
    10: 0xfffffe000a3494cc,
    11: 0xfffffe000a3496dc,
    19: 0xfffffe000a349934,
    24: 0xfffffe000a349b48,
    26: 0xfffffe000a349cd0,
    46: 0xfffffe000a34a300,
    47: 0xfffffe000a34a464,
    48: 0xfffffe000a34a57c,
    50: 0xfffffe000a34a740,
    54: 0xfffffe000a34a7e4,
}

for sel, va in handlers.items():
    off = va2off(va)
    blob = B[off:off+1200]
    print('='*30, 'sel', sel, '@', hex(va), '='*30)
    n = 0
    for insn in md.disasm(blob, va):
        print('  %018x: %-8s %s' % (insn.address, insn.mnemonic, insn.op_str))
        n += 1
        if insn.mnemonic in ('retab', 'ret') or n > 160:
            break
    print()
