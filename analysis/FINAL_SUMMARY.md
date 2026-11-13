# iOS 27.0.1 Jailbreak Research — FINAL SUMMARY

## Objective
Develop a jailbreak for iPhone 17 Pro (iPhone18,1 / t8150 / A19 Pro) on iOS 27.0.1 (24A446).
**User's real goal:** "i just want to have sileo and tweaks working" — requires kernel code execution.

## Devices Tested
| Device | Model | SoC | iOS | UDID |
|--------|-------|-----|-----|------|
| Primary | iPhone 17 Pro | A19 Pro (T8150) | 27.0.1 (24A446) | <device-udid> |
| Secondary | iPhone 13 Pro | A14 | 27.0 dev beta 4 | <device-udid> |

Both devices paired, Developer Mode on, probes installed and verified working.

## Every Attack Surface Tested

### IOKit / Kernel Drivers

| Surface | Status | Result |
|---------|--------|--------|
| **IOSurfaceRoot** (all 60 selectors) | Exhausted | Every selector returns `0xe00002c2` (BadArgument) or empty output. All edge cases (width=0, height=0, BPE=0, BPR=0, max alloc, >20 planes, superbuffer aliasing, HBR extremes) properly validated. No memory-safety bug found. |
| **AGX / AGXG18P (17 Pro) / AGXG14P (13 Pro)** | Exhausted | sel=0x4 returns static userland buffer info. All other selectors 0x0-0xFF return `0xe00002c7` (Unsupported). Channel-index OOB read exists in kext but NOT reachable via user-connectable selector. |
| **AppleJPEGDriver** | Exhausted | Codec selectors power-gated (`0xe00002cc`/`0xe00002bc`). All other selectors unsupported/error. |
| **AppleM2ScalerCSCDriver** | Exhausted | Property path is inert; read-back is static configuration. |
| **AppleAVE2** | Exhausted | Fixed-address write only — DoS, no arbitrary kernel write. |
| **AppleSARService** | Dropped | `0xE00002E2` NotPermitted. |
| **AppleKeyStore** | Tested | Opens on types 0-3. Selectors 0x0, 0x1, 0x10 return all-zeros. Selectors 0x11, 0x1f return plist-like data. All are getters — no memory-safety bugs. |
| **AppleSEPKeyStore** | Tested | Cannot open (IPC error `0xfffffffe`). |

### Userspace Exploits (reviewed, not useful for jailbreak)

| CVE / Repo | Surface | Status | Why not useful |
|------------|---------|--------|----------------|
| **CVE-2026-112688** (0xjohnnydev/backboardd) | CoreMedia Dolby Vision RPU in backboardd | Pre-fix on 27.0.1 | Saved-LR corruption stopped by PAC. Constrained write-1 (only writes value `1`) within existing 4 GB range. No arbitrary read/write, no kernel access. |
| **CVE-2026-112611** (Ping-2o/CG-shading) | CoreGraphics PDF Type-5 shading | Pre-fix on 27.0.1 | Userland only. Crashes Preview deterministically with attacker-controlled fault address, but no kernel access, no sandbox escape. |
| **CVE-2026-112611** (Rust505) | CoreGraphics PDF | Already fixed | Userland heap overflow (DoS) only, no kernel access. |

### Sandbox Escape (reviewed)

| Surface | Status | Result |
|---------|--------|--------|
| **worse_query** | Exhausted | Sandbox escape — read/write other containers, edit MobileGestalt cache. **No kernel r/w.** Cannot install Sileo/tweaks without kernel exploit. worse_query upstream: "This is not relevant to a jailbreak and never will be." |

### Independent Research (SKVLENT/iOS27-Research-Exploits)

Cloned and reviewed: https://github.com/SKVLENT/iOS27-Research-Exploits

