import re

K = r'G:\iOS 27.0.1\iOS\tools\opencode-temp\iosurface-extract\com.apple.iokit.IOSurface'
B = open(K, 'rb').read()

# printable ASCII runs (including \0 separators)
runs = re.findall(rb'[ -~]{4,}', B)
seen = set()
out = []
for r in runs:
    try:
        s = r.decode('ascii')
    except Exception:
        continue
    if 'IOSurface' in s and s not in seen:
        seen.add(s)
        out.append(s)

for s in sorted(out):
    print(s)
