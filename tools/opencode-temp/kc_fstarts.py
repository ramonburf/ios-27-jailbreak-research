#!/usr/bin/env python3
"""Function-start loader/disassembler for kernelcache members (LC_FUNCTION_STARTS)."""
import struct, bisect
from pathlib import Path

sys_path_added = False

def load_build(build):
    global sys_path_added
    import sys
    if not sys_path_added:
        sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/opencode-temp")
        sys.path.insert(0, "G:/iOS 27.0.1/iOS/tools/pylibs")
        sys_path_added = True
    from kc_iosurface import parse_fileset, member_segments, member_load_commands
    p = Path("G:/iOS 27.0.1/iOS/firmware") / build / "kernelcache.release.macho"
    data = p.read_bytes()
    entries, _ = parse_fileset(data)
    e = [x for x in entries if x["name"] == "com.apple.kernel"][0]
    foff = e["fileoff"]
    segs = member_segments(data, foff)
    starts = []
    for cmd, eoff, cmdsize in member_load_commands(data, foff):
        if cmd != 0x26:
            continue
        dataoff = struct.unpack_from("<I", data, eoff + 8)[0]
        size = struct.unpack_from("<I", data, eoff + 12)[0]
        q = dataoff; end = dataoff + size; addr = 0
        while q < end:
            val = 0; shift = 0
            while True:
                b = data[q]; q += 1
                val |= (b & 0x7F) << shift
                if not (b & 0x80):
                    break
                shift += 7
            if val == 0:
                break
            addr += val
            starts.append(segs["__TEXT"][0] + addr)
    starts = sorted(set(starts))
    return {"data": data, "segs": segs, "starts": starts}

def v2o(b, va):
    for nm, (vm, vsz, fo, fsz) in b["segs"].items():
        if vm <= va < vm + vsz:
            return fo + (va - vm)
    raise KeyError(hex(va))

def o2v(b, off):
    for nm, (vm, vsz, fo, fsz) in b["segs"].items():
        if fo <= off < fo + fsz:
            return vm + (off - fo)
    raise KeyError(hex(off))

def func_of(b, va):
    s = b["starts"]
    i = bisect.bisect_right(s, va) - 1
    if i < 0:
        return None
    start = s[i]
    nxt = s[i + 1] if i + 1 < len(s) else None
    return start, nxt

def funcs_in(b, lo, hi):
    s = b["starts"]
    i = bisect.bisect_left(s, lo)
    out = []
    while i < len(s) and s[i] < hi:
        nxt = s[i + 1] if i + 1 < len(s) else None
        out.append((s[i], nxt))
        i += 1
    return out


def _sx(v, bits):
    return v - (1 << bits) if v & (1 << (bits - 1)) else v


def cstr_at(b, va, limit=120):
    try:
        off = v2o(b, va)
    except KeyError:
        return None
    ok = False
    for nm, (vm, vsz, fo, fsz) in b["segs"].items():
        if vm <= va < vm + vsz and 'TEXT' in nm:
            ok = True
            break
    if not ok:
        return None
    data = b["data"]
    end = data.find(b"\x00", off, off + limit)
    if end < 0:
        end = off + limit
    raw = data[off:end]
    if len(raw) < 4:
        return None
    try:
        s = raw.decode("ascii")
    except UnicodeDecodeError:
        return None
    if all(32 <= ord(c) < 127 for c in s):
        return s
    return None


def func_refs(b, start, end):
    off_s = v2o(b, start)
    off_e = v2o(b, end)
    code = b["data"][off_s:off_e]
    out = set()
    n = len(code) // 4
    for i in range(0, n * 4 - 24, 4):
        w = struct.unpack_from('<I', code, i)[0]
        if (w & 0x9F000000) != 0x90000000:
            continue
        rd = w & 0x1F
        imm = _sx((((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3), 21) << 12
        page = ((start + i * 4) & ~0xFFF) + imm
        for j in range(1, 9):
            if i + 4 * j + 4 > len(code):
                break
            w2 = struct.unpack_from('<I', code, i + 4 * j)[0]
            top = w2 & 0xFFC00000
            if top in (0x91000000, 0xB1000000):
                if ((w2 >> 5) & 0x1F) == rd:
                    sh = 12 if (top == 0xB1000000 and (w2 & 0x80000000)) else 0
                    tgt = page + (((w2 >> 10) & 0xFFF) << sh)
                    s = cstr_at(b, tgt)
                    if s:
                        out.add(s)
                break
            if top in (0x14000000, 0xB4000000, 0x94000000, 0x12000000,
                       0x54000000, 0xF4000000, 0x52800000, 0x10000000):
                break
    return out

if __name__ == "__main__":
    import sys
    build = sys.argv[1] if len(sys.argv) > 1 else "24A446"
    b = load_build(build)
    print(build, "functions:", len(b["starts"]))
    if len(sys.argv) >= 4:
        lo = int(sys.argv[2], 0); hi = int(sys.argv[3], 0)
        for st, nx in funcs_in(b, lo, hi):
            print("%#x  size=%#x" % (st, (nx - st) if nx else -1))
