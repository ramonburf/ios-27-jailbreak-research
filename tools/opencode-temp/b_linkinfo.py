import struct, re

K = r'G:\iOS 27.0.1\iOS\tools\agx-reach\kernel_analysis\kexts\com.apple.kernel'
B = open(K, 'rb').read()
ncmds = struct.unpack_from('<I', B, 16)[0]
segs = {}
off = 32
for _ in range(ncmds):
    cmd, cs = struct.unpack_from('<II', B, off)
    if cmd == 0x19:
        name = B[off+8:off+24].rstrip(b'\0').decode('utf-8','replace')
        vm, vs, fo, fs = struct.unpack_from('<QQQQ', B, off+24)
        segs[name] = (vm, vs, fo, fs)
    off += cs

def off2va(o):
    for name,(vm,vs,fo,fs) in segs.items():
        if fo <= o < fo+fs:
            return vm + (o-fo), name
    return None, None

def va2off(va):
    for name,(vm,vs,fo,fs) in segs.items():
        if vm <= va < vm+fs:
            return fo + (va-vm)
    return None

# strings at __TEXT hits
print('--- __TEXT name strings ---')
for va in [0xfffffe00070bf1c1,0xfffffe00070bf1d2,0xfffffe00070bf208,0xfffffe00070bf21a,
           0xfffffe00070bf267,0xfffffe00070bf39f,0xfffffe00070bf3ac]:
    fo = va2off(va)
    s = B[fo:fo+120].split(b'\0')[0]
    print('0x%x: %r' % (va, s))

# __LINKINFO: find printable runs containing key substrings
vm, vs, fo, fs = segs['__LINKINFO']
blob = B[fo:fo+fs]
print('\n--- __LINKINFO strings matching ---')
for m in re.finditer(rb'[\x20-\x7e]{6,}', blob):
    s = m.group()
    if any(t in s for t in [b'Unserialize', b'Serialize', b'XML', b'Binary', b'Dictionary']):
        print('0x%x  %s' % (vm + m.start(), s.decode('ascii','replace')))

print('\n--- raw around 0xb9e5d8a ---')
fo2 = va2off(0xfffffe000b9e5d8a)
print(B[fo2-80:fo2+200])
