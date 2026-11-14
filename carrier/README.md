# Tims Cooked — carrier

A SwiftUI app used as the on-device harness. It has **no entitlements** and runs in an
ordinary app sandbox, which is what makes its findings meaningful — anything it can reach,
any app can reach.

`AGXProbe/ContentView.swift` is the main entry point and contains every socket-UAF race
variant. The file that actually builds is the one on the machine doing the building; keep the
repository copy and the local copy identical, and sync both ways after edits.

## Modes

| Argument | Mode |
|---|---|
| `--sockuaf` | CVE-2026-112514 socket-UAF harness — variants A–E round-robin |
| `--sockprec` | Variant E only: gated one-shot send per sender plus peer-delivery oracle |
| `--sockool` | Variant F: cross-zone reclaim with an out-of-line `mach_msg` spray |
| `--sockxz` | Variant G: free a whole socket page block, then OOL spray |
| `--sockgc` | Variant H: batch-free past the zone's page-return delay, then OOL spray |
| `--web`, `--webscan` | WebKit probing |
| `--probe` | IOSurface probe sweep |
| `--autorun` | Prints a banner only |

## Build and install

From the repository root, on macOS with Xcode:

```sh
DEV=<device-udid> ./build_race.sh
xcrun devicectl device install app --device $DEV \
    .build13/Build/Products/Debug-iphoneos/AGXProbe.app
xcrun devicectl device process launch --device $DEV --console --terminate-existing \
    <your-bundle-id> --sockprec
```

`build_race.sh` defaults the destination to a specific device; override it with `DEV=`.

The app writes its log into its own container (`Documents/`), and also echoes it to the
console when launched with `--console`. `devicectl device copy from --domain-type
appDataContainer` retrieves the file if needed.

Signing is environment-specific (bundle identifier, team, provisioning profile); those
details are deliberately not documented here. Nothing else in this project depends on them.

## Tests

Everything checkable without touching the screen lives in `carrier/tests/`:

```sh
swiftc -O fixcheck.swift -o /tmp/fixcheck && /tmp/fixcheck
swiftc -O logcheck.swift -o /tmp/logcheck && /tmp/logcheck
```

See `carrier/tests/README.md` for coverage.

## Notes

- `ContentView` and its helpers are deliberately `nonisolated`: the race loop must not run on
  the main actor, or SpringBoard kills the app with a scene-creation watchdog at ~20 seconds.
- The bridging header exposes IOKit C APIs, since iOS ships no Swift module for
  `IOKit.framework`.
- Long-running loops are CPU-intensive by design. iOS's CPU watchdog terminates the app at
  roughly 90 seconds of CPU time per 180-second window, so idle waits in the harness need to
  block rather than spin — see `HANDOFF.md` for the current status of that trade-off.
