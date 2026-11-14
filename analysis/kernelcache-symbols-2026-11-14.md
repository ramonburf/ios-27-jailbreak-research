# Kernelcache static-analysis status — iOS 27.0.1 (build 24A446, t8150)

Documents what does and does not work when analysing `firmware/24A446/kernelcache.release.macho`,
so this ground is not covered twice.

## Build identification

```
Darwin Kernel Version 27.0.0: Thu Aug 13 21:41:35 PDT 2026;
root:xnu-13432.2.10~2/RELEASE_ARM64_T8150
```

XNU **13432.2.10**. Apple does not publish that tag publicly, so source-level comparison against
matching XNU sources is not possible — no `bsd/sys/socketvar.h` or `uipc_socket.c` exists for
this exact version.

## Segments (from the Mach-O header)

| Segment | vmaddr | vmsize | fileoff |
|---|---|---|---|
| `__TEXT` | `0xfffffe0007004000` | `0x8000` | `0x0` |
| `__PRELINK_TEXT` | `0xfffffe000700c000` | `0xdc8000` | `0x8000` |
| `__DATA_CONST` | `0xfffffe0007dd4000` | `0x678000` | `0xdd0000` |
| `__DATA_SPTM` | `0xfffffe000844c000` | `0x4c000` | `0x1448000` |
| `__TEXT_EXEC` | `0xfffffe0008498000` | `0x2fb0000` | `0x1494000` |
| `__TEXT_BOOT_EXEC` | `0xfffffe000b448000` | `0x8000` | `0x4444000` |
| `__PRELINK_INFO` | `0xfffffe000b450000` | `0x26c000` | `0x444c000` |
| `__DATA` | `0xfffffe000b6bc000` | `0x308000` | `0x46b8000` |
| `__LINKEDIT` | `0xfffffe000b9c4000` | `0xc4000` | `0x49c0000` |

File size 78,135,296 bytes. A raw string scan works fine (`strings` is unavailable in git-bash;
use a Python `[ -~]{4,}` scan).

## What does NOT work

- **No `LC_SYMTAB`** — the kernel image is fully stripped. There is no local symbol table to
  name `socreate`, `sofree`, `sblock`, or any BSD networking function.
- **No `LC_DYLD_CHAINED_FIXUPS`** (cmd `0x34`) — despite pointers being obfuscated, there is no
  chained-fixups blob to decode. So the planned route "decode the fixup chain → read
  `bsd_syscall_table` → find the `socket` handler → disassemble `socreate`" is unavailable in
  its current form.
- The exported-symbol dump (`kernelcache.release.macho.symbols.json`, 14,216 entries) contains
  only dynamic-export names — `bsd_syscall_table`, `mach_trap_table`, vtables. It has no
  socket internals.
- Raw quadwords read at guessed `struct sysent` offsets do not resolve to sensible VAs, so the
  syscall-table entry layout cannot be inferred without disassembly anchors.

## What IS usable

- **String scanning.** Distinctive C strings survive and localise code: e.g.
  `"soclose: so=%p refcount=0 @%s:%d"` at file offset `0xa2fbd`, and the source path
  `.../Sources/xnu/bsd/kern/uipc_proto.c` at `0xa2c00`.
- **String cross-references.** An `adrp`/`add` pair referencing a known string VA identifies
  the referencing function; disassembly from there is anchored and reliable. This is the viable
  (but labour-intensive) route to `soclose`-adjacent code.
- **One candidate zone name.** Exactly one standalone `"socket"` string exists (offset
  `0xa2cc2`) — but it sits directly among socket **sysctl** names (`socket_debug`,
  `sosend_assert_panic`, `somaxconn`, `sosendminchain`, …) in `uipc_proto.c`, so it is almost
  certainly part of the sysctl tree, **not** proof of a dedicated `socket` zone.

## Open question this was meant to settle

Whether `struct socket` comes from a dedicated zone or a type-isolated `kalloc_type` region.
That determines whether cross-zone reclaim is merely hard or structurally impossible. It is
**still unresolved**: the reference exploit asserts "not in kalloc_type framework" without
binary evidence, and our own device results (stale writes always landing in another socket,
regardless of spray size or batch-free volume) are consistent with either explanation.

## Zone-page probe (`--zoneprobe`) — first result

An A/B footprint experiment was added to settle the isolation question without symbols:
hold 2048 sockets, free them wholesale, then measure how much of a following out-of-line
spray's cost is absorbed.

```
17 Pro: arm A (no sockets freed) sprayed 1024x832 -> delta 208 KB
        held+freed 2048 sockets             -> reclaimed 192 KB
        arm B (after socket free)           -> delta 496 KB
13 Pro: arm A                              -> delta 112 KB
        held+freed 2048 sockets             -> reclaimed 192 KB
        arm B                              -> delta 432 KB
```

Two findings:

1. **Freeing 2048 sockets reclaims almost nothing (~192 KB).** The socket zone hoards its
   pages rather than returning them, which is normal XNU zone behaviour under no sustained
   pressure. This is a direct explanation for why every "exhaust then free" attempt failed:
   page return needs sustained allocation pressure well beyond the zone's resident set, and
   zone GC is lazy. Cross-zone reclaim was never going to happen in these runs.
2. **The post-free delta is larger, not smaller**, on both devices (2–4x). If freed socket
   pages were being consumed by the out-of-line allocations, the post-free delta would be
   *smaller* than the control. It is not, so the spray is not reusing freed socket memory.

Caveat: the probe is confounded — `sockuaf_ool_spray` leaks its ports between arms, so arm B
runs on top of arm A's still-resident messages; and a 1024×832 spray costs only ~112–208 KB,
implying lazy or partial copying by the kernel. So this is evidence against cross-zone reuse,
not proof of type isolation either way.

To settle it cleanly the probe needs: fresh process per arm (no leaked state), larger sprays,
and repeated trials. Even then, footprint granularity and the kernel's lazy copying make it a
weak instrument; the reliable path remains static analysis with proper symbol anchors.

