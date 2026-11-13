# AGXProbe — build & run notes

Target: **iPhone 17 Pro (iPhone18,1 / V53AP), iOS 27.0.1 (24A446)**
Kext under test: `com.apple.AGXG18P`

> ⚠️ Crash probe. Run only on the secondary test device. A bad index can
> cause a kernel panic and reboot. Do not run it on a daily driver.

## Current status

| Step | Result |
|---|---|
| Xcode project created | ✅ `AGXProbe.xcodeproj` |
| Compiles for iOS device | ✅ `BUILD SUCCEEDED` |
| Signed with development cert | ✅ team `<your-team-id>` |
| Installed on the connected iPhone | ✅ `com.<your-bundle-id>` |
| Launched automatically | ✅ with `--autorun` |
| Command/ownership probe | ✅ completed, no crash/respring |
| OOB helper reachable | ⛔ gated by `com.apple.private.agx.performance-spi` |

Final result: **no unprivileged path** to the channel-index OOB helper.
`0x105` commands `0..0xa` and the `0x109` / `0x10d` owner paths all return
`kIOReturnNotPrivileged`; the only successful `0x105` command is the
read-only status query `0xb` (`ownerBits=0`, entitlement bit clear). See
`analysis/agxg18p-reachability-result.md` and
`analysis/probe-run-2026-11-06-1134.log` for the evidence.

The app is installed. It uses the iPogo App ID slot, but the display name is
AGXProbe.

## What was fixed vs. the guide

1. `import SwiftUI` was missing in the original UIKit source.
2. `import IOKit` does not work on iOS — the SDK ships IOKit headers but no
   Swift module. `AGXProbe-Bridging-Header.h` imports `<IOKit/IOKitLib.h>` and
   `SWIFT_OBJC_BRIDGING_HEADER` points at it.
3. `IOServiceGetMatchingService` now gets an `IOServiceMatching()` dictionary,
   not a `CFString`, and the return is compared to `IO_OBJECT_NULL`.
4. Scalar output count is a `UInt32` element count; the input struct is passed
   as a 16-byte raw buffer with matching size.
5. Index range is `0...255` (inclusive), matching the button label.
6. `IOConnectClose` does not exist — replaced with `IOServiceClose`.
7. One `@main` only: `AGXProbeApp` lives in `AGXProbe/ContentView.swift`, and
   there is no generated `AGXProbeApp.swift`.
8. **Service lookup:** `AGXDeviceUserClient` / `AGXCLChannel` are
   `IOUserClient` subclasses, not IOService registry nodes, so they can never
   be found by `IOServiceMatching`. The probe now enumerates `IOAccelerator`
   and opens the AGX node that actually exists (falling back to guessed names
   such as `AGXAcceleratorG18P` if the scan is blocked).

## Project layout

```
~/agx-probe-project/
├── AGXProbe.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/AGXProbe.xcscheme
├── AGXProbe/
│   ├── ContentView.swift              # app + probe (single @main)
│   └── AGXProbe-Bridging-Header.h     # exposes IOKit C API to Swift
├── AGXProbe.swift                     # original UIKit source (unused)
└── README-agxprobe.md
```

## Signing note

The free-account App ID limit ("up to 10 App IDs every 7 days") was already
reached, so `com.<repo-owner>ord.agxprobe` could not be registered. Per your
request, the project reuses the sideloaded iPogo App ID:

```
com.<your-bundle-id>
```

Xcode created a fresh development profile for it. Consequences:

- Reinstalling iPogo with Sideloadly using the same App ID will **replace**
  AGXProbe (and vice versa).
- To use a dedicated ID later, delete an unused App ID in the developer
  portal (or wait for the 7-day window), then change
  `PRODUCT_BUNDLE_IDENTIFIER` in both build configurations.

To change the team: select the AGXProbe target → Signing & Capabilities →
choose your team. The bundle identifier must stay on an App ID that already
exists while the limit is active.

## Build from the command line

```bash
cd ~/agx-probe-project

# compile only (no signing)
xcodebuild -project AGXProbe.xcodeproj -scheme AGXProbe \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# build, sign, install on the connected iPhone
xcodebuild -project AGXProbe.xcodeproj -scheme AGXProbe \
  -destination 'id=<device-udid>' \
  -allowProvisioningUpdates build

xcrun devicectl device install app \
  --device <device-udid> \
  .build/Build/Products/Debug-iphoneos/AGXProbe.app
```

## Running the probe

1. Unlock the iPhone.
2. Open **AGXProbe**.
3. Tap **Start Probe (0–255)**.
4. Watch the log for:
   - `IOAccelerator: AGXAccelerator…` — the node was found.
   - `IOServiceOpen failed: …` — sandbox/entitlement denial (likely on a
     stock sideloaded app; report the exact `kr`).
   - `sel=N idx=M kr=…` — non-zero returns from the selector.
   - App crash / respring / reboot — stop and pull logs.

The scan is intentionally best-effort: a sandboxed third-party app may not be
allowed to open the AGX user client at all. That result is useful too — report
the exact `kr` values.

## Pulling crash logs

```bash
ipsw idev crash ls
ipsw idev crash pull -o ~/agx-probe-project/crashes
```

Or from Windows:

```
.\tools\ipsw\ipsw.exe idev crash ls
.\tools\ipsw\ipsw.exe idev crash pull -o G:\iOS 27.0.1\iOS\analysis\ios\crashes
```

Look for `.ips` files mentioning `AGXG18P`, `IOUserClient`, or `panic`.

## Report back

- Did the `IOAccelerator` scan list an AGX node?
- Did `IOServiceOpen` succeed, and if not, what `kr`?
- Any non-zero selector returns?
- Did the app crash, respring, or reboot?
- If it crashed, the matching `.ips` / panic log.
