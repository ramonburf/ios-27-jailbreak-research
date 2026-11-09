import sys
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN

B = open(r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface','rb').read()
TEXT_OFF  = 0x8000
TEXT_ADDR = 0xfffffe000a3257c0

md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)

starts = [int(x,16) for x in sys.argv[1:]] or [0xfffffe000a34b414]
for va in starts:
    off = TEXT_OFF + (va - TEXT_ADDR)
    print('='*20, hex(va), '='*20)
    n = 0
    for insn in md.disasm(B[off:off+3000], va):
        print('  %018x: %-8s %s' % (insn.address, insn.mnemonic, insn.op_str))
        n += 1
        if insn.mnemonic in ('retab','ret') or n > 220:
            break
    print()
