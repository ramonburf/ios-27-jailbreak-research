# HANDOFF — iOS 27.0.1 jailbreak research (2026-11-13, ~17:45)

Read this first if you are picking the work up cold. Supersedes all earlier notes.

## Goal

**Semi-untethered jailbreak** on iOS 27.0/27.0.1 (user only needs semi-untethered — no
bootrom / LLB / trampoline work required). An app-carried kernel exploit → kernel R/W →
rootless bootstrap is sufficient. Missing gate: a **kernel read/write primitive**.

Top vector: **CVE-2026-112514** socket-buffer use-after-free (`uipc_socket2.c`), live on
27.0/27.0.1, fixed in 27.2 only. **The race is won on hardware** (see below).

Overall readiness ~30 %; socket path 80 %. Full per-path table: `JAILBREAK-PATHS.md`.

## Targets (note the exact UDIDs)

| Device | UDID | OS | State |
|---|---|---|---|
| iPhone 17 Pro (iPhone18,1) | `00008150-00095CD93444C01C` | **27.0.1** (24A446, target) | healthy, USB → MacBook |
| iPhone 13 Pro (iPhone14,2) | `00008110-000E095936C1801E` | 27.0 (24A5390f) | healthy again, USB → MacBook |

⚠️ The 17 Pro UDID ends **`...C01C`** (not `...C01E`). A one-character typo here makes every
pymobiledevice3 device lookup fail with "usbmux has no device matching udid" while
`usbmux list` still shows the device — cost real time to diagnose.

## Access / toolchain

- **MacBook**: Tailscale `volpidash@100.110.170.78` (`No-Oness-MacBook-Pro.local`, macOS 27.3,
  Xcode 27.2, arm64). SSH key `~/.ssh/mac_ios16_ed25519`. Wi-Fi is flaky — retry, run long jobs
  detached, poll logs. `192.168.1.99` also pings but **port 22 is not reachable** (the PC is not
  on that LAN); Tailscale is the working route.
- **PC**: Windows 11. Its own Apple usbmuxd is on `127.0.0.1:27015`. Python 3.14 at
  `C:/Users/Volpi/AppData/Local/Programs/Python/Python314/python.exe` with pymobiledevice3 in
  site-packages. Physical Ethernet is **disconnected**; the PC's live link is a USB-tethered
  adapter (`10.249.56.43`) and Tailscale was down for a while (service running, state `NoState`).
- **Reach both iPhones from the PC** (set up this session, still running):
  1. Mac runs `/private/tmp/usbmux_relay.py` → TCP `127.0.0.1:27015` bridged to Apple's
     unix-socket usbmuxd `/var/run/usbmuxd` (macOS Tahoe exposes no TCP usbmux).
  2. PC holds an SSH tunnel: `ssh -N -L 27016:127.0.0.1:27015 -i ~/.ssh/mac_ios16_ed25519 volpidash@100.110.170.78`
  3. Then:
     ```
     export PYMOBILEDEVICE3_USBMUX=127.0.0.1:27016
     export PYMOBILEDEVICE3_UDID=00008150-00095CD93444C01C
     python -m pymobiledevice3 crash pull --match "AGXProbe|Jetsam|NRD" OUTDIR
     ```
     (listing subcommand is `crash ls`, **not** `list`; `pull` takes `--udid` / `--match`.)
- **Mac python**: `~/ios27-ai-venv/bin/python` now has pymobiledevice3 (installed this session).
- **Build/deploy pipeline (working)**:
  ```
  bash ~/build_race.sh            # DEV defaults to the 17 Pro UDID
  xcrun devicectl device install app --device 00008150-00095CD93444C01C \
      ~/agx-probe-project/.build13/Build/Products/Debug-iphoneos/AGXProbe.app
  xcrun devicectl device process launch --device 00008150-00095CD93444C01C --console \
      --terminate-existing com.nianticlabs.pokemongo.4L9HF29JJU --sockprec
  ```
  Signing profile expires **2026-11-15** — regenerate before then or nothing builds/installs.

## Where the code lives (important)

- **Authoritative carrier source = the Mac's file**:
  `~/agx-probe-project/AGXProbe/ContentView.swift` (sha1 `88f4cb1f…`, **1423 lines**).
  The repo copy `carrier/AGXProbe/ContentView.swift` was stale (1235 lines) — re-synced to
  match at handoff. If they diverge again, trust the Mac.
