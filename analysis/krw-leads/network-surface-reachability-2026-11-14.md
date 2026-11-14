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
3. Compare the 27.0.1 and 27.2 route-socket handlers (`route_output`, `rtrequest`,
   `rt_xaddrs`...) with the exact-diff tooling; the changed netinet functions above are the
   starting set.

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
