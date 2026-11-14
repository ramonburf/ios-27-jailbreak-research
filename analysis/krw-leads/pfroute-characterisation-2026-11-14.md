# PF_ROUTE characterised from the app sandbox (`--routesock`, 2026-11-14)

Device run on the **secondary** unit (iPhone 13 Pro, iPhone14,2, iOS 27.0 build
24A5390f), carrier `com.bench27.agxprobe`. Probe added as
`route_socket_probe()` in `carrier/AGXProbe/SockUafSpray.c`
(launch argument `--routesock`; dispatch in `ContentView.swift`).
Raw console capture: `analysis/evidence/pfroute-2026-11-14/routesock-13pro.log`.

## Why

`--rawsock` had measured that `socket(PF_ROUTE, SOCK_RAW, AF_INET)` **opens**
from an unsigned sandboxed app while every raw-packet path is `EPERM`
(`analysis/krw-leads/network-surface-reachability-2026-11-14.md`). That made
`PF_ROUTE` the only newly measured, sandbox-reachable kernel control interface,
and the immediate next step was to characterise it: does it answer reads, and
can it modify state?

The probe is read-only by construction: stages are RTM_GET / RTM_IFINFO, or
requests designed to fail inside the parser. The one write test uses
TEST-NET-3 (`198.51.100.0/24`) with an immediate RTM_DELETE and a confirming
RTM_GET; no live route is ever installed.

## Results (verbatim, abridged)

```
[*] routesock layout: sizeof(hdr)=92 version_off=2 addrs_off=12
[+] PF_ROUTE/SOCK_RAW/AF_INET -> fd=135 errno=0
[*] routesock S0 unsolicited read -> 0 bytes
[*] routesock S1 GET @0x54 dst=192.0.2.1 msglen=100 -> 100 errno=0
[*] routesock S1 reply -> 128 bytes
S1 hdr: msglen=128 version=5 type=4 index=19 flags=0x40010843 addrs=0x7 pid=7748 seq=1 errno=0
S1 sa0 @0x5c len=16 family=2     (dst 0.0.0.0)
S1 sa1 @0x6c len=16 family=2     (gateway 192.168.1.1)
S1 sa2 @0x7c len=0 family=0
[*] routesock S2 GET @0x5c dst=192.0.2.1 msglen=108 -> 108 errno=0
S2 hdr: msglen=128 version=5 type=4 index=19 flags=0x40010843 addrs=0x7 pid=7748 seq=2 errno=0
[*] routesock S3 GET dst=127.0.0.1 msglen=108 -> 108 errno=0
S3 hdr: msglen=124 version=5 type=4 index=1 flags=0x200045 addrs=0x3 pid=7748 seq=3 errno=0
S3 sa0 @0x5c len=16 family=2     (dst 127.0.0.1)
S3 sa1 @0x6c len=16 family=2     (gateway 127.0.0.1)
[*] routesock S4 GET sa_len=0xff msglen=108 -> -1 errno=22      (EINVAL)
[*] routesock S4 reply -> 0 bytes
[*] routesock S5 en0 IPv4 = 192.168.1.48
[*] routesock S5 RTM_ADD 198.51.100.0/24 msglen=140 -> -1 errno=1   (EPERM)
[*] routesock S5 reply -> 0 bytes
[*] routesock S6 GET 198.51.100.0 -> 108 errno=0
S6 hdr: ... addrs=0x7 ... errno=0                                  (default route)
[*] routesock S7 RTM_DELETE 198.51.100.0/24 msglen=124 -> -1 errno=1  (EPERM)
[*] routesock S8 GET 198.51.100.0 after delete -> 108 errno=0
S8 hdr: ... addrs=0x7 ... errno=0
[*] routesock done: stages(failures) = 0 0 0 0 1 1 0 1 0, first_err=0
```

No crash report appeared on either device. The 13 Pro still lists exactly one
`.ips` (the pre-existing `JetsamEvent-2026-11-14-093502.ips`); no
`AGXProbe.*` report and no kernel panic.

## What this proves

1. **`PF_ROUTE` is bidirectional for reads.** An unsigned sandboxed app can
   send RTM_GET and receive fully-formed route records — real `rt_msghdr`
   (`version=5`), real interface indices (lo0 = 1, en0 = 19), real sockaddr
   arrays, and `errno=0`. The socket is a genuine kernel information channel.
