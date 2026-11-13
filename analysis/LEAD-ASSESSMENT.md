# Lead assessment — iOS 27.0.1 (24A446), iPhone18,1 / t8150

Date: 2026-11-07
Target: iPhone 17 Pro, iPhone18,1, board V53AP, A19 Pro (t8150), iOS 27.0.1 build 24A446
Scope rule: no firmware writes, restores, updates, boot-chain changes or downgrades.

This supersedes the informal ranking discussed on 2026-11-07. It states, for
each lead, **what the repo actually proves**, what it does not, and what the
next falsifiable step is.

---

## 0. Ranking summary

| # | Lead | Primitive class | Reachability | Severity ceiling | Verdict |
|---|---|---|---|---|---|
| 1 | **IOGPU / Metal F1 cross-object GPU overlap** | **write** (cross-object, GPU VA) | **not reproduced on t8150** (proven on A16/27.3β only) | kernel R/W if escalated | **demoted — unreachable on t8150 (§10)** |
| 2 | **Kext lifetime / UAF / type confusion** | unknown (hopes for write) | unknown — unexamined | unknown | **top — static, cheap to start** |
| 3 | AGXG18P channel-index OOB read | 1-bit read oracle | **blocked** by private entitlement | read-only, low | demoted — gated *and* low ceiling |
| 4 | GMMU-TLBI DeviceTree gap | race (TLB invalidate) | confirmed property-absent | needs SPTM-level timing | real but hardware-blocked |
| 5 | TXM loop-counter diff | none | — | — | hardening, not a bug |
| 6 | Exclave services / ImageIO decoders | unknown | — | — | saturated, lowest priority |

The change from the earlier ordering is #1. The AGXG18P lead was the most
*developed* on paper, but development effort is not the same as exploitability.

---

## 1. Lead #1 — IOGPU / Metal F1 cross-object GPU overlap

### Evidence

`analysis/f1/F1-PRIMITIVE-EVIDENCE.md` (full transcript + frame index).
Source: user-supplied screen recording of the F1 Game Trainer probe.

### What is established

* An ordinary sandboxed app can `IOServiceOpen(IOSurfaceRoot)` and create an
  IOSurface through an IOGPU user client with **caller-controlled** tile
  geometry — including `headerPerSlice = 0x40000000` — via a 1751-byte in-band
  XML payload and a `0xc68`-byte output descriptor whose offset `0x00` is the
  surface's **kernel backing pointer** and whose offset `0x48` is the `ARGB`
  pixel-format FourCC.
* `IOSurfaceLookup` (userspace, unprivileged) yields the surface's **kernel
  backing pointer** (`base = 0x104924000`).
* A Metal compute kernel bound to the wrapped surface provides GPU-VA
  read/write with a marker round-trip, bounded to the 0x10000-byte allocation
  (a write at `idx=0x100000` is silently dropped).
* By steering the surface's mapping, a write issued against the F1 surface
  lands in a **different** GPU allocation: `*** CROSS-OBJECT HIT ***`,
  `hits=1`.

### What is *not* established, and why it still ranks first

Everything above was observed on **iPhone15,3 / A16 Pro / T8120 / iOS 27.3.0
beta (24C5037i)**. Our target is **A19 Pro / t8150 / iOS 27.0.1 shipping**.
Two facts cut in favour of porting:

* 27.3 *beta* normally carries **fewer** fixes than the 27.0.1 shipping
  release, so a live bug in the beta is expected to still be live in 27.0.1.
* The primitive is a **write**, reachable unprivileged. It is categorically
  stronger than every other lead on this list.

The open question is narrow and **static**: does the same IOSurface/IOGPU
geometry knob exist, and still alias, in the t8150 kernelcache we already
hold?

### Next falsifiable step

