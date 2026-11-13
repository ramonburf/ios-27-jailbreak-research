# `AppleJPEGDriver` — reachable user-client surface (iOS 27.0.1, t8150)

Date: 2026-11-08
Status: **surface mapped, dispatch table recovered, no vulnerability claimed.**

## Why this target

The open-only reachability sweep (`REACHABILITY-2026-11-08.md`, raw
`analysis/evidence/mac/reach.log`) found three services a plain sandboxed app can
open:

| service | open result |
|---|---|
| `IOSurfaceRoot` | type 0 |
| `AGXAcceleratorG18P` | type 1 |
| **`AppleJPEGDriver`** | **type 0 and type 1** |

`AppleJPEGDriver` is the only one that consumes caller-supplied bulk data (JPEG
encode/decode buffers). `AppleSARService`, despite the highest kext-scope score,
is sandbox-denied (`kIOReturnNotPermitted`), so its 40+ selectors are irrelevant
to an unprivileged chain.

Kext: `com.apple.driver.AppleJPEGDriver`
(`tools/opencode-temp/lifetime-triage/extract/com.apple.driver.AppleJPEGDriver`)

Layout:

| segment | vmaddr | fileoff |
|---|---|---|
| `__TEXT` | `0xfffffe000752d470` | `0x529470` |
| `__TEXT_EXEC` | `0xfffffe0009002170` | `0x1ffe170` |
| `__DATA` | `0xfffffe000b8ce990` | `0x48ca990` |
| `__DATA_CONST` | `0xfffffe00080db768` | `0x10d7768` |

Kernelcache chained-fixup delta for this member: `0x4000`.

## Classes and methods (from symbol strings)

* `AppleJPEGDriverUserClient` — the user client (`0xfffffe0009016744`
  constructor; vtable `0xfffffe00080dd320`).
* `AppleJPEGDriver` — the codec driver object.

Named external-method implementations recovered from the disassembly:

| method | reference addr | enclosing function start |
|---|---|---|
| `AppleJPEGDriver::startDecoder(AppleJPEGDriverIOStruct *, AppleJPEGDriverIOStruct *, mach_port_t, IOUserClient *, task_t)` | `0xfffffe000900bf58` | `0xfffffe000900bdf4` |
| `AppleJPEGDriver::startDecoderExt(AppleJPEGDriverIOStructExt *, …)` | `0xfffffe000900c93c` | `0xfffffe000900c8f8` |
| `AppleJPEGDriver::startEncoder(AppleJPEGDriverIOStruct *, …)` | `0xfffffe000900d0d4` | `0xfffffe000900d094` |
| `AppleJPEGDriver::startEncoderExt(AppleJPEGDriverIOStructExt *, …)` | `0xfffffe000900d4e8` | `0xfffffe000900d4a8` |
| `AppleJPEGDriver::startDecoder2024(AppleJPEGDriverIOStruct2024 *, …)` | `0xfffffe000900d950` | `0xfffffe000900d90c` |
| `AppleJPEGDriver::startEncoder2024(AppleJPEGDriverIOStruct2024 *, …)` | `0xfffffe000900dfec` | `0xfffffe000900dfac` |
| `AppleJPEGDriverUserClient::registerNotificationPort(mach_port_t, UInt32, UInt32)` | — | — |
| `AppleJPEGDriver::clientClosedGated(AppleJPEGDriverUserClient *)` | `0xfffffe00090098d4` | — |

There are three generations of the input struct: `AppleJPEGDriverIOStruct`,
`…IOStructExt`, `…IOStruct2024`. All are passed by pointer from the user client
and copied field-by-field into the driver's state.

## Dispatch table (RECOVERED — 2026-11-08)

Static analysis of `AppleJPEGDriverUserClient`'s `start` / vtable resolved the
dispatch mechanism. The user client's vtable pointer is at
`0xfffffe00080dd320` and the static dispatch table is embedded immediately after
the vtable in `__DATA_CONST.__const` at:

| field | value |
|---|---|
| table VA | `0xfffffe00080dd990` |
| entries | 10 (`dispatchCount = 0xa` passed from `AppleJPEGDriverUserClient::externalMethod`) |
| entry size | `0x28` (40) bytes |

Entry layout (as consumed by the kernel at
`0xfffffe000b37475c`, `IOUserClient::externalMethod` core):

```
offset  size  field
0       8     dispatch function (IOUserClientMethodFunction)
8       4     checkScalarInputCount
0xc      4     checkStructureInputSize
0x10    4     checkScalarOutputCount
0x14    4     checkStructureOutputSize
0x18    8     (additional field, seen = 1 on entries 6/7)
0x20    8     (padding/unused, 0)
```

Recovered table (entry -> function -> target):

| entry | dispatch fn | target fn | structIn | structOut |
|---|---|---|---|---|
| 0 | `0x9016358` | `0xfffffe000900a73c` | 0 | 0 |
| 1 | `0x9016364` | `0xfffffe000900bdf4` | **0x58 (88)** | **0x58 (88)** |
| 2 | `0x9016398` | `0xfffffe000900a748` | 0 | 0 |
| 3 | `0x90163a4` | `0xfffffe000900d094` | **0x58 (88)** | **0x58 (88)** |
| 4 | `0x90163d8` | `0xfffffe000900d4a8` | **0x1000 (4096)** | **0x1000 (4096)** |
| 5 | `0x901640c` | `0xfffffe000900c8f8` | **0x1000 (4096)** | **0x1000 (4096)** |
| 6 | `0x9016440` | `0xfffffe000900dfac` | **0xda0 (3488)** | **0xda0 (3488)** |
| 7 | `0x9016474` | `0xfffffe000900d90c` | **0xda0 (3488)** | **0xda0 (3488)** |
| 8 | `0x90164a8` | `0xfffffe0009009ba4` | 0x4 (4) | 0 |
| 9 | `0x90164d8` | `0xfffffe0009009c3c` | 0 | 0 |

