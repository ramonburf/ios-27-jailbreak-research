# iOS 27.0.1 (24A446) Jailbreak Research — Implementation Plan
**Target device:** iPhone 17 Pro — iPhone18,1, board V53AP, A19 Pro (t8150)
**Host firmware:** 27.0.1 build 24A446 (device already on it; unsigned, do not update)
**Reference repo:** https://github.com/AzozzALFiras/iOS-Research (studies iPhone17,2/d94ap — all device-specific findings must be re-verified on t8150)

---

## 0. Honest scope

This plan produces: a reproducible research toolchain, the t8150 device map, dynamic
reachability verdicts on two leads, and a scoped entry-point hunt. It does NOT guarantee
a jailbreak — that requires an unpatched, reachable memory-corruption bug, which is an
open research problem. Every phase ends in a GATE: proceed / pivot / stop.

---

## Phase 0 — Environment (1 day)

**Goal:** working toolchain on a Mac or Linux host.

- Install: `ipsw` CLI (blacktop), Ghidra (with headless support), Python 3.11+, clang
  with arm64e target, git.
- Optional but recommended: Corellium account (A17/A18 images) as a sacrificial dynamic
  target so the daily phone is not the first test bed.
- **Acceptance:** `ipsw version` runs; Ghidra headless executes a trivial script;
  `clang -target arm64e-apple-ios` compiles a hello-world.

---

## Phase 1 — Firmware acquisition & baseline receipts (1–2 days)

**Goal:** own the firmware and verify which repo findings even apply to t8150.

1. Download IPSWs (do this FIRST — 24A446 is unsigned and mirrors rot):
   - iPhone18,1 27.0.1 (24A446) — primary target
   - iPhone18,1 27.2 (24B119) and 27.3 beta (24C5037i) — for patch-diffing
2. Extract per build: kernelcache, SPTM, TXM, DeviceTree (V53AP), dyld cache, rootfs.
3. Reproduce baseline measurements (repo `diffs/evidence/` style, one markdown
   receipt per claim with the exact command): SPTM/TXM versions + sizes, exclave
   bundle size, kernelcache size.
4. **GATE 1 — DeviceTree GMMU-TLBI check:**
   `ipsw fw dtree DeviceTree.v53ap.im4p | grep -i gmmu`
   - `verify-gmmu-tlbi...` ABSENT → the repo's persistent defense-in-depth gap is live
     on your device; SPTM lead survives (still needs dynamic confirmation).
   - PRESENT → that lead is dead on t8150; SPTM work mostly de-prioritizes.
5. **GATE 2 — AGX kext diff:** patch-diff the A19 Pro GPU kext 27.2→27.3β. Does the
   channel-index OOB read (fixed in 27.3β per the repo's d94ap finding) exist on
   t8150? Note the A19 Pro GPU differs from A18 Pro — this is a fresh diff, not a lookup.

**Deliverables:** `/firmware/` tree; `verification/baseline-receipts.md`; GATE 1 and
GATE 2 verdicts recorded in `STATUS.md`.

---

## Phase 2 — Re-derive the t8150 kernel map (3–5 days, fully static — Claude does this)

**Goal:** every device-specific number from the repo, re-derived on iPhone18,1's
27.0.1 kernelcache, each with a reproduction command.

- `proc_task` layout: element size, zone-id, `task = proc + offset` (repo says 0x768,
  zone-id 0x1a on d94ap — verify, don't assume).
- `zone_require`/`zone_id_require` site count; metadata anchor location
  (CTRR-locked?) vs metadata array (writable?).
- RO-zone write path: confirm `sprr_pperm_el1` flip idiom is a plain EL1 `msr`
  (data-only boundary) on t8150.
- `zalloc_ro_mut` slid + unslid address (repo corrected value is for d94ap — re-derive).
- Exclaves: confirm PAN-only cL4 capability protection exists on t8150
  (0 `msr pan` / `ldtr` / `sttr` in the cL4 kernel).

**Method:** follow the repo's `methodology/verification-guide.md` (function-body
normalized diffing; string-xref for stripped monitors). Write results to
`map/t8150-map.md` — this file becomes the single source of truth for later phases.

---

## Phase 3 — Dynamic reachability harness (1–2 weeks; needs your device or Corellium)

**Goal:** turn the two static leads into reachable/not-reachable verdicts.

- Adapt the repo's `27.0.1/iokit-fuzzing/` sandbox enumerator for t8150: enumerate
  IOKit classes, identify GPU/AGX user clients, check entitlement requirements.
- Build a minimal dev-signed test app (Xcode, free 7-day cert is fine) that probes
  AGX user-client selectors from (a) an unsandboxed app and (b) the app sandbox.
- Safety layers (from the repo): adaptive blocklist, circuit breaker, thermal guard —
  this runs on a daily phone; a panic reboots it and there's no remount yet.
- Collect crash logs (`.ips`) and symbolicate against the 27.0.1 kernelcache.
- **GATE 3:** AGXG17P channel-index path reachable without entitlement? If yes →
  escalate to a full exploit-dev phase. If no → drop Lead A.
- GMMU-TLBI race: realistically Corellium-only (needs SPTM-level timing). If no
  Corellium: record as unconfirmed, move on — do not burn time on static inference.

**Deliverables:** `harness/` repo with the enumerator + probe app; reachability
report per lead.

---

## Phase 4 — Entry-point hunt (open-ended — the hard gate)

**Goal:** a fresh, unpatched, reachable memory-corruption bug. Until Phase 3 GATE 3
or a new bug lands here, Phases 5+ do not start. Prioritized static targets, in order:

1. **Kext lifetime analysis** (UAF/type-confusion — highest value, repo explicitly
   hadn't reached it): pick 3–5 kexts with complex object lifecycles reachable from
   app sandbox; trace alloc/free/retain paths in Ghidra.
2. **GPU driver (AGX/AGXG17P)** — new silicon, less combed than media parsers.
3. **Unaudited exclave services** (roottask etc.) — diminishing returns expected.
4. **Remaining ImageIO decoders** (PSD/KTX/KTX2/BC) — lowest priority, saturated.

Churn heuristic: silently-patched-in-27.3β functions on t8150 = bug signatures worth
reverse-engineering (same method as the repo's 27.2→27.3 find).

---

## Phase 5 — Exploitation chain (only after a confirmed reachable bug)

Ordered by dependency, each stage gated on the previous:

1. Reliable primitive from the confirmed bug (infoleak → then R/W).
2. PAC strategy for the primitive (call-oriented? data-only?).
3. Cross the RO wall: resolve the repo's open Q3 — a PAC-defeating call primitive to
   `zalloc_ro_mut` with dst = an RO element you own + forged src.
4. Escalate to root/tfp0; then decisions on persistence (SPTM/TXM make reboot-
   persistent jailbreaks a research project of their own — expect "rootless, per-boot"
   as the realistic ceiling).
5. Package (rootless-style) only after 1–4 exist.

---

## How to use Claude on this plan

- Feed Claude ONE phase at a time, plus: this file, the reference repo URL, the
  `/firmware/` paths, and `map/t8150-map.md` as it grows.
- Require from Claude every session: runnable scripts, a markdown receipt per claim
  (command + observed output), and updates to `STATUS.md`. No prose-only results.
- Static phases (1, 2, 4) run entirely in Claude's sandbox — point it at extracted
  binaries. Phase 3 requires you to run binaries on your phone; Claude writes, you run,
  you paste back logs.
- Hard rule: if a phase's gate fails, do not let Claude proceed to dependent phases —
  that's how you avoid paying for a chain that starts from nothing.
