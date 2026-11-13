# User-client reachability from a plain sandboxed app — 2026-11-08

**Device:** iPhone18,1 / iPhone 17 Pro / t8150 — iOS 27.0.1 (24A446), UDID
`<device-udid>`
**Harness:** signed debug app `com.<your-bundle-id>`
**Raw log:** `analysis/evidence/mac/reach.log`

## Why this measurement exists

`analysis/kext-scope/kext-scope.tsv` ranks kexts by **string presence**, not by
whether the sandbox lets an app open their user clients. The AGX work already
showed the gap: the top-scoring entries are not necessarily reachable, and
reachability cannot be inferred from `com.apple.private.*` counts alone.

This probe measures reachability directly. It **only** calls
`IOServiceOpen(type)` and `IOServiceClose(conn)`. It never calls
`IOConnectCallMethod`, never submits buffers, never touches Metal.

Services are matched by `IOClass` substring against a curated filter list:
`SAR, Analytics, DiskImage, SmartIO, NVMe, Thunderbolt, JPEGDriver, IOSurface,
IOGPU, AGX, IOHIDFamily, ApNonce`.

## Results

`services=1483 matched=20 reported=10`

| service (`IOClass`) | type 0 | type 1 | decoding |
|---|---|---|---|
| `IOSurfaceRoot` | **OPEN** | — | reachable |
| `AGXAcceleratorG18P` | unsupported | **OPEN** | reachable (type 1 only) |
| `AppleJPEGDriver` | **OPEN** | **OPEN** | **reachable on both types** |
| `AppleDiskImagesController` | `0xE00002C2` | `0xE00002C2` | BadArgument — not a flat sandbox denial |
| `AppleSmartIO` | `0xE00002C2` | `0xE00002C2` | BadArgument |
| `AKSAnalytics` | `0xE00002C1` | `0xE00002C1` | NotPrivileged |
| `AppleSARService` | `0xE00002E2` | `0xE00002E2` | **NotPermitted — sandbox denied** |
| `AppleMobileApNonce` | `0xE00002E2` | `0xE00002E2` | NotPermitted |
| `CoreAnalyticsHub` | `0xE00002C5` | `0xE00002BC` | ExclusiveAccess / Error |
| `KDIDiskImageNub` | `0xE00002BD` | `0xE00002BD` | NoMemory |

Error-code reference:

| value | meaning |
|---|---|
| `0xE00002C1` | `kIOReturnNotPrivileged` — client-side privilege check |
| `0xE00002C2` | `kIOReturnBadArgument` — open arguments/type rejected |
| `0xE00002C5` | `kIOReturnExclusiveAccess` |
| `0xE00002E2` | `kIOReturnNotPermitted` — sandbox denial |
| `0xE00002BC` | `kIOReturnError` |
| `0xE00002BD` | `kIOReturnNoMemory` |
| `0xE00002C7` | `kIOReturnUnsupported` — no user client of that type (not logged) |

## Interpretation

1. **`AppleSARService` — the highest kext-scope score (119 556) — is not
   reachable.** The sandbox returns `kIOReturnNotPermitted`. Its 40+ mapped
   selectors (`tools/opencode-temp/lifetime-triage/sarnames.txt`) are therefore
   irrelevant to an unprivileged chain. This is exactly the error the
   string-based scoping could not predict.

2. **`AppleJPEGDriver` is reachable on both open types.** It is the first
   non-GPU, non-IOSurface user client confirmed openable by a plain app. It is a
   hardware JPEG codec driver, i.e. an attack surface that consumes
   caller-supplied image data — the kind of surface where memory-safety bugs are
   worth looking for.

3. `AppleDiskImagesController` and `AppleSmartIO` return `BadArgument` rather
   than a sandbox denial, so they are **not** ruled out: a different open type or
   a correctly-shaped argument may reach them. Recorded, not pursued yet.

4. `IOSurfaceRoot` and `AGXAcceleratorG18P` reproduce the earlier findings
   exactly, which validates the method.

## Probe bug encountered (and fixed)

The first v8 run crashed. The crash was **in the probe, not the kernel**:

```
EXC_BAD_ACCESS (SIGSEGV) at 0x92a0dbb9aef21130
  _platform_strlen
  __CFStringAppendFormatCore
  String.init(format:_:)
  ReachViewModel.tryOpen(...)
```

Cause: `String(format: "... [uc=%s]", ..., uc)` passed a Swift `String` for
`%s`. Swift bridges `String` to `NSString`, so CF read an object pointer as a
C string and called `strlen` on it. Fixed by using `%@` with `uc as NSString`.

Crash report preserved at
`analysis/evidence/mac/AGXProbe-2026-11-08-151733.ips`. The device did not
reboot; this was a userland app crash only.

## Consequence

Lead #2's shortlist must be re-ordered by **measured reachability**, not score:

1. **`AppleJPEGDriver`** — reachable, consumes attacker data. Primary.
2. `AppleDiskImagesController`, `AppleSmartIO` — BadArgument; retry with other
   open types before discarding.
3. `AppleSARService`, `AKSAnalytics`, `AppleMobileApNonce` — closed.