1. Locate the IOKit service that implements the `IOSurfaceRoot` / F1 path on
   t8150 in `firmware/24A446/kernelcache.release.macho` (the fileset member
   list is in `analysis/evidence/kernelcache-kexts-27.0.1.tsv`; the scoping
   run in `analysis/kext-scope/` adds a GPU/IOSurface-string column).
2. Find the IOSurface-creation user-client method that consumes
   `headerPerSlice` / `tileRow` / `dataPerSlice`, and confirm the 0xc68-byte
   output layout (kernel base pointer at `+0`, surface id at `+0x18`,
   alloc size at `+0x20`, `ARGB` at `+0x48`) exist on t8150. Note: an earlier
   revision said `ASGR`; the bytes are `ARGB`.
3. Only then build a device probe — and build it against the **secondary**
   device, with crash-log pulling and reboot/respring watch active.

### Honest caveat

This lead's provenance is a **game-cheat tool**. The primitive is real and is
the security-relevant content; the product use is not. Nothing in this repo
should be aimed at producing a cheat. The research question is whether the
same GPU-heap aliasing can be escalated into a *kernel* primitive on our
target — that is the path to the jailbreak goal, and it is a different
technical problem from the trainer's cross-process game-memory read/write.

---

## 2. Lead #2 — Kext lifetime / UAF / type confusion

### Evidence

`ios-27.0.1-jailbreak-plan.md` Phase 4 item 1 explicitly ranks this first
and notes the reference repo never reached it. The repo's own `analysis/` and
`audit/` trees contain **no** kext lifetime work — so this is genuinely
untouched search space, not a re-tread.

### Scoping tool

`analysis/kext-scope/scope_kexts.py` parses the 27.0.1 kernelcache
MH_FILESET (301 members) and scores every kext on:

* **reach** — presence of `IOUserClient` / `IOExternalMethodDispatch` /
  `externalMethod` / `getTargetAndMethodForIndex`, minus penalties for
  `com.apple.private.*` entitlement gating;
* **life** — alloc/free/retain/release/terminate/collection/descriptor
  strings, i.e. where a lifetime bug could plausibly live.

Results: `analysis/kext-scope/kext-scope.tsv`,
`analysis/evidence/kext-scope-27.0.1.txt`.

### Two methodology findings (both were bugs in the first implementation)

* The `LC_FILESET_ENTRY` name field is at **+32**, not +28. At +28 the name
  reads as empty (it is the `reserved` word).
* Kernelcache fileset members are **prelinked**: `LC_SEGMENT_64` file offsets
  are **absolute** into the kernelcache, not relative to the member's own
  start, and a **single `__LINKEDIT` is shared by all 301 members**. Naively
  taking "max end of segments" as a member's size yields the whole 78 MB
  kernelcache for every member, and scanning `__LINKEDIT` attributes every
  kext's symbols to every kext. Strings must be taken from each member's own
  segments with `__LINKEDIT` excluded.

### Next falsifiable step

Take the top-ranked sandbox-reachable kexts from the scoping output and, for
each, trace alloc → free → retain/release paths and look for a path where a
freed object remains reachable. This is the classic UAF shape; it needs no
device until a candidate exists.

---

## 3. Lead #3 — AGXG18P channel-index OOB read (demoted)

### Evidence

* `analysis/agx/AGXG18P-CHANNEL-INDEX.md` — the unchecked sequence at
  `0xfffffe0008556f54` confirmed live in the 27.0.1 kernelcache.
* `extraction/extraction/analysis/agxg18p-reachability-result.md` — the
  dynamic verdict.
* `analysis/evidence/2026-11-06-iokit-service-enumeration.log` — raw service
  enumeration (1542 IOKit services; only `AGXAcceleratorG18P` is openable,
  and only with `IOServiceOpen(type=1)`).

### Why it is demoted rather than deleted

The lead is **not** dead — it is **gated**, and it is **low-ceiling**:

* `0x109` / `0x10d` require `com.apple.private.agx.performance-spi`
  (`0xfffffe0007135bdb`), which the dev-signed app cannot hold.
