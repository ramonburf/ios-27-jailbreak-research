#!/usr/bin/env python3
"""Rebuild proper directory tree from 7-Zip's MSI extraction (CM_FP_<mangled>)."""
import os
import shutil
import sys

src = sys.argv[1]
dst = sys.argv[2]

EXTS = ("exe", "bat", "cmd", "dll", "lib", "pyd", "py", "ps1", "sh", "so", "dylib", "json")

# (mangled prefix) -> (real dir, real sub-prefix)
RULES = [
    ("bin.", ("bin", "")),
    ("libexec.", ("libexec", "")),
    ("include.", ("include", "")),
    ("share.", ("share", "")),
    ("lib.site_packages.", ("lib", "site-packages/")),
    ("lib.clang.23.include.", ("lib", "clang/23/include/")),
    ("lib.clang.23.lib.", ("lib", "clang/23/lib/")),
    ("lib.clang.23.share.", ("lib", "clang/23/share/")),
    ("lib.cmake.llvm.", ("lib", "cmake/llvm/")),
    ("lib.llvm-lit.", ("lib", "llvm-lit/")),
    ("lib.libscanbuild.", ("lib", "libscanbuild/")),
    ("lib.LLVM_C.", ("lib", "")),
    ("lib.liblldb.", ("lib", "")),
    ("lib.libclang.", ("lib", "")),
    ("lib.libomp.", ("lib", "")),
    ("lib.LTO.", ("lib", "")),
    ("lib.Remarks.", ("lib", "")),
]


def split_ext(parts):
    """Split trailing extension from a dotted list, if the last part is an ext."""
    if len(parts) > 1 and parts[-1] in EXTS:
        return parts[:-1], parts[-1]
    return parts, None


count = 0
for name in sorted(os.listdir(src)):
    if not name.startswith("CM_FP_"):
        continue
    rel = name[len("CM_FP_"):]
    target = None
    for pref, (real_dir, sub) in RULES:
        if rel.startswith(pref):
            rest = rel[len(pref):]
            parts = rest.split(".")
            parts, ext = split_ext(parts)
            fname = ".".join(parts) if parts else rest
            if ext and not fname.lower().endswith("." + ext):
                fname = fname + "." + ext
            target = os.path.join(dst, real_dir, sub.replace("/", os.sep), fname)
            break
    if target is None:
        target = os.path.join(dst, "misc", rel)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    if os.path.exists(target):
        base, e = os.path.splitext(target)
        target = base + ".dup" + e
    shutil.copy2(os.path.join(src, name), target)
    count += 1

print(f"copied {count} files to {dst}")
