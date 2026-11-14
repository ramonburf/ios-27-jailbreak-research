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

## Immediate next step

Convert the cross-type collision into a controlled primitive. Concretely:

1. Diff the 27.0.1 vs 27.2 socket-buffer helpers (`sblock` / `sbunlock` and their callers) to
   name the field the stale writer corrupts on the reclaimed object.
2. Extend `--sockmix` to read back the state of the hammer-created datagram sockets after a
   hit, so the corrupted field becomes observable without relying on transmission.
3. Only then look for a leak (KASLR slide + heap address) to shape a fake object.

The `struct socket` allocation size question is no longer blocking: the cross-zone sweep
showed the outcome does not depend on it, and the cross-type variant wins without any
spray-size tuning.