* `0x105` commands `0..0xa` require exclusive ownership, which only
  `0x109` can grant.
* The one reachable selector that accepts a shape, `0x110`, takes **8 bytes**,
  while the OOB helper needs a **16-byte** `{index, mask}` input. The shapes
  do not meet.

Even if the gate were bypassed, the primitive is an **OOB read of an 8-byte
pointer slot** whose only observable is one bit (bit 5 of a byte), followed by
a wild-pointer dereference. That is a 1-bit oracle and a crash hazard — not a
write primitive. On its own it could never carry a jailbreak chain.

### Why it is not worth more time right now

Lead #1 is a write primitive in the same subsystem with a proven unprivileged
path. If the F1 geometry knob exists on t8150, that is where the leverage is.
The AGX lead becomes worth revisiting only if #1 is ported and escalated and
one specifically needs a *read* primitive.

---

## 4. Lead #4 — GMMU-TLBI DeviceTree gap (confirmed, hardware-blocked)

### Evidence

`audit/REPORT.md`:
> Parsed both v53ap DeviceTrees into JSON. Neither contains a property named
> `verify-gmmu-tlbis-at-sync`. Both include `issue-gmmu-tlbis-at-retype=1` at
> the sgx node and `tlbi-flushes-smmu` on three display DART nodes.

GATE 1 of the plan passed: the reference repo's persistent defense-in-depth
gap is **live on t8150**. This is a genuinely confirmed, non-speculative
finding.

### Why it is blocked

The plan (Phase 3) is explicit that exploiting a TLB-invalidation race
requires SPTM-level timing control and is "realistically Corellium-only".
Without that hardware the lead is *recordable but not advanceable*. It also
has no defined route to a useful primitive on this hardware, and a race
primitive under SPTM is a research project in itself.

**Verdict:** keep the receipt, do not spend more time on it.

---

## 5. Lead #5 — TXM loop-counter diff (not a vulnerability)

`audit/TXM-REVIEW.md` documents one manually checked region where 27.2 adds an
explicit loop counter with limit `0x10` and returns an error on exhaustion.
That is **hardening**, not a bug — it adds a bound where there was none. The
audit already states that "reachability, security impact and subsystem
identity remain unproven", and that the byte differences are not confined to
metadata.

**Verdict:** not a lead. It is a reminder that cross-build byte differences
need semantic review before they can be called anything.

---

## 6. Lead #6 — Exclave services / ImageIO decoders

The plan itself ranks these last ("diminishing returns", "saturated"), and
nothing in `extraction/` or `audit/` contradicts that. The shared caches that
would hold the media parsers are only partially extracted
(`analysis/ios/dsc/...` has the main `dyld_shared_cache_arm64e` and the
DriverKit/ExclaveOS caches; the 27.2 copy is still blocked by the
go-apfs-v2 B-tree/object-map issue).

**Verdict:** leave at the bottom.

---

## 7. Sequencing

1. **Static now, no device contact:**
   a. Locate the t8150 IOSurface/IOGPU user client and the `headerPerSlice`
      / tile-geometry handling; compare against the A16 behaviour recorded in
      `analysis/f1/F1-PRIMITIVE-EVIDENCE.md`.
   b. Run the kext lifetime scoping to a shortlist and start tracing alloc/free
      paths on the top sandbox-reachable candidates.
2. **Device, secondary unit only, controlled harness first:** a minimal
   read-only IOSurface probe that only *reports* geometry and backing
   addresses — no writes, no overlap attempts — with crash-log pulling and
   reboot/respring watch armed.
3. **Only after a write primitive is demonstrated on t8150:** escalate to a
   kernel read/write primitive, then to Phase 5 (PAC strategy, RO wall,
   root/tfp0).

## 8. Standing safety rules (unchanged)

* Target device is the secondary iPhone, UDID `<device-udid>`;
  never a daily driver.
