# AGXProbe carrier

SwiftUI research app used as the on-device harness. Bundle id
`com.nianticlabs.pokemongo.4L9HF29JJU`, team `4L9HF29JJU`, no entitlements, normal app
sandbox.

`AGXProbe/ContentView.swift` is the authoritative carrier source. It is the same file that
builds on the Mac at `~/agx-probe-project/AGXProbe/ContentView.swift` (sha256
`2c0ed17a5969410e38c97f7921780878b2117a7029a7b03a6ca23cdcb30a1727` at commit time).

## Modes

| Arg | Mode |
|---|---|
| `--sockuaf` | CVE-2026-112514 socket-UAF harness (five race variants + peer-delivery oracle) |
| `--webscan` | WebKit probe |
| `--autorun` | banner only |

## Build / deploy

On the Mac (Xcode 27.2):

```sh
DEV=<udid> ~/build_race.sh
xcrun devicectl device install app --device $DEV .build13/Build/Products/Debug-iphoneos/AGXProbe.app
xcrun devicectl device process launch --device $DEV --terminate-existing \
  com.nianticlabs.pokemongo.4L9HF29JJU --sockuaf
```

`build_race.sh` defaults the destination to the iPhone 17 Pro
(`00008150-00095CD93444C01C`); override with `DEV=`.

Logs: the app writes `Documents/reach.log` in its container. Pull it with
`xcrun devicectl device copy from --domain-type appDataContainer ...`.

Signing profile expires **2026-11-15** — regenerate before then.

## Notes

- `ContentView` / helpers are `nonisolated` on purpose: the race loop must not run on the
  MainActor or SpringBoard kills the app with a `0x8BADF00D` scene-create watchdog at 20 s.
- The bridging header exposes IOKit C APIs; iOS has no Swift module for `IOKit.framework`.
