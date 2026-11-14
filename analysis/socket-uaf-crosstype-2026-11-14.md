# Cross-type socket collision — `--sockmix` reproduces TCP→UDP type confusion on both devices

Date: 2026-11-14
Target: iPhone18,1 / t8150 / iOS 27.0.1 (build 24A446) — **17 Pro `00008150-00095CD93444C01C`**
Secondary: iPhone14,2 / A16 / iOS 27.0 (build 24A5390f) — **13 Pro `00008110-000E095936C1801E`**
Bug: CVE-2026-112514, socket-buffer use-after-free (`uipc_socket2.c`), live on 27.0/27.0.1, fixed in 27.2
Evidence: `analysis/evidence/crosstype-2026-11-14/sockmix_13pro.log`, `…/sockmix_17pro.log`

## What was run

`--sockmix` = precision race (variant E) plus a **cross-type allocation hammer**.

Two changes were made to the carrier for this run:

1. **Datagram oracle.** A `SOCK_DGRAM` listener bound to `127.0.0.1:8090`, plus the ability to
   drain it after each iteration. Nothing in the harness ever calls `send()` on a datagram
   socket, so a datagram arriving there has exactly one possible origin: the kernel pushed
   stale-sender bytes out through a reclaimed dgram socket. This is a *positive* detector —
   one datagram names the collision instead of merely failing to rule one out.
2. **Hammer ordering fix.** In the previous `--sockmix` code the 48-socket TCP spray ran
   *before* the hammer, so fresh TCP sockets took every freed slot before the race window
   opened. The hammer now runs first: while the six senders may still be inside `sendmsg`,
   the harness allocates `socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)` in a tight loop and
   `connect()`s each one to the oracle. Each iteration allocates up to 256 of them; the
   freed slot is taken by whichever allocation lands first.

The TCP side is kept as a control: 48 fresh TCP sockets are connected to the precision
listener afterwards, and any byte they receive beyond the 144-byte contention baseline is
reported separately.

Both devices ran the same build (BUILD_EXIT=0), 2000 iterations each, ~80–96 iterations/s,
and both completed normally (`[+] sockmix: … in 2000 iterations`) — no app crash, no
respring, no reboot.

## Results

| Device | Iterations | Cross-type hits | Datagrams delivered | Bytes delivered |
|---|---|---|---|---|
| 13 Pro (27.0 / 24A5390f) | 2000 | **109** | 335 | 2,744,320 |
| 17 Pro (27.0.1 / 24A446) | 2000 | **4** | 14 | 114,688 |

```
13 Pro: [!] ITER 5 precision/mix: *** CROSS-TYPE HIT: 5 datagram(s)/40960 byte(s) via a reclaimed dgram socket (hammer alloc=239, in flight at close 1/6) ***
13 Pro: [!] ITER 12 precision/mix: *** CROSS-TYPE HIT: 6 datagram(s)/49152 byte(s) via a reclaimed dgram socket (hammer alloc=256, in flight at close 0/6) ***
13 Pro: [+] sockmix: 109 cross-type datagram hit(s), 109 total stale-write hit(s) in 2000 iterations

17 Pro: [!] ITER 188 precision/mix: *** CROSS-TYPE HIT: 1 datagram(s)/8192 byte(s) via a reclaimed dgram socket (hammer alloc=256, in flight at close 5/6) ***
17 Pro: [!] ITER 956 precision/mix: *** CROSS-TYPE HIT: 6 datagram(s)/49152 byte(s) via a reclaimed dgram socket (hammer alloc=13, in flight at close 0/6) ***
17 Pro: [+] sockmix: 4 cross-type datagram hit(s), 4 total stale-write hit(s) in 2000 iterations
```

### Structure of the effect

Every delivered byte count is an exact multiple of **8192**, and the number of datagrams
per hit is an exact multiple of 8192-byte units:

* 13 Pro histogram of datagrams per hit: `{1: 34, 2: 17, 3: 11, 4: 18, 5: 12, 6: 17}`
* 17 Pro histogram: `{1: 2, 6: 2}`

