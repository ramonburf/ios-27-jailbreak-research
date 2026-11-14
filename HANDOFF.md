# Current state, blockers and next steps

Last updated 2026-11-14. Read this first if you are picking the work up cold; it supersedes
the earlier status notes. For the background survey of every surface examined, see
`JAILBREAK-PATHS.md` and `analysis/LEAD-ASSESSMENT.md`.

## Goal and scope

A **semi-untethered jailbreak** on iOS 27.0 / 27.0.1. An app-carried kernel exploit leading
to kernel read/write, then a rootless bootstrap, is sufficient — bootrom / LLB /
trampoline work is explicitly out of scope.

The missing gate is a **kernel read/write primitive**. The top candidate is
**CVE-2026-112514**, a socket-buffer use-after-free in `uipc_socket2.c`, live on 27.0/27.0.1
and fixed only in 27.2.

Overall readiness is about 31 %; the socket path itself is about 83 % complete, and as of
2026-11-14 it can force a **cross-protocol (TCP→UDP) type collision** on demand on both
devices (`analysis/socket-uaf-crosstype-2026-11-14.md`).

## Devices used for testing

| Device | OS | Role |
|---|---|---|
| One iPhone 18,1 class device (A19 Pro, t8150) | **27.0.1** (build 24A446) — the target build | Primary |
| One iPhone 14,2 class device (A16) | 27.0 (build 24A5390f) | Secondary / pre-flight check |

Both are healthy, supervised, and used under a no-data-loss rule. A one-character mistake in
a device UDID makes every `usbmux`-based lookup fail with "no device matching udid" while the
device still appears in listings — worth double-checking before debugging anything else.

## Toolchain

- A macOS host with Xcode builds the carrier with `xcodebuild`
  (`-destination generic/platform=iOS -allowProvisioningUpdates`). No custom toolchains,
  no jailbroken host, no paid entitlement is required — a free developer account is enough.
- Deployment is `xcrun devicectl`; the app is installed and launched over USB with
  `--terminate-existing`.
- Crash reports are pulled from the device with `pymobiledevice3 crash pull`. Note the
  subcommand spelling: it is `crash ls`, not `crash list`, and `pull` takes `--udid` /
  `--match`.
- When the analysis machine is separate from the machine the device is attached to, bridge
  `usbmuxd`'s unix socket to TCP (see `README.md`) and point `PYMOBILEDEVICE3_USBMUX` at the
  forwarded port.

Code signing material, bundle identifiers and provisioning details are deliberately kept
out of this repository. Substitute your own.

## Where the code lives

- `carrier/AGXProbe/` — the harness source. `ContentView.swift` is the main entry point and
  holds all socket-UAF race variants.
- The repository copy and the copy on the build machine should be identical; when they have
  diverged in the past, the build machine was authoritative. Sync both ways after edits.
- `carrier/tests/` — headless regression tests for everything that can be checked without
  tapping the screen.

## Socket-UAF status (stage 4)

The precision variant (**E**) wins reliably on hardware: 20 confirmed stale writes into
reallocated sockets, the first appearing around iteration 9, using a peer-delivery oracle as
the detector. Full evidence: `analysis/socket-uaf-stale-write-2026-11-13.md`.

### Carrier modes (launch arguments)

| Argument | Variant |
|---|---|
| `--sockuaf` | A–E round-robin |
| `--sockprec` | E: gated one-shot send per sender + peer-delivery oracle (the winner) |
| `--sockool` | F: cross-zone reclaim with an out-of-line `mach_msg` spray |
| `--sockxz` | G: free a whole socket page block, then OOL spray |
| `--sockgc` | H: batch-free past the zone's page-return delay, then OOL spray |
| `--sockudp` | connected-UDP spray (type confusion rather than peer bytes) |
| `--sockmix` | E + a datagram allocation hammer *inside* the race window, with a UDP datagram oracle (the cross-type variant — see below) |

Variants F/G/H exist and compile but have never been evaluated. `SockUafSpray.c` provides
`sockuaf_ool_spray(size, count, fill)` for them.

## Cross-type collision reproduced on both devices (2026-11-14)

