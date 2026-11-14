# `uipc_mbuf2.c`: mbuf-chain length arithmetic changed from 32-bit to 64-bit in 27.2

Date: 2026-11-14
Images: `firmware/24A446/kernelcache.release.macho` (iOS 27.0.1, build 24A446) and
`firmware/24B119/kernelcache.release.macho` (iOS 27.2, build 24B119)
Related: `analysis/kernelcache-mbuf-validation-2026-11-14.md` (which recovered the
validator's logic), `analysis/krw-leads/removed-messages-2026-11-14.md` (the removal sweep
that flagged this string family)

## How the two builds were aligned

No function metadata exists in either image, so the comparison is boundary-free and driven by
string cross-references:

1. `uipc_mbuf2.c` appears twice per image in `__PRELINK_TEXT`. The second copy is referenced
   by code; there are **11 ADRP+ADD references** to it in each build.
2. The two reference lists correspond one-to-one in order. Their address deltas are almost
   constant, which means the whole region is shifted uniformly — i.e. it is otherwise
   byte-identical, and any deviation in the delta localises a code change exactly.

| # | 24A446 ref | 24B119 ref | delta |
|---|---|---|---|
| 1 | `0xfffffe000b165c40` | `0xfffffe000b1bba34` | `+0x55df4` |
| 2 | `0xfffffe000b165df0` | `0xfffffe000b1bbbe4` | `+0x55df4` |
| 3 | `0xfffffe000b165ee8` | `0xfffffe000b1bbcdc` | `+0x55df4` |
| 4 | `0xfffffe000b16636c` | `0xfffffe000b1bc160` | `+0x55df4` |
| 5 | `0xfffffe000b166484` | `0xfffffe000b1bc278` | `+0x55df4` |
| 6 | `0xfffffe000b166604` | `0xfffffe000b1bc3f8` | `+0x55df4` |
| 7 | `0xfffffe000b166d10` | `0xfffffe000b1bcb10` | **`+0x55e00`** (+12) |
| 8 | `0xfffffe000b166d40` | `0xfffffe000b1bcb40` | `+0x55e00` |
| 9 | `0xfffffe000b166d60` | `0xfffffe000b1bcb60` | `+0x55e00` |
| 10 | `0xfffffe000b166d94` | `0xfffffe000b1bcb94` | `+0x55e00` |
| 11 | `0xfffffe000b166e08` | `0xfffffe000b1bcc0c` | **`+0x55e04`** (+4) |

Between refs 1–6 the delta never moves: those functions are unchanged apart from relocations.
The delta grows by **12 bytes (3 instructions)** between ref 6 and ref 7, and by **4 bytes
(1 instruction)** between ref 10 and ref 11. Mnemonic-level alignment of each interval
confirms nothing else changed anywhere in the span.

## The four changed sites

All four are the same idiom: a 32-bit `add`/`cmp` pair on `w` registers becomes a 64-bit
`add`/`cmp` pair, with the branch sense adjusted to match.

### Sites 1–3 — the helper at `0xfffffe000b166b5c` / `0xfffffe000b1bc950`

```
site 1   24A446 0xfffffe000b166bb4        24B119 0xfffffe000b1bc9a8
         cmp  w8, w21                     add  x9, x1, w2, uxtw
         b.lo <fail>                      cmp  x9, w8, uxtw
                                           b.hi <fail>

site 2   24A446 0xfffffe000b166bf8        24B119 0xfffffe000b1bc9f0
         cmp  w8, w2                      add  x9, x1, w21, uxtw
         b.lo <fail>                      cmp  x9, w8, uxtw
                                           b.hi <fail>

site 3   24A446 0xfffffe000b166c40        24B119 0xfffffe000b1bca3c
         cmp  w8, w24                     add  x9, x22, w21, uxtw
         b.lo <fail>                      cmp  x9, w8, uxtw
                                           b.hi <fail>
```

Each is preceded by a chain walk that sums `m_len` (`ldr w10,[x9,#0x18]; add w8,w10,w8;
ldr x9,[x9]`) into the 32-bit accumulator `w8`, i.e. the *sum of the mbuf chain length*.

### Site 4 — the validator at `0xfffffe000b166da8` / `0xfffffe000b1bcba8`

This is the function whose failure path carries the `"%s: mbuf %p len (%d) < off+len
(%d+%d) @%s:%d"` panic message.

```
24A446 0xfffffe000b166dd8                 24B119 0xfffffe000b1bcbd8
add  w10, w2, w8                          mov  w10, w2
cmp  w9, w10                              add  x10, x10, w8, uxtw
b.lo <panic>                              cmp  x10, w9, uxtw
                                          b.hi <panic>
```

The panic message fragments also changed format specifiers between the builds:

| build | fragment at | text |
|---|---|---|
| 24A446 | `0xfffffe00070a6abd` | `off+len (%d+%d) @%s:%d` |
| 24B119 | `0xfffffe00070a74db` | `off+len (%u+%u) @%s:%d` |

The `%d` → `%u` change is corroborating evidence that Apple treated the compared quantities
as unsigned and widened them, rather than merely reshuffling the code.

## What is proven

* Between 27.0.1 and 27.2 the mbuf-chain length validation in `uipc_mbuf2.c` was rewritten so
  that the requested span is computed and compared in **64 bits** instead of **32 bits**.
* Four sites changed; the rest of the file's code is mnemonically identical.
* The panic message that reports a too-short chain changed its conversion specifiers from
  signed to unsigned.

## What is suspected, not proven

* The 27.0.1 form is exploitable. The mechanism would be an integer-truncation weakness: a
  caller-supplied offset/length whose `off + len` exceeds 32 bits wraps to a small value, the
  validator accepts it, and the subsequent copy walks past the end of the mbuf chain. **No
  caller has been audited** to establish that any path can deliver such a value without an
  earlier bound.
* It is *not* established that this is the fix for CVE-2026-112514. That CVE is described as a
  use-after-free reached over the network, whereas this change is arithmetic hardening. The
  two may be unrelated; the socket-buffer UAF we are racing is a different defect in a
  different file (`uipc_socket2.c`).
* Reachability from a sandboxed app is unmeasured.

## Why it matters anyway

It is a **confirmed fix site** in the socket/mbuf data path — the same code that our
cross-type collision drives — obtained by a rebase-immune method that can be applied to any
other function. It is a concrete candidate for an Apple Security Bounty report, and a
concrete place to look for a *second* primitive while the UAF conversion is worked.

## Next steps

1. Recover the signatures of the two functions and enumerate their callers (start from the
   chain-walk helper at `0xfffffe000b166b5c`; it is called via the stub at
   `0xfffffe000ab4b600` in 24A446 / `0xfffffe000ab9b600` in 24B119).
2. For each caller, determine whether `off`/`len` can exceed `0xffffffff` or be negative when
   truncated to 32 bits. Socket read/write paths are the obvious candidates.
3. Build a device probe that supplies a large `off`/`len` through the socket API on both
   devices and watches for the panic message or an out-of-bounds effect. Run on the secondary
   device first.
