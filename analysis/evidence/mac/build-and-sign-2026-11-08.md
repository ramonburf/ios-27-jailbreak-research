# Signed build + install on t8150 — 2026-11-08

**Host:** Mac `192.168.1.99` (`volpidash`), Xcode 27.2 (27B52)
**Device:** iPhone18,1 / iPhone 17 Pro / t8150 — iOS 27.0.1 (24A446), UDID `00008150-00095CD93444C01C`
**Project:** `~/agx-probe-project` (`AGXProbe`)

## Outcome

| Step | Result |
|---|---|
| Swift compile | **success** |
| CodeSign | **success** (once keychain unlocked in the same SSH session) |
| `devicectl device install app` | **success** |
| `devicectl device process launch` | **blocked — device locked** |

## The signing blocker, resolved

The long-standing `errSecInternalComponent` failure was **not** a broken identity or
profile. It was a session-scoping problem:

* `security unlock-keychain` only unlocks the keychain for the **current security
  session**. Each new SSH connection gets a fresh session, so the keychain was
  locked again by the time `xcodebuild` ran.
* Evidence: an unlock + trivial `codesign` inside *one* SSH command succeeded
  (`SIGN_OK`); the same `codesign` in a *later* SSH command failed
  (`errSecInternalComponent`), including on a plain `/tmp` file with no
  entitlements.

**Fix:** unlock + `set-key-partition-list` + `xcodebuild` must run in the **same**
shell invocation.

```bash
security unlock-keychain -p '<pw>' "$HOME/Library/Keychains/login.keychain-db"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '<pw>' \
  "$HOME/Library/Keychains/login.keychain-db"
xcodebuild -project AGXProbe.xcodeproj -scheme AGXProbe -configuration Debug \
  -destination 'id=00008150-00095CD93444C01C' \
  -derivedDataPath .build -allowProvisioningUpdates build
# -> ** BUILD SUCCEEDED **  (build_rc=0)
```

Signing identity used: `Apple Development: ramon.burford@icloud.com (CT2NGWCYS4)`
(`3D787264F545F61A7DEABFE375C4C022EA70E25B`), profile
`iOS Team Provisioning Profile: com.nianticlabs.pokemongo.4L9HF29JJU`
(`f0e794bd-104c-4bbf-b61c-9e2e14fc18ba`).

Install confirmation:

```
App installed:
  bundleID: com.nianticlabs.pokemongo.4L9HF29JJU
  installationURL: file:///private/var/containers/Bundle/Application/A4726870-12F5-4C41-8EB5-22EB222576F7/AGXProbe.app/
  databaseUUID: F1CDFBFA-D98D-4B4F-B0EB-D0695EE8F683
```

## Launch blocked (expected, benign)

```
FBSOpenApplicationServiceErrorDomain error 7 (0x07)
NSLocalizedFailureReason = Unable to launch ... because the device was not,
  or could not be, unlocked
BSErrorCodeDescription = Locked
```

No crash, no respring, no reboot. The app simply never started. Retried after
20 s — still locked. Requires a **physical unlock** of the iPhone at the Mac.
No attempt was made to bypass the lock.

## Probe source now deployed

`AGXProbe/ContentView.swift` = read-only IOSurface geometry-acceptance probe:

* control surfaces (plain 64×64, 512×64)
* F1-shaped plane dict baseline (`sliceCount=4`, tile fields set)
* `IOSurfacePlaneHeaderRegionBytesPerSlice` sweep
  `0, 1, 0x100, 0x1000, 0x4000, 0x10000, 0x100000, 0x1000000, 0x10000000,
   0x20000000, 0x40000000, 0x7fffffff, 0x80000000, 0xffffffff`
* same key as a top-level key (to distinguish "value rejected" from "only read
  from a plane dict")
* `dataPerSlice`, `tileRow`, `tileData`, `sliceCount` sweeps
* `IOSurfaceAddressRanges` / `AddressFormat` / `AddressOffset` and
  `IOSurfaceSuperbuffer` presence probes

Safety invariants: no Metal, no GPU submission, no writes to any allocation, no
cross-object attempt. Geometries are created and immediately released; a reject
is simply a `NULL` return.

Log goes to `Documents/geom.log` in the app container.

## Build-environment notes (for reproducibility)

* The iOS SDK's `IOSurface.framework` has **no** umbrella `IOSurface.h`. The C
  API must be imported as `<IOSurface/IOSurfaceRef.h>`.
* In Swift, `IOSurfaceRef` is ARC-managed (`CF_BRIDGED_TYPE`); `CFRelease` is
  marked unavailable and `IOSurfaceRelease` is not declared. Let ARC release.
* `IOSurfaceGetBaseAddress` imports as non-optional `UnsafeMutableRawPointer`.
* No Swift module exists for IOKit/IOSurface on iOS — the bridging header is
  required.

## Next step

Unlock the phone, then:

```bash
xcrun devicectl device process launch --device 00008150-00095CD93444C01C \
  --terminate-existing com.nianticlabs.pokemongo.4L9HF29JJU --autorun
xcrun devicectl device copy from --device 00008150-00095CD93444C01C \
  --domain-type appDataContainer \
  --domain-identifier com.nianticlabs.pokemongo.4L9HF29JJU \
  --source Documents/geom.log --destination /tmp/geom.log
```
