# Findings so far

Summary of every attack surface examined, and why each one is or is not being pursued. For
the full survey, see `analysis/LEAD-ASSESSMENT.md`.

## Constraints

- No firmware writes, restores, updates, downgrades or boot-chain changes. Devices must stay
  on their current OS with all data intact.
- Kernel probes run only on secondary hardware first; anything that might cause an app crash,
  SpringBoard respring or reboot is stopped immediately and its crash logs are pulled.
- Any positive result is confirmed on the primary target device only after it has been shown
  to be benign on the secondary device.
- The goal is a semi-untethered jailbreak; nothing in the boot chain needs to be touched.

## IOSurface (`com.apple.iokit.IOSurface`)

The most thoroughly mapped surface.

- The service is reachable from an ordinary app sandbox: `IOServiceOpen(type=0)` succeeds.
- Selector 0 (create) works and produces surfaces with `IOSurfacePlaneInfo`.
- Selector 1 (release) returns `0xe00002c2` for every ID via struct input — not functional.
- Selector 9 (`setValue`) accepts a string value; selector 10 (`getValue`) returns success but
  an empty output buffer.
- Selectors 26, 46–54 all return `0xe00002c2` (bad argument).
- Every create edge case tried (zero width/height/bytes-per-element/bytes-per-row, maximum
  values, plane offsets and sizes, address ranges) is correctly validated.
- **Superbuffer aliasing is confirmed on both devices**: a parent and child surface created
  with `IOSurfaceAllocateFromSuperbuffer`, sharing a plane offset, share user pages — writes
  through one are visible through the other. This is real, but it stays inside IOSurface's own
  shared pages rather than reaching arbitrary kernel memory.

A separate use-after-free family in this kext (CVE-2026-112517 / -112516 / -112477) is
identified but constrained by pointer authentication and type-confusion barriers; it remains
a secondary candidate at roughly 25 % readiness.

## AGX / AGXG18P

**Exhausted as an attack surface.**

- The accelerator user client is reachable from the app sandbox on both device classes.
- Selector 4 returns a 32-byte output containing two pointer-like values and a size of
  `0x4000`; these look like static userland buffer information, not kernel pointers.
- Selector 0x103 returns success with an all-zero output.
- All other selectors in 0x0–0xFF return `0xe00002c7` (unsupported).
- An out-of-bounds channel-index read does exist in the kext, but it is installed during
  module initialisation rather than in any dispatch table, so it is not reachable through a
  user-connectable selector.

## AppleJPEGDriver

- Reachable via `IOServiceOpen(type=0 and type=1)`.
- The selector 10 dispatch table was recovered (10 entries); selectors 1–7 are callable
  without entitlements.
- All codec selectors return `0xe00002cc` (not responding) or `0xe00002bc` (error), and the
  codec selectors appear power-gated. No exploitable behaviour found.

## IOHIDFamily

An out-of-bounds read/write was identified in the 27.0.1 → 27.2 diff (CVE-2026-112507): four
accessors gained bounds checks. However, no HID class could be opened from the app sandbox,
so the path is not currently reachable. Readiness ~20 %.

## Sockets — CVE-2026-112514 (lead)

See `HANDOFF.md` and `analysis/socket-uaf-stale-write-2026-11-13.md`. The race is won on
hardware (20 confirmed stale kernel writes via a peer-delivery oracle); converting that into
a controlled read/write primitive is the current focus.

## What to do next

1. Determine the kernel allocation size of `struct socket` (blocks evaluation of the
   cross-zone reclaim variants F/G/H).
2. Reclaim the freed socket slot with attacker-influenced contents instead of another socket.
3. Obtain a leak (KASLR slide plus heap address) to shape a fake `so_proto`.