* No firmware writes, restores, updates, boot-chain changes or downgrades.
* Device interaction stays read-only/benign until a signed controlled harness
  exists. Stop immediately on app crash, SpringBoard respring or device
  reboot, and pull crash logs before continuing.
* All scratch, downloads and temp artifacts live on `G:` under
  `tools/opencode-temp/`; nothing is written to `C:`.

---

## 9. Update 2026-11-08 — Lead #1 status change

The three "next falsifiable steps" in §1 and §7.1–7.2 have now been executed.

### Done

* The t8150 / 27.0.1 IOSurface kext has been located, extracted and
  disassembled (`analysis/f1/extract/com.apple.iokit.IOSurface`, sha256
  `8c218044…f93f`). It **does** contain `headerPerSlice` / `dataPerSlice` /
  `sliceCount` parsing.
* A signed, installed, running device harness now exists
  (`analysis/evidence/mac/build-and-sign-2026-11-08.md`), and four read-only
  geometry probes have been run (`analysis/f1/GEOMETRY-PROBE-RESULTS.md`).
* IOSurface allocations of equal size are contiguous with an exact `0x10000`
  stride and no guard page.

### What changed

The F1 path is **not reachable through `IOSurfaceCreate`**. libIOSurface does
not forward the private per-slice keys (or the keys that gate their validation)
to `IOSurfaceRoot`; the kernel parser is never entered. Probe v4 confirmed this
directly: cases that must reject if the parser ran were accepted.

The kext *does* contain a genuine 32-bit overflow in the gated path
(`(data + header) * sliceCount` computed in `w` registers, then compared against
the allocation), but it is unreachable from the API we can currently call.

### Consequence for the ranking

Lead #1 remains first, but its next step is no longer "port the geometry knob".
It is: **reproduce the A16/27.3β route — drive the `IOSurfaceRoot` user client
directly with a serialized property dictionary — because that is the only path
that reaches the kernel parser.** That is a larger step than a probe and should
be treated as a new sub-lead with its own gate.

