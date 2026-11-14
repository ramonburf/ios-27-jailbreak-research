# Network-surface reachability from the app sandbox (`--rawsock`, 2026-11-14)

Device run, both iPhones, carrier build `com.bench27.agxprobe` (build 24A446 harness).
Probe added as `network_surface_probe()` in `carrier/AGXProbe/SockUafSpray.c`
(launch argument `--rawsock`; dispatch in `ContentView.swift`).

## Why

Several live leads live in the kernel's network input/output path — most notably the
`m_sum16` / `m_adj_sum16` mbuf-chain length arithmetic that Apple widened from 32-bit to
64-bit in 27.2 (`analysis/kernelcache-mbuf-len-truncation-2026-11-14.md`). Every caller of
those functions derives `off`/`len` from packet header fields. Whether an *app-carried*
chain can reach them depends entirely on whether a sandboxed app can inject crafted
packets. This probe settles that empirically instead of guessing.

## Results — identical on iPhone 13 Pro (27.0, secondary) and iPhone 17 Pro (27.0.1, primary)

```
[-] AF_INET/SOCK_RAW/ICMP        ERR errno=1 (Operation not permitted)
[-] AF_INET/SOCK_RAW/UDP         ERR errno=1 (Operation not permitted)
[-] AF_INET/SOCK_RAW/TCP         ERR errno=1 (Operation not permitted)
[-] AF_INET/SOCK_RAW/RAW         ERR errno=1 (Operation not permitted)
[-] AF_INET/SOCK_DGRAM/IGMP      ERR errno=41 (Protocol wrong type for socket)
[-] AF_INET6/SOCK_RAW/ICMPV6     ERR errno=1 (Operation not permitted)
[-] AF_INET6/SOCK_RAW/RAW        ERR errno=1 (Operation not permitted)
[-] PF_NDRV/SOCK_RAW/0           ERR errno=1 (Operation not permitted)
[+] PF_ROUTE/SOCK_RAW/INET       OK fd=135
[+] AF_SYSTEM/SOCK_DGRAM/CTRL    OK fd=135
[+] AF_INET/SOCK_STREAM/TCP      OK fd=135
[+] AF_UNIX/SOCK_DGRAM/0         OK fd=135
[-] /dev/bpf0 open errno=1 (Operation not permitted)
[*] rawsock: 4/12 socket families opened
```

`fd=135` repeats because each successful fd is closed before the next call, so the next
allocation reuses the same number. Both devices produced byte-identical results.

## What this proves

1. **Raw-packet injection is unavailable.** `SOCK_RAW` (IPv4 and IPv6), `PF_NDRV` and the
   BPF device are all refused with `EPERM` from the app sandbox on 27.0/27.0.1. An app
   cannot craft IP/TCP/UDP/ICMP headers, cannot feed arbitrary header field values into
   the kernel's input path, and cannot observe loopback traffic.
2. **Therefore the `m_sum16`/`m_adj_sum16` truncation lead is not app-reachable.** Its
   callers are the input-path checksum routines (`inet_cksum`, `inet6_cksum`, `igmp`,
   `mld6`, `nd6_prproxy`, `ipsec`, bridge). Reaching the 32-bit `off+len` wrap needs a
   packet whose header-derived lengths are attacker-chosen; the sandbox gives us no way
   to produce such a packet. Verdict: **remote/AV:N only**, which matches the advisory class
   but makes it useless for an app-carried jailbreak chain.
3. **No BPF/packet-capture route either.** Even passive observation of kernel networking is
   blocked, so the mbuf-overwrite class of primitives stays invisible from an app.

## What it opens: `PF_ROUTE` is reachable

