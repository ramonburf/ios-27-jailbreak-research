# iOS 27 jailbreak research

Research toward a **semi-untethered jailbreak** on iOS 27.0 / 27.0.1 (arm64e).

The aim is an app-carried kernel exploit that yields kernel read/write, followed by a
rootless bootstrap (package manager + tweaks). No bootrom, LLB or trampoline work is in
scope — a semi-untethered result is the goal, not a boot-time untethered one.

All testing happens on **owned, authorised devices** under a strict no-data-loss rule: no
restores, no firmware writes, no updates or downgrades.

## Status

| # | Stage | Status |
|---|-------|--------|
| 1 | Target acquisition (firmware, kernelcache, dyld shared cache) | Done |
| 2 | Reachability map of interesting daemons from an ordinary app sandbox | Done |
| 3 | Vulnerability identification via whole-kernelcache diff (27.0.1 → 27.2) | Done |
| 4 | **Kernel read/write primitive** — CVE-2026-112514 socket-buffer UAF | **Race won on hardware; conversion to controlled R/W not started** |
| 4b–4d | Alternate r/w candidates (IOSurface notify UAF family, IOHIDFamily OOB) | Identified, constrained |
| 5 | Build / deploy pipeline | Working |
| 6 | EL1 code execution past PAC/CTRR/SPTM | Not started |
| 7 | Rootless bootstrap | Not started |

Overall: roughly 30 %. Everything upstream of stage 4 is essentially complete; everything
downstream is untouched.

## The lead: CVE-2026-112514

A use-after-free in the socket buffer accounting path (`uipc_socket2.c`) that is live in
iOS 27.0/27.0.1 and was fixed in 27.2 only. It needs no entitlements and is reachable from
an ordinary app sandbox, which makes it unusually valuable.

The bug: when a socket is torn down while sends are still being processed, the kernel can
keep using a socket buffer that has already been freed and reallocated. By racing a close
against concurrent sends from several threads, the kernel can be made to append data to a
buffer that now belongs to a *different* socket.

**What has been demonstrated on real hardware:** a reliable race win, confirmed by a
peer-delivery oracle — 20 confirmed stale kernel writes into sockets that had been
reallocated after the free. See `analysis/socket-uaf-stale-write-2026-11-13.md`.

**What remains:** turning that into a controlled read/write primitive. The freed slot gets
reclaimed by another *socket*, so the stale write lands in socket-shaped memory rather than
attacker-controlled data. The next step is to reclaim the slot with attacker-influenced
contents (cross-zone page exhaustion plus an out-of-line `mach_msg` spray), then obtain a
leak (KASLR slide and heap address) needed to shape a fake protocol-control object.

## Repository layout

```
carrier/            The on-device harness ("AGXProbe") — SwiftUI app, no entitlements.
  AGXProbe/           App source. ContentView.swift is the main entry point.
  tests/              Headless regression tests for non-UI logic (see its README).
analysis/           Per-topic research notes, bug analysis and evidence logs.
  socket-uaf-*.md     The working notes for CVE-2026-112514, including hardware results.
  LEAD-ASSESSMENT.md  Survey and ranking of every candidate surface examined so far.
JAILBREAK-PATHS.md  Readiness table per exploitation path.
PROGRESS.md          Stage-by-stage progress tracker.
HANDOFF.md           Current state, blockers and immediate next steps.
FIRMWARE-BASELINE.md Firmware inspection notes and how to reproduce them.
```

Kernelcache diffing tooling lives under `tools/opencode-temp/` (not all of it is tracked —
the firmware images themselves are far too large for git and are listed in `.gitignore`).

## Building and running

Requirements: macOS with Xcode, an Apple developer account (a free one is sufficient), and
the target device attached over USB with Developer Mode enabled.

```sh
DEV=<device-udid> ./build_race.sh                 # builds .build13/.../AGXProbe.app
xcrun devicectl device install app --device $DEV \
    .build13/Build/Products/Debug-iphoneos/AGXProbe.app
xcrun devicectl device process launch --device $DEV --terminate-existing \
    com.bench27.agxprobe --sockprec               # substitute your own bundle id
```

`com.bench27.agxprobe` above is a placeholder — replace it with whatever bundle identifier
your own signing identity uses.

### Launch arguments

| Argument | Mode |
|---|---|
| `--sockuaf` | Socket-UAF harness, variants A–E round-robin |
| `--sockprec` | Variant E only: gated one-shot send per sender + peer-delivery oracle (the current best) |
| `--sockool` | Variant F: cross-zone reclaim using an out-of-line `mach_msg` spray |
| `--sockxz` | Variant G: free a whole socket page block, then spray |
| `--sockgc` | Variant H: batch-free past the zone's page-return delay, then spray |
| `--web`, `--webscan` | WebKit probing |
| `--probe` | IOSurface probe sweep |

## Accessing the device from another machine

When the device is attached to a machine other than the build host, `usbmuxd` usually
exposes only a local unix socket, and some tooling wants TCP. A small relay bridges the two:

```sh
# on the machine with the device attached
python3 usbmux_relay.py        # /var/run/usbmuxd  ->  127.0.0.1:27015
# on the analysis machine
ssh -N -L 27016:127.0.0.1:27015 <user>@<host>
export PYMOBILEDEVICE3_USBMUX=127.0.0.1:27016
python3 -m pymobiledevice3 crash pull --match "AGXProbe" outdir/
```

## Verifying changes

```sh
cd carrier/tests
swiftc -O fixcheck.swift -o /tmp/fixcheck && /tmp/fixcheck
swiftc -O logcheck.swift -o /tmp/logcheck && /tmp/logcheck
```

Both programs print `PASS`/`FAIL` per assertion and exit non-zero on failure. See
`carrier/tests/README.md` for what each covers and what still needs manual UI testing.

## Notes

- Nothing in this repository contains credentials or signing material; do not commit any.
- Findings here are published for defensive and research purposes, on hardware owned by the
  researcher. Any vulnerability discovered is intended to be reported to Apple through the
  official security bounty programme before broader disclosure.
