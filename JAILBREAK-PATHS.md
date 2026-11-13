# Jailbreak paths — completion by path

Updated: 2026-11-13. Target: iPhone 17 Pro, iOS 27.0.1 (24A446).

Same percentage convention as `PROGRESS.md`: **how far along that path is toward being a
working part of the chain**, not the probability it eventually works. 100 % means done and
verified on hardware. A path can be at 90 % and still be dead (for example, entitlement-gated).

Overall jailbreak readiness: **~30 %**. Stage 1–3 (target acquisition, reachability map,
vulnerability identification) are done; the whole remaining risk sits in turning a bug into
kernel R/W and then getting past PAC/CTRR/SPTM.

## Paths

| # | Path | Primitive | Reachable | % | Status |
|---|------|-----------|-----------|---|--------|
| 1 | **CVE-2026-112514 socket-buffer UAF** | UAF write | yes — plain `socket()` | **80 %** | **Race won on hardware.** 20 confirmed stale writes into reallocated sockets, first at iter 9. Conversion to controlled R/W not started. |
| 2 | AppleJPEGDriver struct surface | unknown (bulk image input) | yes — opens type 0/1 | **40 %** | Dispatch table recovered, selectors 1–7 callable with no entitlement. Structs partly reconstructed. No bug found yet. |
| 3 | IOSurface notify UAF family (CVE-2026-112517 / -112516 / -112477) | UAF | yes — `IOSurfaceRoot` opens type 0 | **25 %** | Bug site confirmed in the 27.0.1→27.2 diff. PAC/type-confusion constraints unresolved. |
| 4 | IOHIDFamily OOB R/W (CVE-2026-112507) | OOB read/write | unproven | **20 %** | Patch confirmed in diff. No sandbox-openable HID user client identified. |
| 5 | Diff-derived kernel UAF candidates (542 changed kernel funcs) | unknown | unknown | **15 %** | Triage list produced; state-byte check clusters unmapped. No candidate confirmed. |
| 6 | IOGPU / Metal F1 cross-object GPU overlap | GPU write into another allocation | **no** on t8150 | **35 %** | Primitive proven on A16/27.3β. Direct `IOSurfaceRoot` user-client route returns `kIOReturnBadArgument` for every shape; parser never entered. |
| 7 | AGXG18P channel-index OOB read | 1-bit read oracle | entitlement-gated | **45 %** | Unchecked sequence confirmed live. Needs `com.apple.private.agx.performance-spi`; shapes for the one reachable selector do not match. |
| 8 | GMMU-TLBI DeviceTree gap | TLB-invalidation race | yes | **15 %** | Gap confirmed absent in both v53ap DeviceTrees. Needs SPTM-level timing, realistically Corellium-only. |
| 9 | Exclave / ImageIO decoders | parser corruption | yes | **10 %** | Saturated surface; shared caches only partly extracted. No concrete lead. |
| 10 | TXM loop-counter diff | — | — | **5 %** | Hardening, not a vulnerability. Kept as context for the post-R/W stage. |

## Downstream stages (shared by every path)

| Stage | % | Status |
|---|---|---|
| KASLR slide oracle (timing) | **60 %** | Referenced as `z=7.67` in `analysis/references/SOCKET_UAF_ANALYSIS.md`; not yet documented or re-verified against 27.0.1. |
| Kernel R/W conversion | **5 %** | Only the socket-UAF write primitive exists so far; no controlled overlap, no leak, no read. |
| EL1 code exec past PAC / CTRR / SPTM (TXM trustcache) | **5 %** | Not started. |
| Credential patch + rootless bootstrap (package manager) | **5 %** | Not started. |

## Path detail

### 1. Socket UAF — CVE-2026-112514 (primary)

Where the 80 % comes from:

- Bug identified and root-caused to the inlined `sb*` helpers in `uipc_socket2.c`; 27.2
  de-inlines them and adds the `so_usecount > 0` / defunct checks (`analysis/references/SOCKET_UAF_ANALYSIS.md`).
- Carrier `--sockuaf` runs five variants from a detached, persistent-worker harness
  (`analysis/evidence`, `analysis/socket-uaf-hammer-2026-11-13.md`).
- **Decisive oracle built and passed**: freshly connected, never-sent spray sockets behind a
  dedicated listener. A byte arriving at a peer can only come from a stale sender. 20 hits,
  8–24 KiB each, at iterations 9, 14, 19, 29, 34 … — a real stale kernel write.
- Kills solved: SIGPIPE, the 0x8BADF00D MainActor watchdog, thread churn.

The remaining 20 %:

- The freed `struct socket` is reclaimed by another *socket*, not by an attacker-controlled
  buffer. A socket-to-socket stale write alone is not R/W.
- Need a controlled reallocator in the same zone (or cross-zone page exhaustion) so the stale
  write lands in attacker-shaped data.
- Need a leak (KASLR + heap address) to boot the fake-object chain.
- No panic/corruption yet — the writes are harmless because the overlapping object is the same
  type.

Next falsifiable step: reclaim the freed slot with a *non-socket* object of the same zone size,
or with a deliberately shaped socket whose overwritten fields are observable (`so_proto` /
`so_pcb`), then prove one field of the stale write is ours.

### 2. AppleJPEGDriver

40 %: open confirmed on types 0 and 1; vtable and 10-entry dispatch table recovered at
`0xfffffe00080dd320` / `0xfffffe00080dd990`; selectors 1–7 (`startDecoder`, `startEncoder`,
`startDecoderExt`, `startEncoderExt`, `startDecoder2024`, `startEncoder2024`) accept 0x58 /
0x1000 / 0xda0-byte caller structs with no `com.apple.private.*` gate
(`analysis/LEAD-ASSESSMENT.md` §12). Structs partly reconstructed.

Missing: the actual bug. No validation flaw yet; 0x58/0x1000/0xda0 paths only partly traced.

### 3–5. Other diff-derived kernel bugs

Bug sites are confirmed in the binary diff but none is converted. IOSurface is the furthest
(25 %) because the fix is exactly two instructions; it is also the most PAC-constrained.

### 6–8. Demoted paths

Kept because each has a proven primitive or a confirmed property gap, but each is blocked by a
specific external condition (unreachable parser, entitlement, SPTM timing).

### 9–10. Long tail

No concrete candidate; recorded so the search space stays visible.

## Priority

1. Socket UAF conversion (path 1) — only live primitive, and it is already reliable enough to
   produce hits on demand.
2. AppleJPEGDriver struct review (path 2) — best untouched static surface.
3. IOSurface notify family (path 3) — strongest fallback if socket conversion stalls.
4. Everything else stays parked.