`socket(PF_ROUTE, SOCK_RAW, AF_INET)` succeeds from the app sandbox and yields a usable fd.
That is a kernel-facing control interface (routing-table messages, interface walk-ups,
`rt_msghdr` parsing) reachable without any entitlement. It is the only non-socket API of
this kind measured so far. Route sockets are a classic source of kernel parsing bugs, and
the 27.0.1 → 27.2 diff already contains changed netinet functions (`nd6_send.c`,
`in6_pcb.c`, `igmp.c`, `net_filter_event`) that could be reached from it.

### Next step for `PF_ROUTE`

Characterise read vs write before treating it as an exploit surface:

1. **Read-only**: send `RTM_IFINFO` / `RTM_GET` messages on the route socket and confirm the
   kernel answers (sizes/fields), using a dedicated probe round-trip with a timeout.
2. **Write attempt with deliberately invalid arguments**: `RTM_ADD` of a route with an
   invalid address family or an unsatisfiable mask should fail without changing state;
   only then consider whether a valid `RTM_ADD`/`RTM_DELETE` is possible from the sandbox.
   Do not add a live route on either device without planning the rollback.
3. Compare the 27.0.1 and 27.2 route-socket handlers with the exact-diff tooling; the changed
   netinet functions above are the starting set.

## Static first pass on the route-socket path (same day)

One changed function in `bsd/net/route.c` is already localised:

| | 24A446 (27.0.1) | 24B119 (27.2) |
|---|---|---|
| address / size | `0xfffffe000ae662ec`, `0x2ac` | `0xfffffe000aeb9588`, `0x2f0` |
| growth | — | +`0x44` |

Its source-file references are `bsd/net/route.c` lines `0x30f` (783), `0x367` (871) and
`0x36c` (876), and it validates AF_LINK/`AF_INET`/`AF_INET6` sockaddrs
(`family` at `+1` compared against `0x12`/`0x1e`/`2`; `nlen`/`alen` at `+5`/`+6`; data at
`+8` — the `sockaddr_dl` layout). It is called with `buflen = 0x100` from
`0xfffffe000ae72138` and `0xfffffe000ae7507c`.

The semantic difference is in one check:

```
24A446:   cmp   x2, w9          ; x2 = parsed length, w9 = dest->alen
          b.ne  <VERIFY panic>  ; any mismatch panics ("buflen >= sa->sa_len")

24B119:   cmp   x20, w9
          b.hi  <VERIFY panic>  ; only > panics
          ...                   ; plus a whole extra copy/validate block for the
                                ; shorter-than-declared case (subs/adds/bl)
```

So 27.0.1 treats *any* length mismatch between the parsed value and `sockaddr_dl.sdl_alen`
as a fatal `VERIFY` (kernel `brk #0x5519`), while 27.2 only panics when the parsed value is
larger and otherwise handles the remainder explicitly. Two possibilities, unseparated so far:

1. Apple fixed an app-triggerable kernel panic reached through the route socket — worth a
   controlled test on the secondary device.
2. The check is over kernel-internal structures that user input cannot make inconsistent,
   and the change is a refactor.

**Do not claim either without a trigger.** The next step is to drive the route socket with
crafted `RTM_*` messages on the 13 Pro only, starting with well-formed `RTM_IFINFO`/`RTM_GET`,
then deliberately mismatched `sa_len`/`sdl_alen` values, watching for a `brk` panic in the
crash log. Per the standing rule, stop immediately on any panic/reboot and pull the report
first. Tooling used: `scratch/route_fn.py`, `route_b.py`, `route_pair.py`, `route_dis.py`,
`route_callers.py`.

## Reproduce

```
# on the macOS build host
bash ~/build_race.sh                                        # BUILD_EXIT=0
xcrun devicectl device install app --device <UDID> \
    ~/agx-probe-project/.build13/Build/Products/Debug-iphoneos/AGXProbe.app
xcrun devicectl device process launch --device <UDID> --console --terminate-existing \
    com.bench27.agxprobe --rawsock
```

Console output is captured directly; `log_from_c` alone would land only in the app's own
session log, so the C probe mirrors every line to stdout as well.
