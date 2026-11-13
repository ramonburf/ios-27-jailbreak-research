#!/usr/bin/env python3
"""Phase 4 #1 scoping: kext lifetime / UAF triage over the 27.0.1 kernelcache.

For every MH_FILESET entry in the 27.0.1 (24A446) kernelcache we extract the
embedded Mach-O, pull its printable strings and score it on two axes:

  * REACH  -- does the kext expose an IOKit user client / external-method
              surface that a sandboxed app could reach, and is it gated?
  * LIFE   -- does the kext have a complicated object lifecycle (alloc/free/
              retain/release/terminate, reference collections, memory
              descriptors, notification ports, command gates) where a
              use-after-free or type confusion could plausibly live?

The output is a ranking, not a vulnerability claim.  Every score is backed by
the literal strings that produced it so a human can re-check the evidence.

Usage:
    python analysis/kext-scope/scope_kexts.py
Outputs:
    analysis/kext-scope/kext-scope.json
    analysis/kext-scope/kext-scope.tsv
    analysis/evidence/kext-scope-27.0.1.txt
"""
import json
import re
import struct
from pathlib import Path

ROOT = Path(r"G:\iOS 27.0.1\iOS")
KC = ROOT / "firmware" / "24A446" / "kernelcache.release.macho"
OUT_DIR = ROOT / "analysis" / "kext-scope"
EV_DIR = ROOT / "analysis" / "evidence"

LC_FILESET_ENTRY = 0x80000035
MH_MAGIC_64 = 0xFEEDFACF
LC_SEGMENT_64 = 0x19

# ---------------------------------------------------------------------------
# Signal dictionaries
# ---------------------------------------------------------------------------

# IOKit user-client / external-method surface.
REACH_STRONG = [
    "IOUserClient",              # a user-client class exists in the kext
    "getTargetAndMethodForIndex",
    "IOExternalMethodDispatch",
    "IOExternalMethodArguments",
    "externalMethod",
    "IOExternalMethod",
    "IOUserClientMethodDispatch",
]
REACH_WEAK = [
    "IOServiceMatching",
    "IOServiceOpen",
    "IOConnectCallMethod",
    "IOMessagePort",
    "IOService::",
    "publishService",
    "IOConnectCallStructMethod",
    "IOMemoryDescriptor",
]
# Gating: a kext that checks entitlements is less likely to be sandbox-reachable.
GATE_STRONG = [
    "clientHasPrivilege",
    "clientHasAuthorization",
    "entitlement",
    "Entitlement",
    "has_entitlement",
]
GATE_PRIVATE = ["com.apple.private."]

# Object-lifetime / reference-counting complexity.
LIFE_ALLOC = [
    "alloc", "malloc", "calloc", "realloc", "kalloc", "IOAlloc",
    "IOBufferMemoryDescriptor", "IOMemoryDescriptor",
]
LIFE_FREE = [
    "free", "kfree", "IOFree", "release", "dealloc",
]
LIFE_REF = [
    "retain", "release", "OSObject", "IORecursiveLock",
    "IOMutex", "IONotificationPort", "IOWorkLoop",
    "commandGate", "IOService::",
    "removeObject", "addObject", "setObject", "getObject",
    "OSDictionary", "OSArray", "OSSet", "OSOrderedSet",
    "IOReturn", "wakeup", "wait",
]
LIFE_LIFECYCLE = [
    "terminate", "willTerminate", "didTerminate", "detach", "attach",
    "open", "close", "start", "stop", "reset", "suspend", "wake",
    "free", "destroy", "destroyClient", "clientHasPrivilege",
    "sessionClose", "sessionOpen", "handleClientDeath",
]

# GPU / IOSurface surface -- the F1 (IOGPU + Metal cross-object overlap)
# line of work needs to know which kexts own these paths on t8150.
GPU_SIGNALS = [
    "IOSurface", "IOSurfaceRoot", "IOSurfaceCreate", "IOSurfaceLookup",
    "MTLDevice", "MTLBuffer", "MTLResource", "Metal",
    "IOGPU", "AGX", "AppleGpu", "GPU",
    "tileData", "dataPerSlice", "headerPerSlice", "tileRow",
    "gpuAddress", "commandBuffer",
]