`--sockmix` was instrumented and run on both phones: **13 Pro 109 hits / 335 datagrams /
2,744,320 bytes; 17 Pro 4 hits / 14 datagrams / 114,688 bytes**, every delivered byte count an
exact multiple of 8192 (one sender buffer per in-flight sender). The freed TCP socket slot is
reclaimed by a `SOCK_DGRAM` socket allocated during the window, and the in-flight senders'
complete buffers are transmitted as UDP datagrams to an address the harness chose.

This is a genuine cross-protocol type confusion, but it is **not** kernel read/write: the only
attacker-controlled values are the payload and the destination. No panic on either device.
Full evidence and next steps: `analysis/socket-uaf-crosstype-2026-11-14.md`.

Two implementation details mattered and must be preserved:

1. The hammer must allocate **during** the free/touch window. The old `--sockmix` ran the
   48-socket TCP spray first, which consumed the freed slot before the window opened.
2. The detector must be positive. A datagram arriving at the oracle can only come from the
   reclaimed socket, because nothing in the harness ever sends on a datagram socket.

## The 27.2 fix hunt says this is *not* the CVE-2026-112514 bug (2026-11-14)

Exact function boundaries for the kernel member were recovered from `LC_FUNCTION_STARTS`
(21,793 starts; see `analysis/kernelcache-funcstarts-exact-diff-2026-11-14.md`), then every
function in the socket region was compared against its 27.2 counterpart with relocation- and
line-number-normalised instruction streams. Result:

* `soclose`, `soreceive`, `sosend`, `sosend_list`, `socreate_common`, `sofreelastref`,
  `sblock`/`sbunlock` candidates are **semantically identical** between 24A446 and 24B119.
* The "27.2 de-inlined the `sb*` helpers into 17 new functions" hypothesis is **refuted** —
  there is no hidden inlining shift; the helper set did not change.
* The only semantic changes nearby are the four 32→64-bit length-arithmetic sites in
  `uipc_mbuf2.c` (`m_sum16` validator and chain-walk helper) and a halfword-width change in an
  mbuf-class stats function. Real but unrelated changes exist in `fg_insertuipc` /
  `fg_removeuipc` / `unp_*` (flow control / AF_UNIX).

The reproduced race is therefore **very unlikely to be the bug Apple fixed as
CVE-2026-112514**: that advisory is `AV:N` and local app-thread loopback racing is not. Either
the real fix is elsewhere in the network path, or our stale write is a different (possibly
still-live) defect. The conversion blocker is unchanged either way — no field differential.

### Allocator: `struct socket` is type-isolated

`socreate` allocates through a view-based `kalloc_type`-family call (`0xac42a30`) using a
per-type global view pair. All 3,113 call sites share that shape. Together with the device
results (every freed slot taken by another socket regardless of spray size/volume), cross-type
reclaim of the socket slot is structurally blocked. Stage 4 needs a second primitive above the
heap/type wall, not better grooming of this one.

## New static lead: `uipc_mbuf2.c` length arithmetic (2026-11-14)

A boundary-free comparison against 27.2 found four sites where the mbuf-chain length
validation changed from 32-bit `add`/`cmp` to 64-bit, including the validator that carries the
`"%s: mbuf %p len (%d) < off+len (%d+%d)"` panic message (whose format specifiers also
changed `%d`→`%u`). Proven: the arithmetic changed. Suspected, unproven: that the 32-bit form
is reachable and exploitable as an integer-truncation-to-OOB. No caller has been audited.
Full evidence and method: `analysis/kernelcache-mbuf-len-truncation-2026-11-14.md`.

### Unsolved static question (needed before F/G/H can work)

The exact kernel allocation size of `struct socket` on iOS 27.0.1 — and any associated
zone or type name — has not been determined. The out-of-line spray currently hard-codes
**4096**, which almost certainly does not match the socket allocation class, so F/G/H may be
spraying the wrong size entirely. To resolve it:

1. Locate the iOS 27.0.1 kernelcache (under `firmware/`, or the already-extracted kext tree
   used by `tools/opencode-temp/kc_diff_all.py`), find the socket creation path (`socreate`
   / `so_create`) and read the size argument passed to `kalloc` / `kalloc_type` /
   `kalloc_nova`.