2. **Route modification is denied.** `RTM_ADD` and `RTM_DELETE` both return
   `send() == -1, errno = EPERM` from the app sandbox. Writes into the routing
   subsystem are closed, so `PF_ROUTE` cannot be used to alter kernel state.
3. **The input parser validates sockaddr lengths.** A deliberately over-long
   `sa_len` (0xff, with a truthful `rtm_msglen`) is refused with `EINVAL` at the
   syscall — no panic, no partial parse. Combined with the static finding below,
   the 27.0.1 route.c `VERIFY` site is confirmed unreachable from message
   contents.
4. **`struct rt_msghdr` on iOS 27 is 0x5c bytes, not the published 0x54.**
   The reply's first sockaddr sits at `0x5c`; a loopback query returns
   `sa0 @0x5c = 127.0.0.1` exactly as requested, which pins the header size
   independently of any documentation. The published XNU `struct rt_metrics`
   (12 × u32 = 48 bytes) gives 0x54; iOS 27 carries two more metric words.
   Consequence for any future work here: placing sockaddrs at 0x54 silently
   yields a default-route lookup rather than the queried destination — a wrong
   result that looks plausible (see S1 vs S3).

## Observation, unconfirmed

For the default-route reply (`addrs = 0x7`, i.e. DST|GATEWAY|NETMASK) the
declared `rtm_msglen` is 128 = `0x80`, but three 16-byte sockaddrs after a
0x5c header would need `0x8c` = 140. The third entry begins at `0x7c` with
bytes `13 00 00 00`, which is not a valid `sockaddr_in`. Either the kernel
under-computes the message length for replies carrying a netmask, or the third
entry is encoded differently. Not reproduced on the loopback reply (which needs
only two addresses). Recorded as an open anomaly, **not** claimed as a bug.

## Static corroboration: the changed route.c function is encode-side only

Independent of the device run, the one localised 27.0.1→27.2 change in
`bsd/net/route.c` (`0xfffffe000ae662ec` → `0xfffffe000aeb9588`) is reached only
from two functions:

| callee | call sites | what it builds |
|---|---|---|
| `0xfffffe000ae72138` | `0xae7226c`, `0xae72298` | writes `rtm_msglen` (u16 @+0), `rtm_version = 5` (@+2), `rtm_type` (@+3), then copies sockaddrs |
| `0xfffffe000ae7507c` | `0xae751f4` | same encoding shape |

Their own callers pass interface-message type constants (`0xe` = RTM_IFINFO,
`0x11`, `0x12`, `0x14`, `0x15`) and stack-built sockaddr arrays whose elements
are loaded from kernel-owned interface state
(`ldr x27,[x28,#0xa0]` → `ldr x8,[x27,#0x18]`, i.e. `ifnet`/`ifa` fields).
Both source and destination of the compared `sdl_alen` therefore derive from
kernel interface tables, not from message bytes.

The device run agrees: malformed `sa_len` is rejected with `EINVAL` before any
encoding, and no input could induce the `VERIFY`.

## Verdict

`PF_ROUTE` is a **read-only** kernel interface from the app sandbox. It offers
route/interface *information* (useful as an oracle or for KASLR-adjacent
reasoning) but no state mutation, so it is **not** a path to kernel read/write
and should not absorb further exploit development. The route.c fix-site lead is
closed. Remaining value: the reply decoder above can be reused as a cheap,
deterministic kernel-behaviour oracle.

Primary-device note: the identical build could not be installed on the 17 Pro
this run — `devicectl list devices` reports it `connected`, but every
`--device <UDID>` invocation returns `CoreDeviceError error 1000` ("specified
device was not found"), reproducibly across three attempts. That is a CoreDevice
enumeration fault on the host, not a device fault (`usbmux list` shows both USB
and Network entries). The secondary-unit result stands; the primary confirmation
is outstanding.

## Reproduce

```
bash ~/build_race.sh                                   # BUILD_EXIT=0
xcrun devicectl device install app --device 00008110-000E095936C1801E \
    ~/agx-probe-project/.build13/Build/Products/Debug-iphoneos/AGXProbe.app
xcrun devicectl device process launch --device 00008110-000E095936C1801E \
    --console --terminate-existing com.bench27.agxprobe --routesock
```

Static caller analysis used `scratch/route_who_calls.py`,
`scratch/route_callers_ctx.py`, `scratch/route_funcs.py` against
`tools/opencode-temp/kc_fstarts.py` (`load_build("24A446")`).