def cstring_at(data: bytes, off: int, limit: int = 512) -> str:
    end = data.find(b"\x00", off, off + limit)
    if end < 0:
        end = off + limit
    return data[off:end].decode("ascii", "replace")


def parse_fileset(data: bytes):
    """Yield (name, file_off, size, vmaddr) for every MH_FILESET entry."""
    magic, _, _, filetype, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", data, 0)
    if magic != MH_MAGIC_64 and magic != 0xFEEDFACE:
        raise SystemExit(f"unexpected magic {magic:#x}")
    off = 32
    entries = []
    for _ in range(ncmds):
        if off + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack_from("<II", data, off)
        if cmdsize == 0:
            break
        if cmd == LC_FILESET_ENTRY:
            # struct fileset_entry_command {
            #   uint32_t cmd; uint32_t cmdsize;
            #   uint64_t vmaddr; uint64_t fileoff;
            #   uint32_t entry_id; uint32_t reserved;
            # };  followed by a NUL-terminated name.
            # Verified against the 27.0.1 kernelcache: name starts at +32.
            vmaddr = struct.unpack_from("<Q", data, off + 8)[0]
            fileoff = struct.unpack_from("<Q", data, off + 16)[0]
            entry_id = struct.unpack_from("<I", data, off + 24)[0]
            name = cstring_at(data, off + 32)
            entries.append({
                "name": name,
                "vmaddr": vmaddr,
                "fileoff": fileoff,
                "entry_id": entry_id,
            })
        off += cmdsize
    return entries, filetype


def macho_segments(data: bytes, foff: int):
    """[(segname, fileoff, filesize)] of the embedded Mach-O at *foff*.

    NOTE: in an Apple kernelcache the fileset members are *prelinked* -- their
    LC_SEGMENT_64 file offsets are ABSOLUTE offsets into the kernelcache file,
    not relative to the member's own start.  __TEXT is contiguous with the
    member's file offset, but __TEXT_EXEC / __DATA / __DATA_CONST live in
    shared regions, and __LINKEDIT is one single blob shared by every kext.

    Consequence: you cannot get a member's size from "max end of its segments"
    (that yields the whole kernelcache) and you must not scan __LINKEDIT when
    attributing strings to a single kext.
    """
    if foff + 32 > len(data):
        return []
    _, _, _, _, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", data, foff)
    eoff = foff + 32
    out = []
    for _ in range(ncmds):
        if eoff + 72 > len(data):
            break
        ecmd, ecmdsize = struct.unpack_from("<II", data, eoff)
        if ecmd == LC_SEGMENT_64:
            name = data[eoff + 8:eoff + 24].rstrip(b"\x00").decode("ascii", "replace")
            # struct segment_command_64 {
            #   uint32_t cmd; uint32_t cmdsize; char segname[16];
            #   uint64_t vmaddr;  uint64_t vmsize;
            #   uint64_t fileoff; uint64_t filesize;
            #   ...
            # };  -> fileoff is at +40 and filesize at +48 (NOT +32/+40).
            seg_fileoff = struct.unpack_from("<Q", data, eoff + 40)[0]
            seg_filesize = struct.unpack_from("<Q", data, eoff + 48)[0]
            out.append((name, seg_fileoff, seg_filesize))
        eoff += ecmdsize
    return out


def member_blob(data: bytes, foff: int):
    """Per-member bytes, excluding the shared __LINKEDIT region.

    Returns (blob, segments_used).
    """
    segs = macho_segments(data, foff)
    parts = []
    for name, soff, ssize in segs:
        if ssize == 0:
            continue
        if name == "__LINKEDIT":
            continue  # shared by every kext -- would contaminate attribution
        if soff + ssize > len(data):
            continue
        parts.append((name, soff, ssize))
    if not parts:
        return b"", []
    blob = b"".join(data[soff:soff + ssize] for _, soff, ssize in parts)
    return blob, parts