If the direct user-client route also fails to reach the parser, Lead #1 should
be demoted below the kext lifetime work (Lead #2), which is still unexamined.

---

## 10. Update 2026-11-08 (later) — the direct route failed; Lead #1 demoted

The condition in §9 has been met. Probes v5–v7 drove the `IOSurfaceRoot` user
client directly (`analysis/f1/GEOMETRY-PROBE-RESULTS.md` §9; raw logs
`analysis/evidence/mac/geom5.log`, `geom6.log`, `geom7.log`).

### Result

* `IOServiceOpen("IOSurfaceRoot", type 0)` succeeds (`kr=0`).
* `IOConnectCallMethod(selector 0, ...)` returns `0xe00002c2`
  (`kIOReturnBadArgument`) for **all** of:
  * scalar input counts 0 and 1, with scalar values `{payload length, 0, 1}`;
  * XML plist, NUL-terminated XML, binary plist, stripped `<dict>`, stripped+NUL;
  * `u32`/`u64`/zero length-prefixed payloads;
  * structure output buffer `0xc68`.
* A selector sweep `1..5` also returns `0xe00002c2` for every selector.

The error is payload-independent, so it is an input-shape or precondition
rejection, not an XML parsing failure. Static inspection of the dispatch table
(`__DATA_CONST` file `0x46630`, entry stride `0x28`) says selector 0 wants
`scalarInputCount=1`, `structureInputSize=0xffffffff` (variable),
`structureOutputSize=0xc68` — which v6 supplied — but the arm64e function
pointer could not be resolved to a `bti c` prologue, so the table may be partly a
vtable and the selector numbering may not map the way assumed.

### What is *not* established

* That selector 0 is the create method on t8150.
* That open type 0 instantiates the `IOSurfaceRootUserClient` subclass that
  implements create.
* That any payload could reach the kernel per-slice parser through this service.

### Revised ranking

| # | Lead | Status |
|---|---|---|
| 1 | **Kext lifetime / UAF / type confusion** | **top — unexamined, static, no device needed** |
| 2 | IOGPU / Metal F1 cross-object overlap | **demoted — no reachable path found on t8150** |
| 3 | AGXG18P channel-index OOB read | demoted — entitlement-gated, 1-bit read |
| 4 | GMMU-TLBI DeviceTree gap | hardware-blocked |
| 5 | TXM loop-counter diff | not a bug |
| 6 | Exclave / ImageIO | saturated |

### Next step

Move to Lead #2 as the primary line:

1. From `analysis/kext-scope/kext-scope.tsv`, take the highest-scored
   sandbox-reachable kexts (IOUserClient present, no `com.apple.private.*`
   gate, lifetime strings present).
2. For each, trace alloc → retain → release → free on the reachable
   `externalMethod` selectors, looking for a path where a freed object remains
   reachable.
3. Only when a concrete candidate exists, build a device probe — secondary unit
   only, same safety rules.

Re-opening F1 is a separate sub-task: establish the real selector / client type
first (static, by resolving the dispatch pointer correctly against the
kernelcache rather than the extracted kext), and only then retest. It is not on
the critical path.

---

## 11. Update 2026-11-08 (later still) — measured reachability reorders Lead #2

`kext-scope` ranks by strings, not by whether the sandbox permits an open. A
direct open-only sweep (`analysis/reach/REACHABILITY-2026-11-08.md`, raw
`analysis/evidence/mac/reach.log`) measured it for 1483 services:

| service | result |
|---|---|
| `IOSurfaceRoot` | opens (type 0) |
| `AGXAcceleratorG18P` | opens (type 1) |
| **`AppleJPEGDriver`** | **opens (type 0 and 1)** |
| `AppleDiskImagesController` | `BadArgument` (not a flat denial) |
| `AppleSmartIO` | `BadArgument` |
| `AKSAnalytics` | `NotPrivileged` |
| `AppleSARService` | `NotPermitted` — **closed** |

Consequences:

* **`AppleSARService` is dead** despite being the highest-scoring kext. Its 40+
  mapped selectors (`tools/opencode-temp/lifetime-triage/sarnames.txt`) cannot be
  reached by an unprivileged app. Do not spend more time on it.
* **`AppleJPEGDriver` becomes the primary Lead #2 target**: it is reachable on
  both open types and consumes caller-supplied image data.
* `AppleDiskImagesController` / `AppleSmartIO` are only provisionally excluded —
  `BadArgument` means the *shape* was wrong, not that the sandbox refused. They
  should be retried with other open types / arguments before being dropped.

Revised Lead #2 order:

1. `AppleJPEGDriver` — reachable, attacker-data surface.
2. `AppleDiskImagesController`, `AppleSmartIO` — retry open with other types.
3. Everything sandbox-denied — drop.

### AppleJPEGDriver surface (first pass)

`analysis/reach/APPLEJPEGDRIVER-SURFACE.md` records what the static pass
established:

* The user client exposes `startDecoder`, `startDecoderExt`,
  `startDecoder2024` and the three encoder equivalents, all taking a
  caller-supplied `AppleJPEGDriverIOStruct*` (three struct generations).
* `startDecoder` reads caller-controlled fields at `+0x14`, `+0x18`, `+0x30`,
  `+0x48`, `+0x54` before allocating driver state, but also performs explicit
  `newHeaderSize` bounds/alignment checks. **No bug is claimed.**
* The class sets `IOUserClientEntitlements` in `start`, which is in tension with
  the observed successful `IOServiceOpen`; the gate's scope is unresolved.
* The selector dispatch table has **not** been located: chained-fixup encodings
  of the six method starts do not appear in any section, so the table is
  stub-mediated or built at runtime. Until it is found, no selector can be
  called.

Next static steps: recover the dispatch table via `__auth_stubs`, reconstruct
the three input structs, then decide whether a controlled argument-free selector
probe is warranted.

---

## 12. Update 2026-11-08 (later still) — AppleJPEGDriver dispatch table RECOVERED

The §11 "Next static steps" item 1 is now **done**, and the resulting surface is
substantially more actionable than the "no vulnerability claimed" status suggested.

### What was found

* The `AppleJPEGDriverUserClient` vtable pointer is stored at
  `0xfffffe00080dd320`; the static dispatch table sits immediately after the vtable
  in `__DATA_CONST.__const` at `0xfffffe00080dd990`, with **10 entries × 40 bytes**.
* The kernel core that consumes it
  (`sub_fffffe000b37475c`, reached from the user client via
  `__stub_fffffe000b8acf58`) reads, from the `IOUserClientMethodDispatch` entry:
  fn @ +0, checkScalarInputCount @ +8, checkStructureInputSize @ +0xc,
  checkScalarOutputCount @ +0x10, checkStructureOutputSize @ +0x14.
* The user client passes the table plus `dispatchCount = 0xa`.

### Recovered dispatch table

| sel | dispatch fn | resolved codec fn | structIn | structOut | gate |
|---|---|---|---|---|---|
| 0 | `0x9016358` | `0x900a73c` | 0 | 0 | – |
| 1 | `0x9016364` | **`0x900bdf4` = startDecoder`** | **0x58 (88)** | **0x58 (88)** | – |
| 2 | `0x9016398` | `0x900a748` | 0 | 0 | – |
| 3 | `0x90163a4` | **`0x900d094` = startEncoder`** | **0x58 (88)** | **0x58 (88)** | – |
| 4 | `0x90163d8` | **`0x900d4a8` = startEncoderExt`** | **0x1000 (4096)** | **0x1000 (4096)** | – |
| 5 | `0x901640c` | **`0x900c8f8` = startDecoderExt`** | **0x1000 (4096)** | **0x1000 (4096)** | – |
| 6 | `0x9016440` | **`0x900dfac` = startEncoder2024`** | **0xda0 (3488)** | **0xda0 (3488)** | flag @ entry |
| 7 | `0x9016474` | **`0x900d90c` = startDecoder2024`** | **0xda0 (3488)** | **0xda0 (3488)** | flag @ entry |
| 8 | `0x90164a8` | `0x9009ba4` | 4 | 0 | **gated** (`com.apple.applejpegdriver.poweron`) |
| 9 | `0x90164d8` | `0x9009c3c` | 0 | 0 | **gated** |

The wrappers branch directly into the `start*` bodies (`b 0xfffffe000900bdf0`
for decoder, etc.), passing
`driver = [userClient + 0xe0]`, `structIn = args->structureInput`,
`structOut = args->structureOutput`, `mach_port = [userClient + 0xf0]`,
`task = [userClient + 0x100]`.

The earlier stale note (`sel=0x1ff`) is now understood to come from a different
table / mislabelled entry and is contradicted by the code path actually taken.

### Consequence

The codec path is **callable without any `com.apple.private.*` entitlement** for
selectors 1–7. This makes `AppleJPEGDriver` the only known static surface on this
device that (a) an unprivileged sandboxed app can open, and (b) consumes
caller-supplied bulk image data and drives a codec engine. It is now unambiguously
the primary Lead #2 lead, ahead of the AGX demoted leads, and ahead of any
"future" vulnerability we might hope for.

The next research question is no longer "is it reachable?" but **"is the struct
path the vulnerability?"** — specifically whether any field of `AppleJPEGDriverIOStruct*`
is used as a length/offset without validation.

### Next step

Reconstruct the three input structs (`IOStruct` = 0x58, `IOStructExt` = 0x1000,
`IOStruct2024` = 0xda0) from the `start*` bodies, then build a controlled,
argument-shaped probe. No device writes are required for this step; the probe only
needs the struct field offsets and the check functions.

---
