# iOS 27.0.1 Jailbreak — Progress Tracker

Last updated: 2026-11-13
Targets: iPhone 13 Pro (iPhone14,2, iOS 27.0 build 24A5390f) and iPhone 17 Pro (iOS 27.0.1).
Working tree: `G:/iOS 27.0.1/iOS`. Remote: `ramonburf/ios-27-jailbreak-research`.

Percentages are "how far along that component is toward being a working part of the chain",
not "probability it will work". 100% = done and verified on hardware.

## Chain stages

| # | Stage | Component | Status | % |
|---|-------|-----------|--------|---|
| 1 | Target acquisition | Firmware/kernelcache/dyld-cache for 24A446 (17 Pro) + 24B119 (27.2 reference) | Complete | **100%** |
| 2 | Reachability map | Sandbox-app reachability of AGX/IOHID/IOSurface/WebKit daemons | Complete (AGX sweep v39, iokit enumeration, crash corpus) | **95%** |
| 3 | Vulnerability ID | Whole-kernelcache diff 27.0.1 -> 27.2 (91 kexts, 542 changed kernel funcs) mapped to CVEs | Complete | **90%** |
| 4 | Kernel r/w primitive | **CVE-2026-112514 socket-buffer UAF** (CVSS 9.1, network-reachable, no entitlements) | **Race won on hardware.** Watchdog/SIGPIPE/thread-churn kills all fixed; detached persistent-worker harness with a decisive peer-delivery oracle; **20 confirmed stale kernel writes** into reallocated sockets, first at iteration 9. Conversion to a controlled R/W primitive not started | **80%** |
| 4b | Kernel r/w primitive | IOSurface notify UAF family (CVE-2026-112517 / -112516 / -112477) | Identified; PAC/type-confusion constraints unresolved | **25%** |
| 4c | Kernel r/w primitive | IOHIDFamily OOB r/w (CVE-2026-112507) | Patch confirmed in diff; no sandbox-openable HID class | **20%** |
| 4d | Kernel r/w primitive | Other diff-derived kernel UAF candidates | Triage list produced; unconfirmed | **15%** |
| 5 | Build/deploy pipeline | Mac (Xcode) -> Tailscale -> PC -> `pymobiledevice3` install onto iPhone | Working end-to-end | **100%** |
| 6 | EL1 code exec past PAC/CTRR/SPTM (TXM trustcache) | Required after kR/W before any persistent code runs | Not started | **5%** |
| 7 | Credential patch + rootless bootstrap (package manager) | Final stage | Not started | **5%** |

**Overall: ~30%.** The race is won; the gating item is now stage 4 conversion — turning the
confirmed stale write into a controlled kernel read/write (controlled reallocation + leak).
Everything upstream of it (targets, reachability, bug ID, build pipeline) is essentially done;
everything downstream (EL1, bootstrap) is untouched. Per-path percentages:
`JAILBREAK-PATHS.md`.

## Confirmed 27.0.1 -> 27.2 fix sites (live on our devices)

- `com.apple.iokit.IOSurface` — exactly 2 changed functions: `+0xf1` dying-flag check (`ldrb`/`tbz`)
  and the teardown `strb`. Matches the notify-UAF family.
- `com.apple.iokit.IOHIDFamily` — 4 accessors gain `cmp` + `b.ge` + count load (CVE-2026-112507).
- `com.apple.kernel` — 542 changed functions; cluster of new state-byte checks
  (`ldrb`+`tbz`/`tbnz`) = candidate UAF fixes for the still-unmapped kernel CVEs.
- Socket UAF (CVE-2026-112514) is *invisible* to a pair-diff: 27.2 de-inlined the `sb*`
  helpers into 17 new functions, which is why the earlier bench missed it.

## Build/deploy pipeline (working)

1. MacBook (Xcode 27.2, arm64, macOS 27.3) reachable over Tailscale as `no-oness-macbook-pro`.
2. `xcodebuild ... -destination generic/platform=iOS -allowProvisioningUpdates` -> `AGXProbe.app`
   (signed with `iOS Team Provisioning Profile: com.nianticlabs.pokemongo.4L9HF29JJU`,
   includes the 13 Pro UDID; expires 2026-11-15).
3. Wrap as IPA, transfer to the Windows PC.
4. Install onto the USB-attached iPhone with `pymobiledevice3 apps install`.

## Device status (2026-11-13)

- **iPhone 17 Pro** (iPhone18,1, iOS 27.0.1): healthy, paired to the Mac, exact target build. Primary test device.
- **iPhone 13 Pro** (iPhone14,2, iOS 27.0): dropped off `usbmux` after run 1; USB node still
  enumerates but the mux protocol does not answer. Needs a physical force-restart / cable check.

## Immediate next step

Convert the confirmed stale write into a controlled primitive: reclaim the freed socket slot
with attacker-shaped data (or a cross-zone page spray) instead of another socket, and add a
leak. Evidence and harness notes: `analysis/socket-uaf-stale-write-2026-11-13.md`.
