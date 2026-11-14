# Exact kernelcache function diffing via `LC_FUNCTION_STARTS` — and what it shows about CVE-2026-112514

Date: 2026-11-14
Images: `firmware/24A446/kernelcache.release.macho` (27.0.1 / 24A446) and
`firmware/24B119/kernelcache.release.macho` (27.2 / 24B119)
Related: `analysis/kernelcache-mbuf-len-truncation-2026-11-14.md`,
`analysis/socket-uaf-crosstype-2026-11-14.md`, `analysis/kernelcache-symbols-2026-11-14.md`

## 1. Correction: `LC_FUNCTION_STARTS` **is** present in the kernel member

`analysis/kernelcache-symbols-2026-11-14.md` states that both builds lack
`LC_FUNCTION_STARTS` (`cmd 0x26`) and therefore "there is no local symbol table" and function
boundaries cannot be recovered without guessing. That is wrong for the **fileset member**
`com.apple.kernel`:

```
member load commands:  cmd 0x2 (count 1), 0x5, 0xb,
                       0x19 (segments, x20), 0x1b,
                       0x26  <-- LC_FUNCTION_STARTS
                       0x2a, 0x32
```

The blob is at file offset `0x4a0c000`, size `0x8ca0`, and decodes to **21,793** function-start
offsets. Mapping them as `__TEXT.vmaddr + delta` puts **21,731** inside the member's
`__TEXT_EXEC` (`0xfffffe000ab44000` + `0x8fc000`), with the last one at
`0xfffffe000b43f330`. Two spot checks confirm the boundaries are real:

* `0xfffffe000b166da8` (the mbuf-chain length validator) is exactly a function start.
* The `socket` syscall export at `0xfffffe000b17b744` sits 8 bytes before a function start.

This supersedes the earlier `pacibsp`-delimited and linear-sweep approaches: the boundaries are
authoritative, not heuristic. The same method works for 24B119 (21,843 starts).

(`LC_SYMTAB` in the same member has `nsyms = 0`, `strsize = 1` — still stripped. Only function
starts survive.)

## 2. Method

With exact boundaries on both sides, functions can be compared semantically instead of by
address. Normalisation applied before comparison:

1. absolute operands `>= 0xfffffe0000000000` → `#A`;
2. branch/call targets inside the function → `L+<offset>`, outside → `E`;
3. any register defined by `adrp` and then used as a memory base → `[reg,#G]` (this removes the
   noise from global-variable offsets, which legitimately shift between builds);
4. `add reg,reg,#imm` where the source is an `adrp` register → `#S` (same reason).

Unchanged functions then compare **exactly equal**, while genuine code changes stand out with no
relocation noise. Verified against the two known-changed mbuf functions (they still diff).

Tooling added to `tools/opencode-temp/`:
`kc_fstarts.py` (loader + `func_refs`), `kc_norm_diff.py`, `kc_align_region.py`,
`kc_pair_for.py`, `kc_annotate_calls.py`, `kc_find_func.py`.

## 3. Result: the BSD socket core did **not** change between 27.0.1 and 27.2

Region `0xb160000`–`0xb180000` (uipc_socket.c / uipc_socket2.c / kpi_socket.c / uipc_usrreq.c):
**249 functions in 24A446, 210 exact-normalized matches.** Of the 6 A-only functions, four are
normalisation artefacts or mispairs (diffs are line numbers only, or a single global-offset load),
and two are the already-known `uipc_mbuf2.c` arithmetic sites.

Directly diffed, all **semantically identical**:

| Function (24A446 → 24B119) | Evidence of identity |
|---|---|
| `soclose` `0xb16aaa4` → `0xb1c08a8` | 650 insns, IDENTICAL |
| `soreceive` `0xb16e728` → `0xb1c452c` | 233 insns, IDENTICAL |
| `sosendcheck`/`sosend` `0xb16cba4` → `0xb1c29a8` | 132 insns, IDENTICAL |
| `sosend_list` `0xb16deb4` → `0xb1c3cb8` | 490 insns, IDENTICAL |
| `socreate_common` `0xb169b14` → `0xb1bf918` | 478 insns, IDENTICAL |
| `sofreelastref` `0xb16768c` → `0xb1bd490` | 332 insns, IDENTICAL |
| sblock/sbunlock candidates `0xb177950`→`0xb1cd754`, `0xb178190`→`0xb1cdf94` | IDENTICAL |

This **refutes** the earlier hypothesis (`PROGRESS.md`, `HANDOFF.md`) that "27.2 de-inlined the
`sb*` helpers into 17 new functions" and that a pair-diff missed the fix that way. The helper set
is unchanged; there is no hidden inlining shift.