8192 bytes is exactly one sender buffer (`sendLen = 8192`). So each hit delivers **one whole
attacker-chosen message per sender that was still in flight**, emitted as separate UDP
datagrams. The sender buffer is filled with `0x41` bytes.

The control discriminates cleanly: on iterations where the collision fired, the TCP peers
showed `tcpPeerBytes=144` — i.e. exactly the contention baseline and **nothing above it**.
The stale data did *not* reach a TCP socket. On the remaining iterations the same baseline
held, which is expected because those iterations did not fire.

Neither log contains any `odd errno`, `UAF PROBE`, corruption or panic line.

### Crash-log check

Crash reports were pulled from both devices after the runs (`devicectl device copy from
--domain-type systemCrashLogs`). **No `.panic` file exists on either device, and no crash
report newer than 04:15 was produced** during the run windows. Both phones remained
responsive throughout; no data was touched.

## What this proves

1. **The freed `struct socket` slot can be taken by a different protocol subtype.**
   Allocating `SOCK_DGRAM` sockets *during* the free/touch window reliably wins the slot
   away from the sibling TCP allocations that took it in every earlier variant. The freed
   object is reused within the same C type (`struct socket`) but by a different protocol
   family instance.
2. **The in-flight send path then operates on the foreign object.** Each stale sender's
   complete 8192-byte buffer is transmitted as a UDP datagram — the TCP send path walked a
   socket whose protocol state is UDP, and the UDP output routine emitted the attacker's
   bytes.
3. **The destination is attacker-chosen.** The datagram sockets are `connect()`ed by the
   harness, so the same collision delivers attacker bytes to any address the process may
   send to. Content is fully controlled (the sender buffer).

## What this does *not* prove

* It is **not** kernel read/write. No kernel pointer, field offset or object contents were
  controlled; the only values under attacker control are the *payload* and the *destination*.
* No kernel panic, no crash, no observable corruption of the reclaimed object. The collision
  resolved harmlessly into a UDP send every time (143 hits across both devices).
* The mechanism by which the data reaches the datagram socket (append to the reclaimed
  socket's `so_snd` and subsequent protocol output) is inferred from behaviour, not read out
  of the kernelcache. The exact corrupted field is not yet identified.

## How this relates to the earlier cross-zone conclusion

`analysis/socket-uaf-crosszone-2026-11-13.md` concluded that cross-zone reclaim was "ruled
out for this approach": the OOL `mach_msg` spray ran **after** the close, so it competed for
slots too late, and socket-exhaustion page pressure is capped by `RLIMIT_NOFILE`. That
conclusion stands for its own technique.

`--sockmix` wins because it changes two things at once: the hammer runs **inside** the
free/touch window rather than after it, and the competing object is allocated by the same
process in the same zone, so no cross-zone page pressure is needed at all. The prior
`--sockmix` implementation never worked because the TCP spray preceded the hammer and
consumed the slot before the window opened.

## Next steps

1. **Identify the corrupted field.** Diff the 27.0.1 vs 27.2 `sb*`/`sblock`/`sbunlock`
   region (27.2 de-inlined these helpers into 17 new functions) to recover the exact field
   the fix protects; that names what the stale writer touches on the reclaimed object.
2. **Characterise the reclaimed dgram socket.** After a hit, query the hammer-created fds
   (`SO_TYPE`, `SO_SNDBUF`, `SO_ERROR`, `SO_NWRITE`-equivalents) and look for the stale
   bytes as socket state, so the collision becomes visible without relying on transmission.
3. **Test the reverse direction.** Make the victim a datagram socket and hammer TCP
   allocations, so `udp_send` runs on a TCP-owned object (`so_pcb` reinterpretation). This
   is the more dangerous orientation and should be run on the secondary device only.
4. **Decide whether the socket zone is typed.** If `struct socket` comes from a
   `kalloc_type` zone, the collision ceiling is TCP↔UDP; if not, other small objects may
   share the zone and the same hammer technique could force a genuinely foreign type.
