# HANDOFF — iOS 27.0.1 jailbreak research (2026-11-13, ~13:35)

Read this first if you are picking the work up cold.

## Goal

Get a working jailbreak on iOS 27.0/27.0.1. Missing gate: a kernel read/write primitive.
Top vector: **CVE-2026-112514** socket-buffer use-after-free (`uipc_socket2.c`), live on
27.0/27.0.1, fixed in 27.2 only.

**The race is won.** 20 confirmed stale kernel writes into reallocated sockets
(`analysis/socket-uaf-stale-write-2026-11-13.md`). Current work is conversion to controlled
R/W, not triggering. Per-path completion: `JAILBREAK-PATHS.md`.

## Targets

| Device | UDID | OS | State |
|---|---|---|---|
| iPhone 17 Pro (iPhone18,1) | `00008150-00095CD93444C01C` | **27.0.1** (exact target) | healthy, paired to the Mac, USB -> MacBook |
| iPhone 13 Pro (iPhone14,2) | `00008110-000E095936C1801E` | 27.0 (24A5390f) | **dropped off usbmux**, needs a physical force-restart |

## Access / toolchain

- **MacBook**: reachable over Tailscale as `volpidash@100.110.170.78`
  (node `no-oness-macbook-pro`, macOS 27.3, Xcode 27.2, arm64).
  SSH key: `~/.ssh/mac_ios16_ed25519`. Wi-Fi is flaky — always retry, run long jobs detached
  (`nohup ... &`) and poll their logs.
- **PC**: Windows 11. Apple USBMux on `127.0.0.1:27015`; `pymobiledevice3` installed under
  `C:\Users\Volpi\AppData\Local\Programs\Python\Python314` (use `python -m pymobiledevice3`).
  Device commands used so far: `usbmux list`, `apps list/install/pull/afc`, `crash`,
  `developer dvt launch '<bundle> <args>'`.
- **Build/deploy pipeline (working)**:
  1. `xcodebuild -project AGXProbe.xcodeproj -scheme AGXProbe -configuration Debug
     -destination "id=<udid>" -derivedDataPath .build13 -allowProvisioningUpdates build`
  2. `xcrun devicectl device install app --device <udid> <path>/AGXProbe.app`
  3. `xcrun devicectl device process launch --device <udid> --console --terminate-existing
     com.nianticlabs.pokemongo.4L9HF29JJU --sockuaf`
- Build script on the Mac: `~/build_race.sh` (destination currently the 17 Pro UDID).
  Signing: `iOS Team Provisioning Profile: com.nianticlabs.pokemongo.4L9HF29JJU`
  (**expires 2026-11-15** — regenerate before then).

## Where the code lives

- Carrier source (local copy, authoritative for edits):
  `C:\Users\Volpi\AppData\Local\hermes\cache\scratch\ContentView.swift`
  Remote: `~/agx-probe-project/AGXProbe/ContentView.swift` on the Mac.
- Repo clone: `G:/iOS 27.0.1/iOS` → `github.com/ramonburf/ios-27-jailbreak-research` (public).
  `gh` CLI is authenticated as `ramonburf`; push with `git push origin main`.
  Release `v0.4-socket-uaf` carries the carrier source archive; the signed IPA still has to be
  built on the Mac and attached to it.

## Socket-UAF status (stage 4, ~80%)

Carrier `--sockuaf` runs five variants per iteration (`it % 5`, round-robin):

- A: single-fd close-vs-send
- B: 8-fd close-half / send-half
- C: AF_UNIX socketpair close-vs-send
- D: retire a timer-armed socket (keepalive / RTO live in the kernel)
- E: **precision** — gated one-shot send per sender, close only after all six are in-kernel,
  refill with connected sockets, peer-delivery oracle

### Results

| Run | Device | Result |
|---|---|---|
| v1 | 13 Pro | died iter 0, SIGPIPE (fixed: `signal(SIGPIPE, SIG_IGN)`) |
| v2 | 17 Pro | 3000 iters clean, race not won |
| v3 | 17 Pro | ~6700 iters, then SIGKILL; race not won |
| hammer | 17 Pro | 17.8 k iters, 145 M sends, probes only |
| **precision** | **17 Pro** | **20 confirmed stale writes, first at iter 9; write primitive proven** |

Fixed along the way: SIGPIPE ignore; the 0x8BADF00D scene-create watchdog (loop moved off the
MainActor); per-iteration thread churn (persistent workers); double-close (CAS); weak detection
(peer-delivery oracle).

### Open problem (the only one that matters now)

The freed slot is reclaimed by another **socket**. A socket-to-socket stale write is a real
UAF but not yet R/W.

1. Reclaim with attacker-influenced data instead — cross-zone page exhaustion + `mach_msg`
   OOL spray, or observable socket fields (`so_proto`, `so_pcb`, `so_usecount`).
2. Add a leak (KASLR slide + overlapped object address) to build a fake `so_proto`.
3. Verify one controlled field differential, then use the dangling socket as the R/W channel.

## Other active threads

- **Kernelcache diff 27.0.1 → 27.2**: complete (`tools/opencode-temp/kc_diff_all.json`,
  91 kexts changed, 542 kernel functions). Confirms IOSurface notify-UAF fix,
  IOHIDFamily count-check fix, and a cluster of new state-byte checks that are candidates
  for the unmapped kernel UAFs. Triage scripts: `analyze_diff.py`, `analyze_diff2.py`.
- **AppleJPEGDriver** (kernel driver, t8150): reachable from an unprivileged sandboxed app
  (opens on type 0/1), dispatch table recovered (selectors 1–7 callable without
  `com.apple.private.*`). Consumes caller-supplied image structs (0x58 / 0x1000 / 0xda0).
  **No bug found yet** — see `analysis/LEAD-ASSESSMENT.md` §12.
- **Bounty folder**: `C:\Users\Volpi\Documents\Apple-Security-Bounty\` — README, template,
  candidate entries. Honest status: **no confirmed novel vulnerability yet**; everything
  with a known root cause already carries a CVE.

## Environment gotchas

- The macOS Tahoe VM (`G:/Hackintosh/macOS-VM`) boots to OpenCore but lists **no bootable
  OS**; its recovery image fails on `usr/standalone/OS.dmg.root_hash`. Do not trust it
  until fixed. `config.plist` was patched (`UEFI.APFS.GlobalConnect=true`), original backed
  up as `config.plist.orig-bak`.
- The 13 Pro needs someone physically present to force-restart it.
