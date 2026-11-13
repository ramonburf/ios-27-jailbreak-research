# Socket UAF — stale write confirmed on 27.0.1 (2026-11-13 ~13:20)

Target: iPhone 17 Pro, iPhone18,1, iOS 27.0.1 (24A446). Carrier AGXProbe `--sockuaf`.

## Result

**20 confirmed stale kernel writes** into freshly reallocated sockets, starting at iteration 9
and continuing every few iterations (9, 14, 19, 29, 34, 44 …). Payload 8 KiB / 16 KiB / 24 KiB.
The run was stopped by an unrelated build replacement at 20 hits, not by a failure.

Each hit means: a sender entered `sendmsg()` on socket A, `close(A)` completed and freed the
`struct socket`, the slot was reallocated to a new socket B, and the in-flight syscall then
wrote A's queued data into B. That is a kernel use-after-free **write**, not just a read.

## Why the oracle is decisive

The five hammer variants alone only produced ambiguous "odd errno" and `F_GETFD` probes: a
sender can observe a freed fd through the fd table for many reasons. The precision variant (E)
removes the ambiguity:

1. Dedicated listener on `127.0.0.1:8089`; accepted peers are held and never read.
2. Spray sockets are freshly created **and connected to that listener**, never sent on.
3. Six senders park on a gate, then each fires exactly one 8 KiB `sendmsg` with 8 iovecs.
4. The close is released only after all six senders have crossed into the syscall
   (`st.entered == 6`), so no sender can still be doing an fd lookup.
5. The freed slot is refilled immediately with 48 connected spray sockets.
6. Any byte arriving at a spray peer can only have come from a stale sender.

`doneAtClose` in the log records how many senders were provably in flight at close (2–6/6 in
the observed hits).

## Harness fixes that made this reachable

| Problem | Fix |
|---|---|
| Fatal SIGPIPE on iter 0 | `signal(SIGPIPE, SIG_IGN)` |
| `0x8BADF00D` scene-create watchdog kill at 20 s (the old "SIGKILL after N iters") | whole loop moved off the MainActor into `Task.detached`, background logging via `emitBg` |
| ~2.7 threads per iteration | six persistent sender threads + one closer, created once, spinning on a shared `Int32` word array |
| Close landing after the senders already returned | gate + `entered` counter: close fires while all senders are in-kernel |
| Double-close of a reused fd number | CAS on `phase 2 → 3`, exactly one closer |
| Weak detection | peer-delivery oracle (above); `F_GETFD` probe kept as a secondary signal |

Run rate ~100–200 iterations/s, 145 M+ sends per run, fd count flat, footprint stable.

## Log signature

```
[!] ITER 9 precision: *** STALE WRITE: 8192 byte(s) delivered into a reallocated socket (sends in flight at close: 4/6) ***
...
[+] socket UAF: 20 confirmed hit(s) — stale write primitive
```

Full log on the Mac: `/tmp/appdata/reach.log`.

## What this is and is not

Is: a reliable, on-demand UAF write into a kernel `struct socket` sized slot in the socket zone.

Is not yet: controlled kernel R/W. The reallocator is another socket, so the overwritten fields
are socket fields with socket-shaped values. To escalate:

1. Reclaim the freed slot with **attacker-influenced** data rather than a socket: cross-zone
   page exhaustion → `mach_msg` OOL spray, or a socket whose overwritten fields are observable
   (`so_proto`, `so_pcb`, `so_usecount`).
2. Add a leak (KASLR slide + heap address of the overlapped object) to build a fake `so_proto`.
3. Verify with a controlled field differential, then use the dangling socket as the R/W channel.

## Notes

- No kernel panic or device reboot in any run. The write is into valid reused memory.
- The socket zone is not in the `kalloc_type` type-isolation framework, which is why this path
  survived when the IOKit paths did not.
- `SO_NWRITE` does not exist on iOS (`ENOPROTOOPT`); `TCP_CONNECTION_INFO` works but loopback
  ACKs drain the send queue, so it is not a good standalone oracle.
