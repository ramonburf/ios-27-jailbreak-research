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

## Correction: chained fixups ARE present

The earlier claim that this kernelcache has no `LC_DYLD_CHAINED_FIXUPS` was wrong — the
check compared the load-command value against `0x34`, but the real constant is
**`0x80000034`** (it carries the `LC_REQ_DYLD` flag). The blob is at file offset
`0x4a80000`, size `0x576`; header version 0, exports trie absent.

A decoder was written (`kc_chain_decode.py`) using the layouts from Apple's
`include/mach-o/fixup-chains.h`. Results:

- 9 segments carry fixups; `__DATA_CONST` (format 8, 0x4000 pages, 414 pages),
  `__DATA_SPTM`, and `__DATA` were walked.
- **20,859 chained pointers resolved**, and the decoded values land inside `__TEXT_EXEC`
  (`0xfffffe0008498000`–`0xfffffe000b448000`) exactly as expected — the decoder is sound.
- Pointer formats present: unauthenticated rebases and **authenticated rebases**
  (`auth=1`, key=IA/IB style). Authenticated entries decode as
  `target = image_base + (raw & 0xFFFFFFFF)`, with `image_base = __TEXT vmaddr`.
- `__DATA_CONST` contains a long run of 2,721 consecutive text pointers at segment offset
  `0x4b0000` (VM `0xfffffe0008284000`), with mixed 8- and 16-byte deltas.

This supersedes the "static confirmation blocked" verdict: static work is now possible
without symbols. The remaining task is locating `socreate` by anchoring disassembly on
string cross-references (e.g. `"soclose: so=%p refcount=0 @%s:%d"` at file `0xa2fbd`),
then reading the allocation call to determine whether `struct socket` comes from a
dedicated zone or a type-isolated region.

Caveat: the `bsd_syscall_table` address carried over from an older symbol dump
(`0xfffffe0007eaee90`) does **not** resolve correctly in this build — the pointers there
decode into `__PRELINK_TEXT`, i.e. the kext region, so that address belongs to a different
kernelcache. Symbol addresses must be re-derived for this build rather than reused.

## Anchored disassembly: the socket close path

The plaintext state of `__TEXT_EXEC` was verified directly rather than assumed:

- sampled windows decode **2048/2048** words into valid AArch64 instructions;
- byte entropy is **6.82 bits/byte**, not the ~8.0 expected for ciphertext;
- real C strings, parseable load commands and resolvable chained fixups all present.

So `kernelcache.release.macho` is the *decompressed, unencrypted* image — no decryption
step exists or is needed. (`kernelcache.release.v53` is the IM4P container it came from.)

A cross-reference search for the `"soclose: so=%p refcount=0 @%s:%d"` panic format string
(file `0xa2fbd`) returns exactly **one** site:

```
0xfffffe000b16b478   adrp x0, #0xfffffe00070a6000      ; file string page
0xfffffe000b16b47c   add  x0, x0, #0xfbd              ; the soclose format string
0xfffffe000b16b480   bl   0xfffffe000b424a74          ; panic/assert helper
```

Around it sit further VERIFY blocks pushing a source-file pointer plus line numbers
(0x462 = 1122, 0x523 = 1315, 0x1cb5 = 7349), and a new function begins immediately after at
`0xfffffe000b16b4cc` (`pacibsp; sub sp, sp, #0x40`). This anchors the socket teardown /
verification region — precisely the code the 27.2 fix modified — and gives a reliable base
for walking to the allocation site. Tools: `tools/opencode-temp/kc_soclose_xref.py`.

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

