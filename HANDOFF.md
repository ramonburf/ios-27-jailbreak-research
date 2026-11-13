# HANDOFF — iOS 27.0.1 jailbreak research (2026-11-13, ~12:15)

Read this first if you are picking the work up cold.

## Goal

Get a working jailbreak on iOS 27.0/27.0.1. Missing gate: a kernel read/write primitive.
Top vector: **CVE-2026-112514** socket-buffer use-after-free (`uipc_socket2.c`), live on
27.0/27.0.1, fixed in 27.2 only.

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

## Socket-UAF status (stage 4, ~55%)

Carrier `--sockuaf` runs three race variants per iteration (round-robin by `it % 3`):

- A: single-fd close-vs-send (upstream `run_race_iteration`)
- B: 8-fd close-half / send-half (upstream `run_multi_fd_race`)
- C: AF_UNIX socketpair close-vs-send (+ a non-blocking reader)

### Results so far

| Run | Device | Result |
|---|---|---|
| v1 | 13 Pro | died iter 0, SIGPIPE (fixed: `signal(SIGPIPE, SIG_IGN)`) |
| v2 | 17 Pro | 3000 iters clean, **race not won** |
| v3 | 17 Pro | ~6700 iters, then SIGKILL (app resource ceiling, not a panic), **race not won** |

Fixes already applied: SIGPIPE ignore; both upstream race variants; bounded listener fd
holder (was leaking accepted fds → run budget doubled); loopback listener so connects
reach ESTABLISHED.

### Open problems

1. **Race never wins.** Suspects: (a) loopback sends drain instantly so no pending socket
   buffer state; (b) thread scheduling window too tight; (c) detection
   (`getsockopt(SO_TYPE)`/`SO_SNDBUF==0`) too weak — a won race may be silent.
2. **App gets SIGKILLed after ~6700 iters.** Cause unknown (jetsam vs watchdog vs fd/thread
   accumulation). Fix it to allow longer runs.
3. No KASLR/pointer-leak oracle, so a won race would not be observable even if it happened.

### Concrete next steps

- Try a **real network peer** instead of loopback (point the target at a host that accepts
  but does not read), or shrink `SO_RCVBUF` and send much more data to force backlog.
- Add a blocking/slow receiver thread; widen timing windows; add CPU contention.
- Strengthen detection: monitor the *target* socket state, `getpeername`, unexpected
  `send()` return codes, and any kernel panic/reboot.
- Investigate the SIGKILL: capture ` JetsamEvent`/`ApplicationExit` reports from the device.

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