- Local scratch copy: `C:\Users\Volpi\AppData\Local\hermes\cache\scratch\mac_ContentView.swift`.
- Repo: `G:/iOS 27.0.1/iOS` → `github.com/ramonburf/ios-27-jailbreak-research` (public).
  `gh` authenticated as `ramonburf`. Release tag `v0.4-socket-uaf` exists.

## Socket-UAF status (stage 4, ~80 %)

The precision variant (E) wins reliably: 20 confirmed stale writes into reallocated sockets on
hardware, first at iteration 9, via a peer-delivery oracle
(`analysis/socket-uaf-stale-write-2026-11-13.md`).

### Carrier modes (launch args)

`--sockuaf` runs variants A–E round-robin; solo modes pick one:

| arg | variant |
|---|---|
| `--sockprec` | E: gated one-shot send per sender + peer-delivery oracle (the winner) |
| `--sockool` | F: cross-zone reclaim with mach_msg OOL pages |
| `--sockxz` | G: free a whole socket page block, then OOL spray |
| `--sockgc` | H: batch-free past the zone page-return delay, then OOL spray |
| `--sockudp` | connected-UDP spray (type confusion instead of peer bytes) |

Variants F/G/H were added on the Mac **after** the last repo sync and had not been evaluated
when work paused. `SockUafSpray.c` provides `sockuaf_ool_spray(size, count, fill)`.

### Open problem (the only one that matters)

The freed `struct socket` slot is reclaimed by another **socket**, so the stale write lands in
socket-shaped fields. That is a real UAF write but not R/W. Need:

1. Reclaim with attacker-influenced data (cross-zone page exhaustion → `mach_msg` OOL spray),
   or with a socket whose overwritten fields are observable (`so_proto` / `so_pcb`).
2. A leak (KASLR slide + heap address of the overlapped object) to build a fake `so_proto`.
3. Prove one controlled field differential, then use the dangling socket as the R/W channel.

## ⚠️ Known blocker found this session: the CPU watchdog kills the app

All four `AGXProbe.cpu_resource-*.ips` reports say the same thing:

```
CPU: 90 seconds cpu time over 94 seconds (96% cpu average),
     exceeding limit of 50% cpu over 180 seconds
```

The harness dies after ~94 s because six persistent sender threads spin at 100 % CPU. Fix
before any long run — replace the busy-waits in
`~/agx-probe-project/AGXProbe/ContentView.swift`:

- line ~495 `if st.gate == 0 { continue }` → add `usleep(20)`
- line ~502 `while st.gate != 0 && st.stop == 0 { }` → `usleep(5)` inside
- line ~505 `if st.phase == 0 { continue }` → add `usleep(50)`
- closer loop ~547: spin only when `st.phase == 2`, else `usleep(100)`
- main iteration loop: add `usleep(200)` between iterations

This preserves the race window (variant E gates on `st.entered == 6` before closing) but drops
average CPU well below the 50 % threshold, so runs can go long enough to evaluate F/G/H.

## Other log findings from the 17 Pro (2026-11-13)

- `com.apple.NRD.UpdateBrainService` crashed 3× (13:33, 15:21, 17:09) — **Apple's own bug**:
  dyld aborts because the staged binary was `built for platform tvOS` but launched on iOS.
  Recurs roughly every 2 h, unrelated to our work. Possibly reportable, low impact.
- Both `JetsamEvent`s (13:29, 15:10) name **Discord** as largest process, reasons
  `per-process-limit` / `fc-thrashing` / `highwater` — not caused by AGXProbe.
- No kernel panic and no device reboot in any run.

## Bounty folder

`C:\Users\Volpi\Documents\Apple-Security-Bounty\` — README (rules + submission channels),
`TEMPLATE.md`, `candidates/`. Honest status: **no confirmed novel Apple vulnerability yet**;
everything with a known root cause already carries a CVE. Closest leads recorded there.

## Environment gotchas

- The macOS Tahoe VM (`G:/Hackintosh/macOS-VM`) boots to OpenCore but lists **no bootable OS**;
  its recovery image fails on `usr/standalone/OS.dmg.root_hash`. Do not rely on it.
  `config.plist` was patched (`UEFI.APFS.GlobalConnect=true`); original at `config.plist.orig-bak`.
- Nothing in the tree contains secrets; do not commit credentials.