| Finding | Surface | SKVLENT Verdict | Our Reproduction |
|---------|---------|----------------|------------------|
| #01 | IOSurface size validation | Demonstrated (4 GiB header accepted) | ✅ Confirmed kr=0x0 on both devices, but "No expansion of accessible memory observed" |
| #02 | Metal GPU VA | Partially demonstrated | Same-context cross-page access only |
| #03 | mediaplaybackd / FigXPC | Partially demonstrated | NULL dereference = DoS only |
| #04 | AppleAVE2 | Partially demonstrated | Fixed-address write = DoS only |
| #05 | ANE reachability | Not demonstrated | Not reachable from sandbox |
| #06 | AppleM2ScalerCSCDriver | Not demonstrated | Property path inert |
| #07 | Container path disclosure | Demonstrated | Info disclosure only |
| #08 | Image parser surfaces | Not demonstrated (entitlement) | All selectors BadArgument |
| #09 | External leads | Not demonstrated (closed) | All three leads closed |
| #10 | Sandbox escape (worse_query) | Demonstrated | Userland container R/W only, no kernel |

**SKVLENT bottom line:** "Kernel read/write and a jailbreak were **not demonstrated** on this configuration."

### Independent Research (iOS-Research / AzozzALFiras)

Cloned and reviewed: https://github.com/AzozzALFiras/iOS-Research

Comprehensive static analysis of iOS 27.0.1 firmware covering:
- Media parsers (ImageIO, USD, CoreMedia, CoreGraphics) — all bugs already patched in 27.2
- SPTM (Secure Page Table Monitor) — fully mapped, one race already patched
- TXM (Code-Signing Monitor) — sound, no bugs
- Exclaves (cL4 secure kernel) — all hardened
- Kernel zone mitigations — RO wall holds against data-only R/W
- IOKit fuzzing — 1430 services, 343 classes, 108 openable, 3.45M calls → **0 crashes**

**iOS-Research bottom line:** "current iOS (27.0.1) is hardened across every surface examined here."

## Open Questions (Not Exploitable Without Kernel R/W)

Per iOS-Research STATUS.md:
- **fg_cred / so_cred reader-side** — Requires kernel R/W already
- **AGXG17P GPU channel-index OOB read** — Live in 27.0.1 but reachability pending; A18 Pro only (not our A19 Pro)
- **SPTM GMMU-TLBI race** — DeviceTree-gated off on this device
- **Kernel-zone exploitation path** — Requires PAC-defeating call primitive
- **ANE deserializer low-confidence site** — Not 100% closed but unproven

## Conclusion

**No kernel read/write primitive or exploitable memory-safety bug has been found on iOS 27.0.1** across all tested attack surfaces on both devices.

This is independently confirmed by:
1. Our exhaustive on-device testing (IOSurface, AGX, AppleJPEGDriver, AppleAVE2, AppleKeyStore, etc.)
2. SKVLENT's research bench (70 probes across 10 articles)
3. iOS-Research's static analysis of the firmware

**Without kernel code execution, Sileo and tweaks cannot be installed** on iOS 27.0.1. The worse_query sandbox escape provides userland container read/write but cannot install system-level software.

## Files
- `G:\iOS 27.0.1\iOS\analysis\CURRENT_STATUS.md` — Full project status
- `G:\iOS 27.0.1\iOS\analysis\SKVLENT_TEST_RESULTS.md` — SKVLENT comparison results
- `G:\iOS 27.0.1\iOS\tools\opencode-temp\SKVLENT-repo/` — Cloned SKVLENT repository
- `G:\iOS 27.0.1\iOS\tools\opencode-temp\CVE-2026-112688-backboardd/` — Cloned backboardd CVE repo
- `G:\iOS 27.0.1\iOS\tools\opencode-temp\CVE-2026-112611-cg-shading/` — Cloned CoreGraphics CVE repo
- `G:\iOS 27.0.1\iOS\iOS-Research\` — Cloned iOS-Research repository
- `G:\iOS 27.0.1\iOS\analysis\reach\WORSE-QUERY-VERIFIED.md` — worse_query results