2. Cross-check against a real XNU `struct socket` for arm64e (~600s/2600s era), which is
   roughly 0x180–0x220 bytes — confirm from the binary, do not assume.
3. Also recover the offsets of `so_proto`, `so_pcb`, `so_rcv`, `so_snd` and the defunct /
   usecount flag. Those are needed to shape a fake object once the slot is reclaimed.

A previous attempt at this analysis was interrupted and produced no output;
`analysis/socket-struct-size.md` does not exist yet. Partial work located the arm64e
kernelcache and a working `kalloc` search pattern, plus the kernel slide constant `0x3c0`,
but did not converge on a size.

### The open problem

The freed socket slot is normally reclaimed by another **socket**, so the stale write lands
in socket-shaped fields — a genuine use-after-free write, but not read/write. As of
2026-11-14 the slot *can* also be taken by a different protocol subtype (`SOCK_DGRAM`), but
that collision still only controls the transmitted payload and destination, not any kernel
field.

Getting from here to a controlled primitive requires:

1. Naming the field(s) the stale writer corrupts on the reclaimed object (static: diff the
   27.0.1 vs 27.2 `sb*` region — 27.2 de-inlined those helpers into 17 new functions).
2. Making one of those fields observable/controllable, e.g. a datagram socket whose
   overwritten state can be read back through `getsockopt`, or a `so_proto` / `so_pcb`
   pointer.
3. A leak — KASLR slide plus the heap address of the overlapped object — to shape a fake
   object once a controllable field exists.
4. Proof of one controlled field differential, after which the dangling socket can serve as
   the read/write channel.

## Cross-zone reclaim attempts (2026-11-13)

Two harness bugs were found and fixed: the out-of-line spray hard-coded **4096** bytes when
the socket size class is **832** (now `--spraysize`, default 832), and the solo-mode flags
were swapped (`--sockool` ran the page-free variant and vice versa). Zone-exhaustion
pre-phase and a fill detector were added.

Tested on both devices: variants F (`--sockool`), G (`--sockxz`) and H (`--sockgc`) each ran
255–511 iterations with the race firing (4–6 of 6 senders still in flight at close) but no
cross-zone effect was observed, and the CPU watchdog killed every run after ~100 s.
Full detail and the caveats of the detector: `analysis/socket-uaf-crosszone-2026-11-13.md`.

## Known blocker: the CPU watchdog kills the harness

Every `AGXProbe.cpu_resource` crash report says the same thing:

```
CPU: 90 seconds cpu time over 94 seconds (96% cpu average),
     exceeding limit of 50% cpu over 180 seconds
```

Six persistent sender threads spin at 100 % CPU, so the app is killed after roughly 94
seconds. Any fix must cut average CPU below the threshold **without** widening the race
window — variant E gates on all six senders having entered `sendmsg` before the close, so
the senders must fire simultaneously.

Simply adding `usleep()` to the idle waits does reduce CPU (no kill within ~6 minutes), but
it collapses the race rate: with a 20 µs poll, the six senders wake staggered, the early
ones finish their sends before the last one even enters `sendmsg`, and far fewer are in
flight when the close lands. In testing, hits dropped from 2–6 senders in flight to 1.

The right fix is a blocking primitive that still wakes in microseconds — a
`DispatchSemaphore` or `os_unfair_cond` — rather than polling. Blocked threads cost ~0 %
CPU but wake immediately, preserving the simultaneous-fire behaviour the race depends on.

## Other observations from device logs

- `com.apple.NRD.UpdateBrainService` crashes repeatedly (roughly every two hours). This is
  Apple's own bug: dyld aborts because the staged binary was built for tvOS and launched on
  iOS. It recurs independently of this project. Possibly reportable, low impact.
- Jetsam events name an unrelated third-party chat application as the largest process, with
  reasons `per-process-limit` / `fc-thrashing` / `highwater`. Not caused by this harness.
- No kernel panic and no device reboot occurred in any run.

## Network-surface reachability measured (2026-11-14)

