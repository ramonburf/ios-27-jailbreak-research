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

## Decisive result: the race fires, but the slot is always reclaimed by a socket

The cross-zone variant had no observer, so it was impossible to tell whether the race even
fired there. A peer-delivery observer was added to `sockUafRaceCrossZone`: it connects 48
probe sockets whose peers are already accepted, sends nothing on them, and afterwards drains
the peers. Any byte that arrives is stale-sender data.

Result, both devices, `--sockool`:

```
17 Pro: ITER 54 crosszone: *** STALE WRITE into a socket: 49152 byte(s) ***
        (sprayed 256x832 OOL, peer bytes=49152, senders done=6)
13 Pro: ITER 39 crosszone: *** STALE WRITE into a socket: 40960 byte(s) ***
```

So in this mode the race wins just as reliably as in the precision mode, and the freed slot
is **always** taken by another socket — never by the attacker-controlled out-of-line data.
That rules out the cross-zone reclaim strategy as implemented, and explains the absence of
both fill-hits and kernel panics.

Why: only one socket is freed per iteration, so its zone page stays resident; the zone free
list is LIFO and hands that exact slot straight to the next allocation. Returning a page
requires freeing *every* socket on it at once, with nothing allocating before the spray —
which variants G and H attempt but have not yet been given an observer.

## Variants G and H — same outcome

With the observer in place, `--sockxz` (G, free a 16-socket block) and `--sockgc` (H,
batch-free 700 sockets) were run on the two devices:

```
17 Pro, G: ITER 205 pagefree: *** STALE WRITE into a socket: 49152 byte(s) ***
        (16 freed, sprayed 512x832 OOL, peer bytes=49152)
13 Pro, H: ITER  12 batchgc: *** STALE WRITE into a socket: 49152 byte(s) ***
13 Pro, H: ITER  21 batchgc: *** STALE WRITE into a socket: 49152 byte(s) ***
```

All four reclaim/type-confusion variants now agree: the race fires, and the stale write
lands in a **socket** every time. Freeing 700 sockets at once does not change that either.

Conclusion: with a per-process, per-protocol socket allocation pattern, the freed slot is
always handed straight back to another socket. Cross-zone reclaim is ruled out for this
approach, which explains the zero fill-hits and the absence of any kernel panic across
roughly 2,000 reclaim-variant iterations on two devices.

## Size sweep — the spray size does not matter

`--spraysize=<n>` was fixed to accept the single-token form and both sizes were then run on
both devices (`--sockool --spraysize=4096`, confirmed active via `sprayed 256x4096 OOL`):

```
17 Pro: ITER 10 crosszone: *** STALE WRITE into a socket: 49152 byte(s) ***
13 Pro: ITER 48 crosszone: *** STALE WRITE into a socket: 49152 byte(s) ***
```

At 4096 bytes the outcome is identical to 832. Whatever size the out-of-line payload uses,
the freed slot is still taken by another socket — so the size of the allocation class is not
the limiting factor, and the `sizeof(struct socket)` question no longer blocks this path.

## Variant I (UDP type confusion) — tested, no effect

`--sockudp` ran the full 40,000 iterations on both devices in ~180 s without being killed by
the CPU watchdog — confirming the watchdog cost comes from the out-of-line spraying, not the
race itself. `afterClose(max)=0` and no panic on either device.

Interpretation: the socket zone is almost certainly shared across protocols (one element
size), and because the kernel frees and the in-flight send touches the slot within
microseconds entirely in kernel context, user space cannot interleave a foreign-protocol
allocation into that window. Type confusion by allocator ordering does not look reachable
this way.

## Next steps

Cross-zone reclaim is now ruled out for this approach, so the remaining ideas change shape:

1. **Race a cross-type allocation against the stale write.** The slot is always reused by
   whatever the process allocates next, and the free/touch window is only microseconds wide —
   but that window is concurrent with the senders, not after them. A dedicated thread that
   hammers `socket(AF_INET, SOCK_DGRAM, ...)` continuously *while* the race runs could get a
   datagram socket into the slot during the window, turning the same UAF write into a
   TCP-vs-UDP type confusion instead of a plain socket-to-socket delivery. This is the most
   promising untested idea.
2. **Use the stale write as a primitive in its own right.** It appends attacker-chosen bytes
   to a live socket's send buffer, reliably and repeatedly. Worth measuring exactly which
   fields of the receiving socket are modified (`sb_cc`, `sb_mbcnt`, record pointers) before
   assuming they are useless.
3. **Decode the kernelcache fixup chain** to confirm `sizeof(struct socket)` and read
   `socreate_common`. Still useful for shaping any future fake object, but no longer
   blocking: the size sweep showed the outcome does not depend on it.
4. **Move the whole exploit off the OOL spray.** Variant I showed that without per-iteration
   spraying, runs reach 40,000 iterations and ~180 s without tripping the CPU watchdog —
   plenty of runway once an approach needs many attempts.