STR_RE = re.compile(rb"[\x20-\x7e]{4,}")


def count_pattern(blob: bytes, needles):
    """Single-pass count of every needle occurrence in *blob*.

    One regex alternation per category, matched straight over the raw bytes.
    (The obvious alternative -- extract every string, then loop over the
    needles for each string -- is O(strings x needles) and takes >15 minutes
    on the 78 MB `com.apple.kernel` member.)
    """
    rx = re.compile(b"|".join(re.escape(n.encode()) for n in needles))
    hits = 0
    matched = {}
    for m in rx.finditer(blob):
        s = m.group().decode("ascii", "replace")
        hits += 1
        matched[s] = matched.get(s, 0) + 1
    return hits, ["%s x%d" % (k, v) for k, v in sorted(matched.items())]


def main():
    data = KC.read_bytes()
    entries, filetype = parse_fileset(data)
    print(f"kernelcache: {KC}")
    print(f"filetype={filetype} fileset entries={len(entries)}")

    rows = []
    for idx_e, e in enumerate(entries):
        foff = e["fileoff"]
        if foff == 0 or foff >= len(data):
            continue
        blob, segs = member_blob(data, foff)
        if not blob:
            continue
        print(f"  [{idx_e:3d}/{len(entries)}] {e['name']:<52s} {len(blob):>9,} B", flush=True)

        r_strong, r_strong_hit = count_pattern(blob, REACH_STRONG)
        r_weak, r_weak_hit = count_pattern(blob, REACH_WEAK)
        g_strong, g_strong_hit = count_pattern(blob, GATE_STRONG)
        g_priv, g_priv_hit = count_pattern(blob, GATE_PRIVATE)
        l_alloc, l_alloc_hit = count_pattern(blob, LIFE_ALLOC)
        l_free, l_free_hit = count_pattern(blob, LIFE_FREE)
        l_ref, l_ref_hit = count_pattern(blob, LIFE_REF)
        l_life, l_life_hit = count_pattern(blob, LIFE_LIFECYCLE)
        gpu_hits, gpu_hit = count_pattern(blob, GPU_SIGNALS)

        # Reach score: strong user-client surface dominates; private-entitlement
        # gating subtracts (an unreachable kext is worthless regardless of
        # lifecycle complexity).
        reach = r_strong * 6 + r_weak
        gated = g_priv * 4 + g_strong * 2
        reach_adj = max(0, reach - gated)

        # Life score: capped so a huge kext cannot dominate on size alone.
        life = min(l_alloc, 40) + min(l_free, 60) + min(l_ref, 80) + min(l_life, 120)

        # GPU / surface surface -- relevant to the F1 (IOGPU + Metal
        # cross-object overlap) line of work.

        rows.append({
            "name": e["name"],
            "vmaddr": f"0x{e['vmaddr']:x}",
            "size": len(blob),
            "segments": [s[0] for s in segs],
            "reach_raw": reach,
            "gated": gated,
            "reach_adj": reach_adj,
            "life": life,
            "score": reach_adj * life,
            "has_userclient": r_strong > 0,
            "private_entitlements": g_priv,
            "gpu_hits": gpu_hits,
            "signals": {
                "reach_strong": r_strong_hit,
                "reach_weak": r_weak_hit,
                "gating": g_strong_hit + g_priv_hit,
                "alloc": l_alloc_hit,
                "free": l_free_hit,
                "refcount": l_ref_hit,
                "lifecycle": l_life_hit,
                "gpu": gpu_hit,
            },
        })

    rows.sort(key=lambda r: (-r["score"], -r["reach_adj"], -r["life"]))

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    EV_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "kext-scope.json").write_text(
        json.dumps({"kernelcache": str(KC), "entries": rows}, indent=1),
        encoding="utf-8")

    hdr = "score\treach_adj\tlife\tsize\tname\tvmaddr\tuc\tpriv\tgpu"
    lines = [hdr]
    for r in rows:
        lines.append("%d\t%d\t%d\t%d\t%s\t%s\t%s\t%d\t%d" % (
            r["score"], r["reach_adj"], r["life"], r["size"], r["name"],
            r["vmaddr"], "Y" if r["has_userclient"] else "-",
            r["private_entitlements"], r["gpu_hits"]))
    (OUT_DIR / "kext-scope.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")

    n_uc = sum(1 for r in rows if r["has_userclient"])
    n_priv = sum(1 for r in rows if r["private_entitlements"])
    n_gpu = sum(1 for r in rows if r["gpu_hits"])
    report = [
        "KEXT LIFETIME / UAF SCOPING - iOS 27.0.1 (24A446), iPhone18,1 t8150",
        "=" * 72,
        f"kernelcache : {KC}",
        f"fileset entries parsed : {len(entries)}",
        f"kexts scored : {len(rows)}",
        f"kexts with an IOUserClient surface : {n_uc}",
        f"kexts referencing com.apple.private.* : {n_priv}",
        f"kexts with GPU/IOSurface strings : {n_gpu}",
        "",
        "Scoring (heuristic, not a vulnerability claim):",
        "  reach = 6*strong_userclient_hits + weak_hits - (4*private_ent_hits + 2*gate_hits)",
        "  life  = min(alloc,40)+min(free,60)+min(refcount,80)+min(lifecycle,120)",
        "  score = reach_adj * life",
        "",
        "Method note: kernelcache fileset members are prelinked; segment file",
        "offsets are absolute into the kernelcache and __LINKEDIT is shared by",
        "every kext.  Strings are therefore attributed per member from that",
        "member's own segments only (__LINKEDIT excluded).",
        "",
        "TOP 40 BY SCORE",
        "-" * 72,
        "score\treach\tlife\tsize\tkext",
    ]
    for r in rows[:40]:
        report.append("%6d\t%5d\t%5d\t%8d\t%s" % (
            r["score"], r["reach_adj"], r["life"], r["size"], r["name"]))
    report += ["", "ALL KEXTS WITH AN IOUserClient SURFACE", "-" * 72]
    for r in rows:
        if r["has_userclient"]:
            report.append("%6d\t%5d\t%5d\t%8d\t%s  priv=%d" % (
                r["score"], r["reach_adj"], r["life"], r["size"], r["name"],
                r["private_entitlements"]))
    report += ["", "ALL KEXTS WITH GPU / IOSurface STRINGS", "-" * 72]
    for r in rows:
        if r["gpu_hits"]:
            report.append("%6d\t%5d\t%5d\t%8d\t%s  gpu=%d" % (
                r["score"], r["reach_adj"], r["life"], r["size"], r["name"],
                r["gpu_hits"]))
    (EV_DIR / "kext-scope-27.0.1.txt").write_text("\n".join(report) + "\n", encoding="utf-8")

    print(f"kexts with IOUserClient surface : {n_uc}")
    print(f"kexts with com.apple.private.* : {n_priv}")
    print(f"kexts with GPU/IOSurface strings: {n_gpu}")
    print()
    print("TOP 40:")
    for r in rows[:40]:
        print("%6d\t%5d\t%5d\t%8d\t%s" % (
            r["score"], r["reach_adj"], r["life"], r["size"], r["name"]))
    print()
    print("GPU / IOSurface kexts:")
    for r in rows:
        if r["gpu_hits"]:
            print("%6d\t%5d\t%8d\t%s  gpu=%d" % (
                r["score"], r["reach_adj"], r["size"], r["name"], r["gpu_hits"]))
    print()
    print(f"written: {OUT_DIR / 'kext-scope.tsv'}")
    print(f"written: {EV_DIR / 'kext-scope-27.0.1.txt'}")


if __name__ == "__main__":
    main()
