# Kernel mbuf-chain length validation recovered from 27.0.1

Part of the sweep for assertions Apple removed between 24A446 and 24B119
(`analysis/krw-leads/CVE-2026-112576-cow.md` records the CoW case from the same sweep).

## String

```
"%s: mbuf %p len (%d) < off+len (%d+%d) @%s:%d"
```

Present in 27.0.1 at file offset `0xa2aa6` (VM `0xfffffe00070a6aa6`), attributed in the
string table to **`uipc_mbuf2.c`** (nearest source-file string), and to `ip6_input.c` for a
second occurrence. It is absent from 27.2.

## References

Found with the bitmask ADRP+ADD scanner (`tools/opencode-temp/kc_mbuf2_xref.py`, adapted from
`kc_cow_xref.py`; capstone linear sweeps desynchronise on this image and miss references):

| reference | role |
|---|---|
| `0xfffffe000b166d80` | panic block in a tail path |
| `0xfffffe000b166e24` | panic block in the main body |

Both sit in `__TEXT_EXEC` around `0xfffffe000b166xxx` — the same neighbourhood as the
`soclose` panic references (`0xfffffe000b16b478`) mapped earlier, i.e. the socket/mbuf core.

## Recovered logic

The enclosing function begins at `0xfffffe000b166da8`:

```
mov   x8, x1                 ; x8 = requested offset
mov   w9, #0                 ; accumulator
mov   x10, x0                ; x10 = mbuf chain head
cbz   x10, +0x28             ; empty chain skips the walk
loop:
  ldr   w11, [x10, #0x18]    ; m_len
  add   w9, w11, w9          ; total += m_len
  ldr   x10, [x10]           ; m_next
  cbnz  x10, loop
add   w10, w2, w8            ; w10 = requested length + offset
cmp   w9, w10                ; total chain length vs requested span
```

On failure the two sites push line `0x4ec` (1260) with file string at page+`0xad4` and the
message, then call the panic helper `0xfffffe000b424a74`. On success the function returns a
value masked with `0xffff`.

### Structural payoff

This confirms `struct mbuf` field offsets on this build without needing a symbol table:

| field | offset |
|---|---|
| `m_next` | `0x00` |
| `m_len` | `0x18` |

Useful for any further work on the socket-UAF primitive, which manipulates mbuf chains placed
inside sockets.

## Status

The check is a *defensive* validation, not obviously the vulnerability itself. The fact that
its message disappears in 27.2 may mean the validation moved or was replaced rather than
removed. Whether any reachable path performs an equivalent copy *without* this check is the
open question — and is the reason the string was pulled from the removal sweep in the first
place.
