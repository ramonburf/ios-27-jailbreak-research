#!/usr/bin/env python3
"""Whole-kernelcache function-level diff between two iOS 27 kernelcaches.

Goal: locate EVERY function whose mnemonic profile changed, across all MH_FILESET
members, so we can map the 27.2 kernel CVE fixes (several "write kernel memory"
UAFs whose subsystem is still unidentified) to concrete kexts/functions.

Reuses the parsing helpers from kc_iosurface.py.
"""
import sys, json, struct
from pathlib import Path
from collections import Counter

sys.path.insert(0, str(Path(__file__).parent))
# capstone is installed to a G: target dir (keeps C: writes minimal); make the
# script self-contained so it runs without an external PYTHONPATH.
_extra = Path(__file__).resolve().parent.parent / "pylibs"
if _extra.is_dir():
    sys.path.insert(0, str(_extra))
from capstone import Cs, CS_ARCH_ARM64, CS_MODE_ARM
from kc_iosurface import parse_fileset, member_segments, function_starts

A_PATH = sys.argv[1]
B_PATH = sys.argv[2]
OUT = sys.argv[3]

md = Cs(CS_ARCH_ARM64, CS_MODE_ARM)
md.detail = False


def load(kc_path):
    data = Path(kc_path).read_bytes()
    entries, _ = parse_fileset(data)
    out = {}
    for e in entries:
        name = e["name"]
        try:
            segs = member_segments(data, e["fileoff"])
        except Exception:
            continue
        seg = segs.get("__TEXT_EXEC") or segs.get("__TEXT")
        if not seg:
            continue
        base = seg[0]
        text = data[seg[2]:seg[2] + seg[3]]
        try:
            fstarts = function_starts(data, e["fileoff"], e["vmaddr"])
        except Exception:
            continue
        funcs = []
        for i, s in enumerate(fstarts):
            en = fstarts[i + 1] if i + 1 < len(fstarts) else s + 0x40
            off = s - base
            n = en - s
            if off < 0 or off + n > len(text) or n <= 0 or n > 0x10000:
                continue
            hist = Counter()
            try:
                for ins in md.disasm(text[off:off + n], s):
                    hist[ins.mnemonic] += 1
            except Exception:
                continue
            funcs.append({"start": s, "size": n, "hist": hist})
        out[name] = funcs
    return out


print("loading A", A_PATH, flush=True)
A = load(A_PATH)
print("loading B", B_PATH, flush=True)
B = load(B_PATH)

names = sorted(set(A) & set(B))
print("members A=%d B=%d common=%d" % (len(A), len(B), len(names)), flush=True)

results = []
for name in names:
    fa, fb = A[name], B[name]
    if not fa or not fb:
        continue
    # index-pair when counts match (fast path), else best-similarity pairing
    pairs = []
    if len(fa) == len(fb):
        pairs = list(zip(fa, fb))
    else:
        used = set()
        for a in fa:
            best, bs = None, 0.0
            for j, b in enumerate(fb):
                if j in used:
                    continue
                if abs(a["size"] - b["size"]) > max(a["size"], b["size"]) * 0.35 + 8:
                    continue
                keys = set(a["hist"]) | set(b["hist"])
                if not keys:
                    continue
                inter = sum(min(a["hist"][k], b["hist"][k]) for k in keys)
                union = sum(max(a["hist"][k], b["hist"][k]) for k in keys)
                sim = inter / union if union else 0
                if sim > bs:
                    bs, best = sim, j
            if best is not None and bs >= 0.5:
                used.add(best)
                pairs.append((a, fb[best]))
    changed = []
    for a, b in pairs:
        keys = set(a["hist"]) | set(b["hist"])
        delta = {k: b["hist"].get(k, 0) - a["hist"].get(k, 0) for k in keys}
        delta = {k: v for k, v in delta.items() if v}
        if not delta:
            continue
        inter = sum(min(a["hist"][k], b["hist"][k]) for k in keys)
        union = sum(max(a["hist"][k], b["hist"][k]) for k in keys)
        sim = inter / union if union else 0
        # noise floor: pure relocation/recompile keeps sim high and delta tiny
        if sim >= 0.93 and sum(abs(v) for v in delta.values()) <= 2:
            continue
        changed.append({
            "a_addr": a["start"], "b_addr": b["start"],
            "a_size": a["size"], "b_size": b["size"],
            "sim": round(sim, 3),
            "delta": delta,
        })
    if changed:
        results.append({"kext": name, "n_funcs_a": len(fa), "n_funcs_b": len(fb),
                        "n_pairs": len(pairs), "changed": changed})

results.sort(key=lambda r: -len(r["changed"]))
with open(OUT, "w") as fh:
    json.dump(results, fh, indent=1)

print("\n==== SUMMARY ====")
for r in results:
    print("%-55s funcs %d/%d pairs %d changed %d" % (
        r["kext"], r["n_funcs_a"], r["n_funcs_b"], r["n_pairs"], len(r["changed"])))
print("total kexts with changes:", len(results))
