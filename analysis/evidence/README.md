# Raw evidence index

Every artifact here is a **raw capture**, not an interpretation. The `.md`
files that interpret them live one level up in `analysis/`.

Convention: filename = `YYYY-MM-DD-<what>.log|txt|json|png`.

| file | what it is | source |
|---|---|---|
| `2026-11-06-iokit-service-enumeration.log` | IOKit service enumeration run from the signed AGXProbe app: 1542 services scanned, 4 AGX/GPU services found, `IOServiceOpen(type=0)` vs `type=1` results per service, 6 `IOUserClient` instances found | on-device AGXProbe app, stdout captured |
| `2026-11-06-probe-cursor.txt` | the probe's last-call marker file (currently **empty** — see the note below) | on-device AGXProbe app |
| `2026-11-06-pymd-debugserver-lldb-run.log` | `pymobiledevice3 developer debugserver lldb` failure trace, showing the Unix-pty limitation that forced the custom Windows driver | PC-side `pymobiledevice3` |
| `2026-11-07-rsd-info.json` | RSD userspace tunnel facts (device/host IPv6 addresses, service ports) | PC-side `pymobiledevice3` |
| `kernelcache-kexts-27.0.1.tsv` | all 319 kext names + load addresses, parsed out of `ipsw kernel kexts` output | `firmware/24A446/kernelcache.release.macho` |
| `kext-scope-27.0.1.txt` | kext lifetime/UAF triage report over all 301 kernelcache fileset members | `analysis/kext-scope/scope_kexts.py` |
| `mac/geom5.log` | on-device probe v5: `IOServiceOpen(IOSurfaceRoot)` ok, selector 0 with XML → `0xe00002c2` | signed AGXProbe app, `--autorun` |
| `mac/geom6.log` | on-device probe v6: selector-0 scalar-shape matrix (0/1 scalars × length/zero/one/none) and selector sweep 1–5, all `0xe00002c2` | signed AGXProbe app, `--autorun` |
| `mac/geom7.log` | on-device probe v7: 8 payload encodings × 2 scalar shapes, all `0xe00002c2` | signed AGXProbe app, `--autorun` |
| `mac/reach.log` | on-device probe v8: open-only reachability sweep over 1483 services; `IOSurfaceRoot`, `AGXAcceleratorG18P`, `AppleJPEGDriver` open, `AppleSARService`/`AKSAnalytics` denied | signed AGXProbe app, `--autorun` |
| `mac/AGXProbe-2026-11-08-151733.ips` | crash report for the first v8 run: userland `String(format:"%s", String)` bug in the probe, not a kernel fault; device did not reboot | on-device crash reporter, pulled via `devicectl` |
| `video-contact-sheet.png` | 10-frame contact sheet (2 s interval) of the supplied F1 recording | `HNvr78FcHnHWtN8k.mp4` |
| `video/frame_*.png` | individually extracted frames of the same recording (index in `analysis/f1/F1-PRIMITIVE-EVIDENCE.md` §5) | `HNvr78FcHnHWtN8k.mp4` |

## Note on `2026-11-06-probe-cursor.txt`

`extraction/extraction/analysis/agxg18p-reachability-result.md` lists this
file as the "last call marker (`sel=0x110 idx=2`)". **The file is now 0 bytes.**
Either the app truncates it on a clean exit or a later run overwrote it. The
claim it was supposed to support (that the last call the probe made was
`sel=0x110` with index 2) therefore rests on the reachability report's
prose, not on this artifact. Flagged rather than quietly ignored.

## What is *not* here, and why

The 300-combination argument-shape matrix and the 0–255 index sweep for
`sel=0x110` were run inside the app, but their raw stdout was not persisted
to disk before this evidence pass — the numbers survive only in the session
record and in the prose of the reachability report. They are recorded as
**second-hand** in `analysis/agx/AGX-DYNAMIC-REACHABILITY.md` and flagged for
regeneration; they are not presented as if a raw capture existed.

## Provenance rules applied to this directory

* No artifact in this directory was produced by writing to, flashing,
  restoring, updating or otherwise modifying device firmware.
* Device interaction was limited to: opening debug sessions, enumerating
  IOKit services, opening `AGXAcceleratorG18P`, and issuing benign
  `IOConnectCallMethod` shapes with zero-filled buffers.
* The video frames are the user's own supplied artifact, preserved
  unmodified; the analysis of them is in `analysis/f1/`.