`--rawsock` was built into the carrier and run on **both devices** (identical output): raw
IPv4/IPv6 sockets, `PF_NDRV` and `/dev/bpf*` are all refused with `EPERM`, while
`PF_ROUTE/SOCK_RAW/INET` and `AF_SYSTEM/SOCK_DGRAM/SYSPROTO_CONTROL` **open successfully**.
Consequences: no app-carried packet injection exists, so every network-input lead
(`m_sum16`/`m_adj_sum16`, `inet_cksum`, `nd6_send`, `igmp`, `net_filter_event`) is remote-only;
and `PF_ROUTE` is a newly measured, sandbox-reachable kernel control interface. Full table and
next steps: `analysis/krw-leads/network-surface-reachability-2026-11-14.md`.

## The changed mbuf functions are identified: `m_sum16` / `m_adj_sum16`

The four 32→64-bit sites live in **`m_sum16`** (`0xfffffe000b166da8`) and **`m_adj_sum16`**
(`0xfffffe000b166b5c`), plus the SIMD ones-complement checksum core at
`0xfffffe000ab4b600`. Their callers are input-path checksum routines; several pass a
difference of header fields straight into the length argument, which is how `len` can
underflow into a huge `u_int` and make `off+len` wrap modulo 2^32. Because raw sockets are
denied to apps, the defect is reachable only by a network peer: **remote `AV:N`, not
app-reachable**. Evidence: `analysis/krw-leads/msum16-checksum-callers-2026-11-14.md`.

## CoW guard recovered (2026-11-14)

Exact function boundaries show the "External objects are not implemented for CoW" assertion is
the tail of the fault-path function starting at `0xfffffe000ac86c10`, reached only from
`0xfffffe000ac88dd4` when `[obj+0x75]` bit 1 is set **and** the helper at
`0xfffffe000acbabd8` returns something other than `3`. A generic IOSurface CoW storm is
therefore unlikely to hit it; the helper and the object layout must be identified first.
Details appended to `analysis/krw-leads/CVE-2026-112576-cow.md`.

## PF_ROUTE characterised: read-only from the sandbox (2026-11-14)

`--routesock` ran on the 13 Pro and settled the interface:

* **Reads work.** `RTM_GET` returns real `rt_msghdr` records (`version=5`,
  `errno=0`) with sockaddr arrays; the app can enumerate routes and interfaces.
* **Writes are refused.** `RTM_ADD` and `RTM_DELETE` both return
  `send() == -1, errno = EPERM`. No state mutation is possible.
* **Malformed `sa_len` is rejected** with `EINVAL`; no panic, no partial parse.
* `struct rt_msghdr` on iOS 27 is **0x5c**, not the published 0x54 — the first
  reply sockaddr sits at `0x5c`, confirmed by a loopback query returning
  `127.0.0.1` exactly. Placing sockaddrs at 0x54 silently produces a
  default-route lookup that looks plausible.

Verdict: an information channel only, **not** a path to kernel read/write. The
route.c fix-site lead is closed — statically the changed helper is encode-side
(called only from two notification encoders fed by ifnet/ifa state), and the
device run shows the parser validates lengths before any encoding.
Evidence: `analysis/krw-leads/pfroute-characterisation-2026-11-14.md`.

One open anomaly, unconfirmed: the default-route reply declares
`rtm_msglen = 128` while three advertised sockaddrs would need `0x8c`; the
third entry starts with bytes `13 00 00 00`. Recorded, not claimed.

## Immediate next step

1. **Identify `0xfffffe000acbabd8`** (the CVE-2026-112576 CoW guard helper) and
   the setter of `[obj+0x75]` bit 1. Pure static analysis, explicitly queued in
   HANDOFF; do this before any further CoW device work.
2. **`PF_ROUTE` is now closed as exploit surface** — read-only, writes `EPERM`.
   Do not build more route probes except as an oracle.
3. **The mbuf length-arithmetic lead stays closed** as app-reachable work
   (raw sockets are denied); keep it as a bounty candidate.
4. **Use the exact-diff tooling** (`tools/opencode-temp/kc_fstarts.py`,
   `kc_norm_diff.py`, `kc_align_region.py`) for all future binary comparison.
