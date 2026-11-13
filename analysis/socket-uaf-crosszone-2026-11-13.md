# Cross-zone reclaim attempts — 2026-11-13

Status of variants F/G/H (reclaim the freed `struct socket` slot with attacker bytes
instead of another socket) after fixing two harness bugs and adding a detector.

## Two real harness bugs found and fixed

1. **Wrong spray size.** Variants F/G/H hard-coded a 4096-byte out-of-line `mach_msg`
   payload. The reference exploit for this bug uses **832 bytes**, which is the size class
   of `struct socket` on arm64e iOS 27. Spraying 4096 meant the attacker data was being
   allocated in an entirely different size class, so it could never compete for a freed
   socket slot. The size is now configurable (`--spraysize=<bytes>`, default 832).

2. **Solo-mode flags were swapped.** `--sockool` selected variant G (page-free block) and
   `--sockxz` selected variant F (cross-zone). Any earlier evaluation of those two modes
   was testing the wrong code path. Mapping is now: `--sockool`→F (r=5),
   `--sockxz`→G (r=6), `--sockgc`→H (r=7).

## New instrumentation

- **Zone-exhaustion pre-phase** for the reclaim variants: raises the fd limit, then holds
   up to 4096 sockets so the socket zone must grow; 64 held sockets are closed every
   second iteration to push pages back to the page allocator.
- **Fill detector** (`sockUafFillProbe`): after spraying, allocates eight fresh sockets and
   reads `SO_SNDBUF` / `SO_RCVBUF`, looking for the 0x41 fill pattern.

## Results — both devices

Tested on the iPhone 18,1 target device (iOS 27.0.1) and the iPhone 14,2 secondary device,
same build of the carrier:

| Variant | Argument | Iterations per run | Race participation | Observable effect |
|---|---|---|---|---|
| F cross-zone | `--sockool` | 511 | at close 3–6/6 senders | none |
| G page-free | `--sockxz` (previously run as `--sockool`) | 255 | at close 3–6/6 senders | none |
| H batch GC | `--sockgc` | 255 | at close 3–6/6 senders | none |

Every run ended the same way: the iOS CPU watchdog killed the app with signal 9 after
roughly 100 seconds (~90 s CPU per 180 s window). Both devices behaved identically — the
race itself fires reliably (most iterations have 4–6 of 6 senders still in flight when the
close lands), but no cross-zone effect was detected.

The zone-exhaustion pre-phase works as intended (`zone exhaust: holding 3963 sockets`), and
the 832-byte spray is confirmed active (`sprayed 256x832 OOL`). Zero fill-hits.

## Why the detector may be blind

Reading `SO_SNDBUF`/`SO_RCVBUF` after allocation is a weak test: `socreate_common`
initialises most socket fields (including both buffer highs) immediately after the
allocation, so even if a socket lands in a sprayed page the kernel overwrites the very
fields we read. Absence of hits therefore does not prove the reclaim failed — it proves
only that this detector cannot see it.

A stronger detector would either:
- fill the spray with a shape that leaves a field uninitialised and observable, or
- use the stale write itself as the probe (peer delivery already works in variant E), or
- look for a kernel panic when a socket's `so_proto` is replaced by fill bytes — none
  occurred across ~1,500 total iterations.

## Next steps

1. Determine `sizeof(struct socket)` from the binary rather than assuming 832 (static
   analysis of the kernelcache is blocked by chained-fixup pointer encoding; needs the
   fixup chain decoded).
2. Replace the fill detector with one that survives field initialisation.
3. Once a reclaim is demonstrably happening, shape the fill as a fake `so_proto` using the
   known offsets of `so_proto`, `so_pcb`, `so_rcv`, `so_snd`.
