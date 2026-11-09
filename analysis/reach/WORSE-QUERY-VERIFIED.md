# worse_query — Verified Sandbox Escape (iOS 27.0.1 / 27.0 beta 4)

Date: 2026-11-09

## Result
worse_query (forcequitOS) verified working on BOTH test devices.

| Device | OS | Data/System | Shared AppGroup | SystemGroup |
|---|---|---|---|---|
| iPhone 17 Pro (iPhone18,1) | 27.0.1 (24A446) | handle=2, 23 entries (RO) | handle=3, 289 entries, WRITE OK | -6 |
| iPhone 13 Pro (iPhone14,2) | 27.0 dev beta 4 | handle=2, 22 entries (RO) | handle=3, 247 entries, WRITE OK | -6 |

Pre-state for every target: `EPERM` ("you don't have permission to view it").
Post-state: full directory enumeration succeeds.

## Mechanism
1. App obtains its own App Group container path.
2. Replaces `<group>/Library/Caches` with a symlink to the target path.
3. Asks `containermanagerd` (`container_query`, class 7 appGroup, part 3 = Library/Caches)
   for a sandbox token for the group's Caches.
4. containermanagerd resolves the symlink -> issues token for the *target* path.
5. `sandbox_extension_consume` -> process now has the extension.

## Access matrix (confirmed)
- `/private/var/containers/Data/System` — READ/list only (write denied)
- `/private/var/mobile/Containers/Shared/AppGroup` — READ/WRITE
- `/private/var/containers/Shared/SystemGroup` — refused (-6, kernel won't issue token)

This matches the upstream README claim (iOS 26.0-26.7.2 / 27.2).

## Significance
- This is a **sandbox escape**, NOT a kernel exploit.
- Upstream explicitly states: "This is not relevant to a jailbreak and never will be."
- It grants file read/write outside the app sandbox (other apps' group containers,
  system container metadata). It does NOT grant kernel r/w, task_for_pid, or code injection.
- Useful as a *chain prerequisite* / recon primitive, not a jailbreak.

## Build notes
- Patched project to team `4L9HF29JJU`, bundle `com.volpi.worsequery`, group `group.volpi.worsequery`.
- Added `AutoProof.m` (constructor -> main queue) that runs the escape against the 3 paths and
  writes `Documents/wq_proof.log`.
- Build: xcodebuild Debug, destination id=00008110-000E095936C1801E / 00008150-00095CD93444C01C.
- Pull: `devicectl device copy from --domain-type appDataContainer --domain-identifier com.volpi.worsequery --source Documents/wq_proof.log`.
