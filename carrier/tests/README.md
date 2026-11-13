# Carrier regression tests

These are standalone Swift programs that exercise the **non-UI** logic of the AGXProbe
carrier app. They exist because most of the app's code is ordinary UIKit and can only be
driven by a human tapping the screen — so anything that *can* be checked headlessly is
checked here, in one place, instead of being re-verified by hand after every edit.

They compile with plain `swiftc` on macOS; no Xcode project, no device, no signing.

```sh
swiftc -O fixcheck.swift -o /tmp/fixcheck && /tmp/fixcheck
swiftc -O logcheck.swift -o /tmp/logcheck && /tmp/logcheck
```

Each program prints `PASS`/`FAIL` per assertion and exits non-zero if anything failed.

## `fixcheck.swift` — data-handling edge cases

Copies the relevant functions **verbatim** out of the app sources and drives them directly:

| Area | Source file | What it proves |
|---|---|---|
| Boolean typing in plists | `PlistEditorController.swift` | `NSNumber(value: true)` is recognised as a CFBoolean, so leaving a boolean value unchanged saves a boolean rather than silently turning it into an integer. Round-trips through binary plist serialisation as a boolean. |
| Plist editing validation | `PlistEditorController.swift` | `"false"`, `"0"`, `"TRUE"` convert to booleans; garbage input is rejected instead of being written as a string. Numeric values still parse as Int/Double. |
| Array index guards | `PlistEditorController.swift` (`PlistTree`) | A negative array index returns `nil` on read and is a no-op on write, instead of trapping or corrupting memory. Valid indices still work. |
| Hex patch offsets | `FilesViewController.swift` | Offsets at or beyond EOF are rejected without overflowing; the exact-fit boundary is correct. Also demonstrates that the previous expression crashed on an offset above `Int.max`. |

## `logcheck.swift` — logger concurrency

Replicates the patched `Logger` structure from `ViewController.swift` (an
`NSRecursiveLock` guarding `beginTest` / `note` / `endTest` / `append`) and hammers it
from several threads at once:

- `beginTest` takes the lock and then calls `append`, which locks again — this requires a
  *recursive* lock. The harness shows a plain `NSLock` version deadlocking, confirming the
  choice of `NSRecursiveLock` is load-bearing rather than stylistic.
- Serial runs attribute results (`ok` / `fail`) correctly.
- Six concurrent runs × 40 notes produce exactly 252 lines, with no lost, duplicated or
  interleaved entries, and the on-disk file matches the in-memory record.

This matters because overlapping probe runs used to mix log entries and report wrong
summaries, which makes exploit results untrustworthy.

## Not covered here

The remaining fixes are reachable only through taps (file browser directory-grant ordering,
search cancellation/generation, disabling all probe cards during a run). Those need a UI
automation stack such as XCUITest or `idb`; they cannot be driven from the command line.
