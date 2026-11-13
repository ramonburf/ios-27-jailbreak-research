# AGXG18P channel-index OOB helper — dynamic reachability result

Date: 2026-11-06 11:34 local
Device: REDACTED_PERSON's iPhone 17 Pro (iPhone18,1, t8150), iOS 27.0.1 (24A446)
UDID: <device-udid>
App: AGXProbe, bundle ID `com.<your-bundle-id>`
Signing: `Apple Development: redacted@example.invalid (<your-team-id>)`, team `<your-team-id>`

## Result

**The channel-index bitmap helper at `0xfffffe0008556f54` is not reachable
from the sideloaded app.** Every user-client path that can supply a
channel index is behind an ownership/entitlement gate requiring
`com.apple.private.agx.performance-spi`. The signed app does not carry that
entitlement. The unprivileged selectors are read-only queries and do not
accept a channel index.

No crash, panic, respring, or reboot occurred. The device stayed
`available (paired)` after the run.

## Dynamic evidence

### 1. Only one user-client type is exposed

```
open type=0  kr=0xe00002c7  (kIOReturnUnsupported)
open type=1  OK
open type=2  kr=0xe00002c7
...
open type=15 kr=0xe00002c7
```

`IOServiceOpen(type=1)` creates the only usable `AGXDeviceUserClient`.

### 2. Entitlement bit is clear and no owner is held

`0x105` command `0xb` is the unprivileged status query (it bypasses the
owner check). Input/output are 0x48-byte structures; input word 0 = `0xb`.

```
query sel=0x105 in=72 out=72 kr=0 gotOut=72
      0b 00 00 00 00 ...
status flags=0x0 ownerBits=0 entitled=false gpuFlag=false
```

The handler encodes:

- bits 0..1 — owner state: `0` = no owner, `1` = another client owns it,
  `3` = this client owns it
- bit 2 — `com.apple.private.agx.performance-spi` present
- bit 3 — GPU-side flag

`flags=0x0` means **no owner and no entitlement**.

### 3. Owner-gated `0x105` commands all fail

`0x105` command IDs `0..0xa` require the caller to be the exclusive owner
(`[GPU+0x11380]->[0x20] == this client`). All returned
`kIOReturnNotPrivileged` (`0xe00002c1`):

```
cmd0 .. cmd10  kr=0xe00002c1
cmd11 (0xb)    kr=0
```

The only command that succeeds is the read-only status query `0xb`.

### 4. Owner acquisition is entitlement-gated

`0x109` is the owner/authorization path. All commands, including command 0
with input byte 1 = 1 (the documented owner-set operation), returned
`kIOReturnNotPrivileged`:

```
109cmd0 .. 109cmd3  kr=0xe00002c1
setowner (109 cmd0, in[1]=1)  kr=0xe00002c1
```

`0x10d` (open/close path) likewise:

```
10dcmd1 .. 10dcmd3  kr=0xe00002c1
```

### 5. Unprivileged selectors are queries only

- `0x100`, `0x101`, `0x102` — device-info queries, `kr=0`
- `0x103`, `0x104`, `0x106` — trivial device-info queries
- `0x10a` — copies a 16-byte constant
- `0x10f` — reads device state, no input
- `0x110` — accepts an 8-byte input whose byte 0 is validated to `0..2`
  (a selector, not a channel index); all three selectors return `kr=0`
- `0x112` — read-only query
- `0x10b`, `0x10c` — hardcoded `kIOReturnUnsupported`

None accepts a channel index in the range needed to reach the OOB read.

## Static gate chain

1. `0x109` handler (`0xfffffe00084f0ff0`) calls the entitlement check at
   `0x84f1038`:

   ```
   bl 0x8587f2c        ; auth stub
   ...
   ```

   The stub's `__auth_got` entry (`0xfffffe0007f34a28`, raw
   `0x801100000303b908`) resolves to `0xfffffe000a03f908` after the
   `+0x4000` addrDiv/slide adjustment. The checked string at
   `0xfffffe0007135bdb` is:

   ```
   com.apple.private.agx.performance-spi
   ```

   A zero return means no entitlement and the handler returns
   `kIOReturnNotPrivileged`.

2. `0x10d` uses the same entitlement string and check at `0x84f0b98`.

3. `0x109` command 0 with input byte 1 = 1 is the owner-set operation. The
   `0x105` dispatcher's owner check (`0x84f16c8`) reads
   `[GPU+0x11380]->[0x20]` and compares it to the calling client. Since the
   owner field is still zero, commands `0..0xa` fail before reaching any
   channel-index helper.

4. The helper at `0xfffffe0008556f54` is the reserve/allocate function:

   ```asm
   ldrb  w8, [x1]            ; channel index (attacker-controlled byte)
   ldr   x9, [x9, #0x40]     ; table
   ldr   x8, [x9, x8, lsl #3]; OOB read, no bounds check
   ldrb  w8, [x8, #0x14]
   tbnz  w8, #5, ...
   ```

   It has no direct `bl` caller in the kext disassembly; it is invoked
   through an indirect channel/vtable path. All user-reachable callers that
   can pass a channel index are the `0x105` commands `0..0xa`, which are
   blocked by the owner gate above.

## Entitlement check on the signed app

`codesign -d --entitlements :-` on the installed build shows only:

```
application-identifier = <your-team-id>.com.<your-bundle-id>
com.apple.developer.team-identifier = <your-team-id>
get-task-allow = true
```

`com.apple.private.agx.performance-spi` is absent. Adding it is not
signature at launch.

## Conclusion

There is no unprivileged dynamic path to the `0xfffffe0008556f54`
channel-index OOB helper from this signed app. Reaching it requires the
private AGX performance entitlement so that `0x109` command 0 can install
the caller as the exclusive owner. Without that entitlement, `0x105`
commands `0..0xa` return `kIOReturnNotPrivileged` and the helper is never
entered.

## 2026-11-06 follow-up (full-kernelcache static analysis + service enumeration)

- Full-kernelcache disassembly was used to resolve the `sel=0x110` /
  OOB-helper path.
- The OOB helper at `0xfffffe0008556f54` has no direct `bl`/`bra` branch
  target in the full kernelcache disassembly; it is reached through an
  authenticated indirect branch (channel/vtable path).
- The C++ vtable method associated with the external selector namespace
  `0x110` (`AGXDeviceUserClient::fn_0x110`) is implemented at
  `0xfffffe000b2e0d40` and is a small authenticated dispatcher; it does not
  directly call the OOB helper.
- The command-processing helper at `0xfffffe00084e83ec` calls the slot
  allocator at `0xfffffe000856a5e8`; the prior interpretation that
  `0x856a5e8` is the OOB helper was corrected.
- Service enumeration on the secondary device found only
  `AGXAcceleratorG18P` (plus unrelated AGX firmware services) as the
  openable AGX/IOUserClient service; no new selector/service entry point was
  found.
- Dynamic `ssize=16` sweep over `0x100..0x1ff` found no selector that accepts
  the 16-byte `{index, mask}` shape and reaches the OOB helper; the
  owner-gated `0x105` command path remains the only known route.

## Artifacts

- `probe.log` — raw run log (this run)
- `cursor.txt` — last call marker (`sel=0x110 idx=2`)
- `AGXProbe/ContentView.swift` — probe implementation
- `analysis/sel105.txt`, `analysis/sel109.txt`, `analysis/sel10d.txt` —
  handler disassembly
- `analysis/agx_uc.json` — `AGXDeviceUserClient` vtable metadata
