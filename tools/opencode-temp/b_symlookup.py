import json, bisect

P = r'G:\iOS 27.0.1\iOS\tools\agx-reach\kernel_analysis\kernelcache.release.macho.symbols.json'
raw = json.load(open(P, 'r', encoding='utf-8'))
syms = {}
for k, v in raw.items():
    try:
        a = int(k)
    except ValueError:
        a = int(k, 16)
    syms[a] = v

keys = sorted(syms)
print('total symbols:', len(syms))

def show(va):
    print('\nVA 0x%x' % va)
    if va in syms:
        print('  EXACT:', syms[va])
    i = bisect.bisect_right(keys, va) - 1
    if i >= 0:
        print('  nearest <=: 0x%x  %s  (+0x%x)' % (keys[i], syms[keys[i]], va - keys[i]))
    j = bisect.bisect_left(keys, va)
    if j < len(keys):
        print('  nearest >=: 0x%x  %s  (-0x%x)' % (keys[j], syms[keys[j]], keys[j] - va))

for va in [0xfffffe000b2a99e4, 0xfffffe000b2616c0, 0xfffffe000b2a99e0, 0xfffffe000b2a9a00]:
    show(va)

print('\n--- names matching parser/cast/dict ---')
for va in keys:
    n = syms[va]
    if any(s in n for s in ['Unserialize', 'Serializ', 'Dictionary', 'XML', 'safeMetaCast',
                            'OSData::', 'OSString::', 'OSArray::', 'OSCollection::',
                            'OSObject::', 'metaCast', 'OSSerialize']):
        print('  0x%x  %s' % (va, n))