The neighbouring region `0xb17a000`–`0xb187000` does contain real changes, but they are in
UNIX-domain / flow-control paths, not the TCP send/close race:

* `fg_insertuipc` `0xb181118` (0xd04) → `0xb1d6f1c` (0xd5c), +0x58
* `fg_removeuipc` `0xb185334` (0x56c) → `0xb1db1cc` (0x5e4), +0x78
* a `_but_wired`-related option handler `0xb184854` (0x6e8) → `0xb1da6d8` (0x6fc), +0x14
* `unp_getlock` / `unp_unlock` minor changes.

None of these touch `so_snd`, `so_pcb`, refcount/defunct handling or the close/send wake path.

### The only semantic changes in the socket/mbuf data path

| Site | 24A446 → 24B119 | Change |
|---|---|---|
| chain-walk helper | `0xb166b5c` → `0xb1bc950` | 3× `cmp w,b.lo` → `add x,cmp x,b.hi` (32→64-bit span math) |
| `m_sum16` validator | `0xb166da8` → `0xb1bcba8` | same 32→64-bit change; panic message `%d`→`%u` |
| mbuf-class stats | `0xb1519ac` → counterpart | 32-bit loads/stores → halfword (`ldrh`/`strh`) |

## 4. What this means for CVE-2026-112514

Apple's iOS 27.2 Kernel section (support.apple.com 149230) lists several distinct UAFs:
`CVE-2026-112576` (CoW), `CVE-2026-65350`/`112679`, `CVE-2026-112517`,
`CVE-2026-112516`, **`CVE-2026-112514`** ("use-after-free ... system termination or corrupt
kernel memory", Marc Newlin / SkySafe, STAR Labs SG, greenbynox), `CVE-2026-84495`/`112474`,
`CVE-2026-112507`, plus a type-confusion (`112606`) and a race (`112501`).

Because every function implicated by our reproduced race is byte-for-byte semantically identical
between the two builds, **our socket-buffer stale-write race is very unlikely to be the bug that
`CVE-2026-112514` fixes**. The advisory also scores it `AV:N` (network-reachable); our trigger is
a local loopback race between app threads (`AV:L`). Two possibilities remain:

1. `112514` is fixed elsewhere in the network input/output path (not yet localised), or
2. our race is a *different*, possibly still-live defect — consistent with the BSD socket core
   being untouched in 27.2, but unproven because neither test device runs 27.2.

Either way the conversion conclusion is unchanged: the stale write lands in a valid reused
`struct socket`, so proto and pcb are consistent and only payload/destination are controlled.
No field differential exists.

## 5. Side finding: `struct socket` comes from a view-based (type-isolated) allocator

`socreate` allocates the socket through `0xfffffe000ac42a30` after loading a per-type global pair:

```
adrp x8, #0x7ea2000 ; ldr x8,[x8,#0xa38] ; ldp x0,x1,[x8]
mov  w2, #4          ; bl 0xac42a30       ; str x0 -> *aso
```

All 3,113 call sites of `0xac42a30` follow the same shape — `adrp/add` to a per-type global,
`ldp x0,x1,[xN]`, `mov w2,#flags`, `bl` — and different types use different globals
(`0xb753680`, `0xb753500`, `0xb7535c0`, …). The callee authenticates a pointer at `[view+0x40]`,
reads a halfword size at `[view+0x34]` and updates per-CPU accounting. This is the
`kalloc_type`-family allocation path.

Combined with the device results (every freed slot reclaimed by another socket regardless of
spray size/volume; cross-zone variants F/G/H always landing in a socket), the evidence says the
freed socket slot is type-isolated: **cross-type reclaim of the slot is structurally blocked.**
Stage 4 conversion therefore needs a second, non-heap primitive, not better grooming of this one.

## 6. Next steps

1. Decide whether to keep pursuing the socket UAF at all, or re-rank the
   VM/IOSurface-backed leads above the type wall. Given §5, further socket grooming is bounded.
2. If continuing, test whether the race survives a local TCP **listener** (network-style trigger)
   rather than loopback app threads — the AV:N description of the real CVE suggests packet-driven
   state, not `sendmsg`.
3. Localise `112514` proper: enumerate changed functions whose refs include netinet/ip_input /
   tcp_input / udp / mbuf-cluster strings and inspect their deltas (the triage list in
   `triage_changed` output already flags `ip_dummynet.c`, `nd6_send.c`, `necp`, `net_filter_event`).
