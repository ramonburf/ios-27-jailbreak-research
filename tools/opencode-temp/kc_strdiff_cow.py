#!/usr/bin/env python3
"""String diff between iOS 27.0.1 (24A446) and 27.2 (24B119) kernelcaches,
filtered to virtual-memory / CoW / pager vocabulary to locate the CVE-2026-112576 fix."""
import re
from pathlib import Path

BASE = Path("G:/iOS 27.0.1/iOS/firmware")
OLD = BASE / "24A446" / "kernelcache.release.macho"
NEW = BASE / "24B119" / "kernelcache.release.macho"

pat = re.compile(rb'[ -~]{6,}')


def strings_of(p):
    d = p.read_bytes()
    return {m.group().decode('ascii', 'replace') for m in pat.finditer(d)}


print("loading old ...")
old = strings_of(OLD)
print(f"  old strings: {len(old)}")
print("loading new ...")
new = strings_of(NEW)
print(f"  new strings: {len(new)}")

added = new - old
removed = old - new
print(f"added in 27.2: {len(added)}   removed: {len(removed)}")

KW = ('cow', 'co_w', 'copy-on-write', 'copy on write', 'vm_protect', 'vm_fault',
      'vm_map', 'vm_page', 'vm_copy', 'pager', 'memory_object', 'shared_region',
      'vm_object', 'vm_external', 'vm_wire', 'pmap', 'page_table', 'map_violation',
      'vm_reference', 'vm_deallocate', 'vm_inherit', 'vm_remap', 'vm_msync')

hits = sorted(s for s in added if any(k.lower() in s.lower() for k in KW))
print(f"\n=== new in 27.2 matching VM/CoW vocabulary ({len(hits)}) ===")
for s in hits[:60]:
    print("  " + s[:150])

print(f"\n=== removed in 27.2 matching same vocabulary "
      f"({sum(1 for s in removed if any(k.lower() in s.lower() for k in KW))}) ===")
for s in sorted(removed):
    if any(k.lower() in s.lower() for k in KW):
        print("  " + s[:150])
