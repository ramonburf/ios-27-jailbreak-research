# Kext lifetime / UAF scoping — iOS 27.0.1 (24A446), t8150

Phase 4 item 1 of `ios-27.0.1-jailbreak-plan.md`. This directory holds the
triage that narrows 301 kernelcache members down to a shortlist worth tracing
by hand.

| file | what it is |
|---|---|
| `scope_kexts.py` | the triage tool (parses the MH_FILESET, scores every member) |
| `kext-scope.json` | machine-readable per-kext signals |
| `kext-scope.tsv` | one row per kext, tab-separated |
| `scope-run.log` | the run log (per-member progress) |
| `README.md` | this file |
| `LIFETIME-TRIAGE.md` | hand-trace of the shortlist (separate workstream) |

Raw report: `analysis/evidence/kext-scope-27.0.1.txt`.

---

## Results

| metric | value |
|---|---|
| fileset entries parsed | **301** |
| kexts scored | **301** |
| with an `IOUserClient` surface | **92** |
| referencing `com.apple.private.*` | **60** |
| with GPU / IOSurface strings | **33** |

## How the scoring works

```
reach = 6 × (strong user-client signal hits) + (weak signal hits)
      − (4 × com.apple.private.* hit count + 2 × gating-signal hits)
life  = min(alloc signals, 40) + min(free signals, 60)
      + min(refcount signals, 80) + min(lifecycle signals, 120)
score = max(0, reach) × life
```

* **strong user-client signals** — `IOUserClient`,
  `getTargetAndMethodForIndex`, `IOExternalMethodDispatch`,
  `IOExternalMethodArguments`, `externalMethod`, `IOUserClientMethodDispatch`
* **weak signals** — `IOServiceMatching`, `IOServiceOpen`,
  `IOConnectCallMethod`, `publishService`, `IOMemoryDescriptor`, …
* **gating signals** — `clientHasPrivilege`, `clientHasAuthorization`,
  `entitlement`, and a heavy penalty per `com.apple.private.*` string
* **life signals** — alloc/free/retain/release, collection types
  (`OSDictionary`/`OSArray`/`OSSet`), locks, notification ports, command
  gates, and lifecycle verbs (`terminate`/`detach`/`open`/`close`/`destroy`)

The `priv` column in the report is the count of `com.apple.private.*` strings
in that kext — a proxy for "is this service gated". **A low `priv` with a high
`reach` is the interesting quadrant**: an unprivileged app may be able to open
the service.

## Top of the ranking

| score | reach | life | priv | size | kext |
|---:|---:|---:|---:|---:|---|
| 119 556 | 492 | 243 | **0** | 1 439 046 | `com.apple.driver.AppleSARService` |
| 45 000 | 150 | 300 | 153 | 12 941 305 | `com.apple.kernel` |
| 42 483 | 289 | 147 | 1 | 465 442 | `com.apple.driver.AppleSEPManager` |
| 24 747 | 219 | 113 | 4 | 331 357 | `com.apple.driver.AppleProcessorTrace` |
| 21 000 | 70 | 300 | **0** | 2 632 045 | `com.apple.iokit.IOThunderboltFamily` |
| 20 909 | 103 | 203 | 6 | 371 629 | `com.apple.iokit.IOGPUFamily` |
| 19 809 | 213 | 93 | **0** | 113 553 | `com.apple.driver.AppleDiskImages2` |
| 11 560 | 40 | 289 | **0** | 2 964 799 | `com.apple.driver.AppleAVE2` |
| 10 602 | 93 | 114 | **0** | 60 819 | `com.apple.iokit.CoreAnalyticsFamily` |
| 8 127 | 43 | 189 | **0** | 1 635 604 | `com.apple.driver.AppleAVD` |
| 5 880 | 105 | 56 | 1 | 78 424 | `com.apple.driver.ApplePMP` |
| 5 454 | 101 | 54 | **0** | 81 332 | `com.apple.driver.AppleSmartIO2` |
| 5 293 | 67 | 79 | **0** | 294 701 | `com.apple.driver.AppleJPEGDriver` |

`com.apple.kernel` dominating is expected — it is the kernel itself, and its
`priv=153` correctly reflects that it is not an app-reachable service. It is
kept in the table only so the ranking is not silently filtered.

## GPU / IOSurface kexts (relevant to the F1 lead)

| score | reach | gpu hits | size | kext |
|---:|---:|---:|---:|---|
| 20 909 | 103 | **578** | 371 629 | `com.apple.iokit.IOGPUFamily` |
| 254 | 2 | 958 | 1 084 037 | `com.apple.AGXG18P` |
| 76 | 1 | **401** | 273 732 | `com.apple.iokit.IOSurface` |
| 1 848 | 33 | 4 | 235 300 | `com.apple.iokit.IOMobileGraphicsFamily` |
| 0 | 0 | 7 | 241 664 | `com.apple.iokit.IOMobileGraphicsFamily-DCP` |

`com.apple.iokit.IOGPUFamily` is the kext that owns the IOSurface/F1
allocation path described in `analysis/f1/F1-PRIMITIVE-EVIDENCE.md`; it is
present on t8150 with a large user-client surface. `com.apple.iokit.IOSurface`
owns the surface object itself. Both are on the Lead #1 critical path.

---

## Three methodology bugs found and fixed in `scope_kexts.py`

These are worth recording because they silently produce *plausible-looking
but completely wrong* output, and any future kernelcache tooling in this repo
must not repeat them.

1. **`LC_FILESET_ENTRY` name offset.** The name is at **+32**, not +28.
   At +28 you read the `reserved` word, get an empty string, and every kext
   appears nameless.

2. **Prelinked segment offsets.** Kernelcache fileset members are
   **prelinked**: their `LC_SEGMENT_64` file offsets are **absolute into the
   kernelcache**, not relative to the member's own start. Taking
   "max(segment fileoff + filesize)" as a member's size therefore yields the
   whole 78 MB kernelcache for *every* member. The first version of this
   script scored all 301 kexts identically because of this.

3. **Swapped `segment_command_64` fields.** `fileoff` is at **+40** and
   `filesize` at **+48**, after `vmaddr` (+24) and `vmsize` (+32). Reading
   them at +32/+40 (i.e. reading `vmsize` as `fileoff` and `fileoff` as
   `filesize`) produces monotonically-growing garbage sizes — the second
   broken run reported `com.apple.kernel` as **1.2 GB**.

Additionally, **a single `__LINKEDIT` is shared by every one of the 301
members**. Scanning it while attributing strings to one kext means every kext
appears to contain every other kext's symbols. `member_blob()` excludes it
and the report states this.

## What this tool does *not* do

* It is **not** a vulnerability finder. It ranks by string presence, which is
  a proxy for "has a user-client surface and a complicated lifecycle", not for
  "has a bug".
* It says nothing about whether a service is actually openable from the
  sandbox. The `priv` count is a proxy only. The real test is a device probe
  (`IOServiceOpen`) — and that is exactly what the AGX work already showed
  can differ from the static expectation.
* It does not follow data flow, so it cannot see a UAF that spans two kexts.

## Reproduce

```powershell
cd G:\iOS 27.0.1\iOS
python analysis\kext-scope\scope_kexts.py
# -> analysis\kext-scope\kext-scope.tsv
# -> analysis\evidence\kext-scope-27.0.1.txt
```

Takes a few minutes: the `com.apple.kernel` member alone is ~13 MB of text and
every category is a single regex pass over each member's own segments.
