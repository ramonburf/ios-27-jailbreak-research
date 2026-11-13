# Socket-UAF hammer harness — state at pause (2026-11-13 ~13:05)

Mac went to sleep mid-work. Nothing on the device is running. Read this before resuming.

## Root cause of the "SIGKILL after N iterations"

Not jetsam. Pulled `systemCrashLogs` → `AGXProbe-2026-11-13-123307.ips`:

```
FRONTBOARD 0x8BADF00D  scene-create watchdog transgression:
exhausted real (wall clock) time allowance of 19.96 seconds
```

The whole `--sockuaf` loop ran on the MainActor from `.task`, so the scene never
finished creating and SpringBoard killed the app at 20 s. fd count was flat (20) and
footprint only ~15 MB, so the earlier "memory pressure" theory was wrong.

## What was changed (carrier ContentView.swift, v123 → next)

1. **Off the MainActor** — `runSocketUafMode` and all `sockUaf*` helpers are `nonisolated`;
   `--sockuaf` is dispatched via `Task.detached`; logging goes through `emitBg`
   (`Task { @MainActor ... }`). **Verified: app survived >2 min, 17.8 k iterations.**
2. **Persistent workers** — 6 sender threads + 1 closer thread created once, spinning on a
   shared word array (`SockUafState`), instead of ~2.7 threads per iteration. ~200 it/s.
3. **Real race structure** — senders are already in-kernel when the closer fires; the
   closer wins a CAS `phase 2 → 3` so exactly one party closes (no double-close of a
   reused fd number).
4. **Longer kernel residency** — `sendmsg` with 8 × 1 KiB iovecs, `MSG_DONTWAIT`.
5. **New oracle** — after a send returns `>= 0` (or an odd errno) while phase == 3, do
   `fcntl(fd, F_GETFD)`; if the descriptor is still free, the syscall walked a stale
   socket → counted as `UAF PROBE` and logged.
6. **Timer variant (D)** — pool of 64 sockets whose send window is filled and left idle,
   arming the TCP retransmit timer; variant D retires one per iteration so close races a
   live kernel timer, not only a syscall.

## Status of the build

- **Built + installed + verified**: main-actor fix (step 1) + persistent workers. Ran
  17.8 k iterations clean, no corruption.
- **Written locally, NOT yet built**: steps 4–6 (`sendmsg`, UAF probe, timer variant).
  The last build failed on a Swift string-literal error at `ContentView.swift:650`; the
  local source is **already fixed** but was not re-uploaded. Build it from the local
  authoritative copy `C:\Users\Volpi\AppData\Local\hermes\cache\scratch\ContentView.swift`
  (identical to `~/agx-probe-project/AGXProbe/ContentView.swift` whenever synced).

## Resuming

1. Upload the local ContentView.swift, run `~/build_race.sh`, install, launch without
   `--console` (console is not required; it was not the cause of the kills).
2. Watch `UAF PROBE` counts in the pulled `Documents/reach.log`; a hit is the real signal.
3. Pull `systemCrashLogs` after any abnormal exit — a kernel panic log is the other
   positive signal.

Profile expiry is still **2026-11-15**; regenerate before then.