Selectors are therefore the table index (entry order is authoritative; the
earlier `curses.txt` note of `sel=0x1ff` came from a stale/different table and is
contradicted by the code path actually taken by `externalMethod`).

Gating:
* entries 8/9 call into `AppleJPEGDriver::setPowerState_gated` /
  `AppleJPEGDriver::clientClosedGated` style code paths and gate on
  `[AppleJPEGDriverUserClient + 0x108]` (set during `start` from the
  `com.apple.applejpegdriver.poweron` entitlement).
* entries 1/3/4/5/6/7 (`startDecoder*`, `startEncoder*`) carry NO such gate in the
  dispatch entry and are reached without an entitlement check on the codec path.

The dispatch functions are thin wrappers:

* entry 1 (`0x9016364`) -> `startDecoder`: loads
  `structIn = args->structureInput`, `structOut = args->structureOutput`,
  `driver_instance = [x0 + 0xe0]`, `mach_port = [x4 + 0xf0]`,
  `task = [x4 + 0x100]` and branches to `0xfffffe000900bdf0`.
* entry 3/4/5/6/7 similarly branch (`b 0xfffffe000900d0xx`) to the corresponding
  `start*` implementation, passing the same register layout.

This resolves the "dispatch table not found" open problem. The remaining open
problems are struct layout and entitlement semantics.

## What `startDecoder` does with the input (first 0x100 bytes)

At `0xfffffe000900bdf4`:

```
0x900be24:  cbz  x1, error            ; input struct must be non-null
0x900be40:  ldr  w2, [x1, #0x48]      ; caller-controlled u32
0x900be44:  ldr  x8, [x1, #0x30]      ; caller-controlled pointer/flag
0x900be48:  cmp  x8, #0
0x900be4c:  cset w3, ne
0x900be50:  ldr  w8, [x1, #0x14]      ; caller-controlled u32
0x900be54:  ldrh w9, [x1, #0x18]      ; caller-controlled u16
0x900be58:  orr  w4, w9, w8, lsl #16
0x900be6c:  bl   __stub_fffffe000b5d37fc
0x900be78:  bl   __stub_fffffe000b7fd210 ; kalloc_type
0x900be84:  add  x28, x0, #0x428
```

Fields at `+0x14`, `+0x18`, `+0x30`, `+0x48`, `+0x54` are read from the
caller-supplied structure before any size relationship between them is
established in this prologue. Whether that is safe depends on checks performed
by the stub at `0xfffffe000b5d37fc` (an IOKit/kernel helper) and on downstream
use in `startDecoderGated`.

Some validation *is* present in the same function:

* `newHeaderSize` must be a multiple of 12
  (`"… is not a multiple of 12 bytes, rejecting"`);
* `newHeaderSize` compared against `MARKERRAM_MEM_SIZE`
  (`"… exceeds MARKERRAM_MEM_SIZE … rejecting"`) and against `0xf7f`/`0x1000`
  bounds in the `Ext` path.

So the parser is not naive. No bug is claimed.

## Class properties set in `AppleJPEGDriverUserClient::start`

The `start` path (`0xfffffe0009015cdc`) calls `setProperty` with:

| property | meaning |
|---|---|
| `IOUserClientDefaultLocking` | IOKit locking policy |
| `IOUserClientDefaultLockingSetProperties` | IOKit property-set policy |
| `IOUserClientDefaultLockingSingleThreadExternalMethod` | single-threaded external-method policy |
| `IOUserClientEntitlements` | **entitlement gate** |

`IOUserClientEntitlements` being set is noteworthy, yet the actual
`IOServiceOpen` succeeded for both types. That means either the property value is
empty on this path, or the gate is applied per-selector / per-method rather than
at open. This must be resolved before assuming the methods are callable.

## Open problems

1. ~~**Selector numbering / dispatch table not yet located.**~~ **RESOLVED.**
   The dispatch table was located at `0xfffffe00080dd990` in
   `__DATA_CONST.__const`, 10 entries × 40 bytes, consumed by
   `IOUserClient::externalMethod` (core at `0xfffffe000b37475c`) via
   `IOUserClientMethodDispatch` (fn @ +0, checkScalarInput @ +8,
   checkStructureInput @ +0xc, checkScalarOutput @ +0x10, checkStructureOutput @
   +0x14). Selector = table index. See "Dispatch table (RECOVERED)" above.
2. **Input struct layout not fully mapped.** `AppleJPEGDriverIOStruct`,
   `…Ext` and `…2024` need field-by-field reconstruction from the three
   `start*` functions and `start*Gated`.
3. **Entitlement semantics of `IOUserClientEntitlements`** on this class.

## Next steps (static first)

1. ~~Recover the dispatch table~~ — **done** (see "Dispatch table (RECOVERED)").
2. Reconstruct `AppleJPEGDriverIOStruct` (and the `Ext`/`2024` variants) from the
   field offsets used by `startDecoder` / `startDecoderGated`.
3. Only after 1–2: build a controlled, argument-free selector probe (bad
   arguments should return `kIOReturnBadArgument`, not crash) on the secondary
   device, with crash-log pulling armed.

No device interaction beyond open/close has been performed against
`AppleJPEGDriver`.
