from capstone import *
from capstone.arm64 import *
import struct

data = open('G:\\iOS 27.0.1\\iOS\\analysis\\evidence\\mac\\ajd_extract\\com.apple.driver.AppleJPEGDriver', 'rb').read()
print(f'File size: {len(data)} bytes')

kext_base_vm = 0xfffffe0009002170
kext_base_fo = 0x14000

funcs = {
    'sel1_startDecoder': 0xfffffe000900bdf4,
    'sel3_startEncoder': 0xfffffe000900d094,
    'sel4_startEncoderExt': 0xfffffe000900d4a8,
    'sel5_startDecoderExt': 0xfffffe000900c8f8,
    'sel6_startEncoder2024': 0xfffffe000900dfac,
    'sel7_startDecoder2024': 0xfffffe000900d90c,
}

md = Cs(CS_ARCH_ARM64, CS_MODE_LITTLE_ENDIAN)
md.detail = True

for name, va in funcs.items():
    fo = kext_base_fo + (va - kext_base_vm)
    print(f'=== {name} (va=0x{va:x}, fo=0x{fo:x}) ===')
    code = data[fo:fo+200]
    for insn in md.disasm(code, va):
        print(f'  {insn.address:#x}: {insn.mnemonic}\t{insn.operands}')
    print()
