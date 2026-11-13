# Progress tracker

Last updated: 2026-11-13.

Percentages mean "how far along that component is toward being a working part of the chain",
not "probability it will work". 100 % means done and verified on hardware.

## Chain stages

| # | Stage | Component | Status | % |
|---|-------|-----------|--------|---|
| 1 | Target acquisition | Firmware / kernelcache / dyld shared cache for build 24A446 (target) plus a 27.2 reference build | Complete | **100%** |
| 2 | Reachability map | Sandbox-app reachability of AGX / IOHID / IOSurface / WebKit daemons | Complete (AGX sweep, iokit enumeration, crash corpus) | **95%** |
| 3 | Vulnerability ID | Whole-kernelcache diff 27.0.1 → 27.2 (91 kexts, 542 changed kernel functions) mapped to CVEs | Complete | **90%** |
| 4 | Kernel r/w primitive | **CVE-2026-112514 socket-buffer UAF** (CVSS 9.1, network-reachable, no entitlements) | **Race won on hardware.** Persistent-worker harness with a decisive peer-delivery oracle; **20 confirmed stale kernel writes** into reallocated sockets. Conversion to a controlled R/W primitive not started | **80%** |
| 4b | Kernel r/w primitive | IOSurface notify UAF family (CVE-2026-112517 / -112516 / -112477) | Identified; PAC / type-confusion constraints unresolved | **25%** |
| 4c | Kernel r/w primitive | IOHIDFamily OOB r/w (CVE-2026-112507) | Patch confirmed in the diff; no sandbox-openable HID class found | **20%** |
| 4d | Kernel r/w primitive | Other diff-derived kernel UAF candidates | Triage list produced; unconfirmed | **15%** |
| 5 | Build / deploy pipeline | macOS + Xcode → signed `.app` → `devicectl` install → launch on device | Working end-to-end | **100%** |
| 6 | EL1 code exec past PAC/CTRR/SPTM (TXM trustcache) | Required after kernel r/w before any persistent code runs | Not started | **5%** |
| 7 | Credential patch + rootless bootstrap (package manager) | Final stage | Not started | **5%** |

**Overall: ~30%.** The race is won; the gating item is now stage 4 conversion — turning the
confirmed stale write into a controlled kernel read/write (controlled reallocation plus a
leak). Everything upstream of it (targets, reachability, bug identification, build pipeline)
is essentially done; everything downstream (EL1, bootstrap) is untouched. Per-path
percentages are in `JAILBREAK-PATHS.md`.

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

Convert the confirmed stale write into a controlled primitive: reclaim the freed socket slot
with attacker-shaped data (or a cross-zone page spray) instead of another socket, and add a
leak. Evidence and harness notes: `analysis/socket-uaf-stale-write-2026-11-13.md`, and the
open technical questions in `HANDOFF.md`.
