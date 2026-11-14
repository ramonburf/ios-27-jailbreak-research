# Progress tracker

Last updated: 2026-11-14.

Percentages mean "how far along that component is toward being a working part of the chain",
not "probability it will work". 100 % means done and verified on hardware.

## Chain stages

| # | Stage | Component | Status | % |
|---|-------|-----------|--------|---|
| 1 | Target acquisition | Firmware / kernelcache / dyld shared cache for build 24A446 (target) plus a 27.2 reference build | Complete | **100%** |
| 2 | Reachability map | Sandbox-app reachability of AGX / IOHID / IOSurface / WebKit daemons / network socket families | Complete (AGX sweep, iokit enumeration, crash corpus, `--rawsock` both devices) | **96%** |
| 3 | Vulnerability ID | Whole-kernelcache diff 27.0.1 → 27.2 (91 kexts, 542 changed kernel functions) mapped to CVEs | Complete | **90%** |
| 4 | Kernel r/w primitive | **CVE-2026-112514 socket-buffer UAF** (CVSS 9.1, network-reachable, no entitlements) | **Race won on hardware**, and as of 2026-11-14 the freed slot can be forced into a `SOCK_DGRAM` object (`--sockmix`: 335 datagrams on the 13 Pro, 14 on the 17 Pro). Exact function diffing shows the whole BSD socket core is **semantically unchanged** in 27.2, so this is probably not the CVE-2026-112514 fix site; and `struct socket` is allocated through a view-based typed allocator, so cross-type reclaim is structurally blocked. Still not kR/W | **83%** |
| 4b | Kernel r/w primitive | IOSurface notify UAF family (CVE-2026-112517 / -112516 / -112477) | Identified; PAC / type-confusion constraints unresolved | **25%** |
| 4c | Kernel r/w primitive | IOHIDFamily OOB r/w (CVE-2026-112507) | Patch confirmed in the diff; no sandbox-openable HID class found | **20%** |
| 4d | Kernel r/w primitive | Other diff-derived kernel UAF candidates | Triage list produced; unconfirmed | **15%** |
| 4e | Kernel r/w primitive | `uipc_mbuf2.c` mbuf-chain length arithmetic (`m_sum16` / `m_adj_sum16`, four 32→64-bit sites confirmed changed in 27.2) | Functions identified and fully caller-mapped; several callers pass underflow-capable header-field differences. Raw sockets are denied to apps on both devices, so the path is **remote-only (`AV:N`), not app-reachable**. Keep as a bounty candidate | **30%** |
| 4f | Kernel r/w primitive | `PF_ROUTE` raw route socket from the app sandbox | Measured reachable on both devices (`--rawsock`); read/write capability and the 27.0.1→27.2 route-handler diff untested | **10%** |
| 5 | Build / deploy pipeline | macOS + Xcode → signed `.app` → `devicectl` install → launch on device | Working end-to-end | **100%** |
| 6 | EL1 code exec past PAC/CTRR/SPTM (TXM trustcache) | Required after kernel r/w before any persistent code runs | Not started | **5%** |
| 7 | Credential patch + rootless bootstrap (package manager) | Final stage | Not started | **5%** |

**Overall: ~31%.** The race is won and the slot can now be forced into a foreign-protocol
object; the gating item is stage 4 conversion — naming and then controlling one corrupted
kernel field. Everything upstream of it (targets, reachability, bug identification, build
pipeline) is essentially done; everything downstream (EL1, bootstrap) is untouched.
Per-path percentages are in `JAILBREAK-PATHS.md`.

## Confirmed 27.0.1 → 27.2 fix sites

- `com.apple.iokit.IOSurface` — exactly two changed functions: a dying-flag check
  (`ldrb` / `tbz`) at `+0xf1` and the teardown `strb`. Matches the notify-UAF family.
- `com.apple.iokit.IOHIDFamily` — four accessors gain `cmp` + `b.ge` + a count load
  (CVE-2026-112507).
- `com.apple.kernel` — 542 changed functions; a cluster of new state-byte checks
  (`ldrb` + `tbz`/`tbnz`) are candidate UAF fixes for kernel CVEs not yet mapped.
- The socket UAF (CVE-2026-112514) is *invisible* to a plain pair-diff: 27.2 de-inlined the
  `sb*` helpers into 17 new functions, which is why an earlier pass missed it.

## Build and deploy pipeline

1. Build the carrier on macOS with Xcode:
   `xcodebuild -destination generic/platform=iOS -allowProvisioningUpdates`.
2. Install onto the attached device:
   `xcrun devicectl device install app --device <udid> <path-to-.app>`.
3. Launch with a mode argument and capture the console, e.g.
   `xcrun devicectl device process launch --device <udid> --console --terminate-existing \
    <bundle-id> --sockprec`.
4. Logs appear both on the console and in the app's own container.

Signing uses a standard development provisioning profile. Its details (bundle identifier,
team, expiry) are environment-specific and are deliberately omitted from this repository —
substitute your own.

## Immediate next step

The socket UAF remains blocked by type isolation; the mbuf checksum lead is now closed as
app-reachable work (raw sockets are denied). Priorities:

1. **Characterise `PF_ROUTE`** — measured reachable from the app sandbox on both devices.
   Read-only route messages first, then invalid-argument writes, then the 27.0.1→27.2
   route-handler diff (`analysis/krw-leads/network-surface-reachability-2026-11-14.md`).
2. **Identify the CVE-2026-112576 guard helper** `0xfffffe000acbabd8` and the setter of
   `[obj+0x75]` bit 1 before any further CoW device work.
3. **Use `tools/opencode-temp/kc_fstarts.py` + `kc_norm_diff.py` + `kc_align_region.py` for
   all future 27.0.1↔27.2 comparisons**; the method is exact and removes relocation noise.

Evidence: `analysis/kernelcache-funcstarts-exact-diff-2026-11-14.md`,
`analysis/socket-uaf-crosstype-2026-11-14.md`, `analysis/socket-uaf-stale-write-2026-11-13.md`,
`analysis/krw-leads/network-surface-reachability-2026-11-14.md`,
`analysis/krw-leads/msum16-checksum-callers-2026-11-14.md`, and `HANDOFF.md`.
