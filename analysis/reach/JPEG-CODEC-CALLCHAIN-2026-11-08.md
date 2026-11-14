# JPEG codec call-chain / dispatch milestone (2026-11-08)

This consolidates the static findings on `AppleJPEGDriver` made on 2026-11-08.

## Dispatch table — RECOVERED

The `AppleJPEGDriverUserClient` vtable pointer is stored at
`0xfffffe00080dd320` and the static dispatch table lives in
`__DATA_CONST.__const` at `0xfffffe00080dd990`.

- 10 entries, each 40 bytes (`IOUserClientMethodDispatch`).
- Entry: fn @ +0, checkScalarInputCount @ +8, checkStructureInputSize @ +0xc,
  checkScalarOutputCount @ +0x10, checkStructureOutputSize @ +0x14.
- Consumed by kernel core at `0xfffffe000b37475c` via stub
  `__stub_fffffe000b8acf58`, with `dispatchCount = 0xa`.

Selector = table index.

| sel | dispatch fn | codec fn | in | out | gate |
|---|---|---|---|---|---|
| 0 | 0x9016358 | 0x900a73c | 0 | 0 | - |
| 1 | 0x9016364 | **0x900bdf4 startDecoder** | **0x58 (88)** | **0x58 (88)** | - |
| 2 | 0x9016398 | 0x900a748 | 0 | 0 | - |
| 3 | 0x90163a4 | **0x900d094 startEncoder** | **0x58 (88)** | **0x58 (88)** | - |
| 4 | 0x90163d8 | **0x900d4a8 startEncoderExt** | **0x1000 (4096)** | **0x1000 (4096)** | - |
| 5 | 0x901640c | **0x900c8f8 startDecoderExt** | **0x1000 (4096)** | **0x1000 (4096)** | - |
| 6 | 0x9016440 | **0x900dfac startEncoder2024** | **0xda0 (3488)** | **0xda0 (3488)** | flag@entry |
| 7 | 0x9016474 | **0x900d90c startDecoder2024** | **0xda0 (3488)** | **0xda0 (3488)** | flag@entry |
| 8 | 0x90164a8 | 0x9009ba4 | 4 | 0 | gated (`com.apple.applejpegdriver.poweron`) |
| 9 | 0x90164d8 | 0x9009c3c | 0 | 0 | gated |

## Call chain from `startDecoder`

`AppleJPEGDriverUserClient::externalMethod` -> dispatch fn 1 ->
`AppleJPEGDriver::startDecoder` (`0x900bdf4`) -> (allocs JpegRequest at
`0x...b7fd210`, copies input struct fields into it) -> vtable call on
`AppleJPEGDriver` at offset `0xb8` -> `AppleJPEGHal::startDecoderGated(ajpeg_setup_t *)`
-> `RequestHandling::decodeRequestValidation(JpegRequest *)` etc.

## Validation functions (candidates for the bug)

See disassembly:

* `RequestHandling::encodeRequestValidation` @ `0xfffffe0007530568`
* `RequestHandling::decodeRequestValidation` @ `0xfffffe00075305a9`
* `RequestHandling::decodeHWRequestSetup` @ `0xfffffe00075305ea`
* `RequestHandling::encodeHWRequestSetup` @ `0xfffffe0007530628`

## Struct field offsets observed in `startDecoder` (0x900bdf4)

From the caller-supplied struct (ptr in `x1`, output struct in `x2`, request
object in `x21`):

| offset | size | use |
|---|---|---|
| `+0x8` | u32 | copied to request+0x2ac (and +0x2b0) |
| `+0x14` | u32 (+`0x18` u16) | packed into a u32 at `+0x14`/`+0x18`; copied to request+0x428 |
| `+0x20` | u8 | flags -> request+0x310 / +0x312 / +0x314 |
| `+0x24` | f64 | -> request+0x450 |
| `+0x2c` | u32 | subsample mode (switch 0..4) |
| `+0x30` | ptr (null-checked) / 8B | -> request+0x10 |
| `+0x40` | ptr | -> request+0x20 |
| `+0x48` | u32 | kdebug arg, -> request+0x538 |
| `+0x4c` | f64 | -> request+0x47c |

Total struct size for selector 1 (decode) / 3 (encode): `0x58` (88) — matches the
dispatch check `checkStructureInputSize == 0x58`.

Total struct size for selector 4 / 5 (Ext): `0x1000` (4096).
Total struct size for selector 6 / 7 (2024): `0xda0` (3488).

## Next step

Map the three structs field-by-field and find which fields are validated in
`RequestHandling::*Validation` vs. only used in HW setup.


## Correction (2026-11-14): the "unidentified kernel stub" address is not code

Re-resolving `0xfffffe000b8a2fc4` against build 24A446:

| | |
|---|---|
| containing segment | `__DATA` |
| file offset | `0x489efc4` |
| raw bytes | `00 00 a0 00 73 6b 5f 63 68 5f 61 6c 6c 6f 63 5f 6c 6f 63 6b` |

The bytes are ASCII — **`***`, with `sk_ch_evq_lo…` following nearby. Disassembly of
the address produces garbage (`udf`, SIMD register ops), confirming data rather than code.
`sk_*` strings are Skywalk channel/policy names spread across the image (252 matches,
file `0x4210a`–`0x49f9bd8`), not a kernel symbol table.

**Consequence:** the earlier claim that `clientClosedGated`
(`0xfffffe000900985c`) "calls stub `0xfffffe000b8a2fc4` on userClient" cannot be correct as
written. Either the call is indirect through a pointer held elsewhere, or the target was
misread. The refcount question that decides whether the dangling-pointer UAF is triggerable
remains **open**, and that analysis should be treated as unverified.

Revalidation path: locate the actual call instruction inside `clientClosedGated`, recover its
real target, and determine what the branch that skips `release()` actually tests.


## Revalidation (2026-11-14): the real `clientClosedGated` call chain

Re-disassembled `clientClosedGated` at `0xfffffe000900985c` from the entry point:

```
0xfffffe000900985c  pacibsp
0xfffffe0009009870  mov  x20, x1            ; x20 = userClient
0xfffffe0009009874  mov  x19, x0            ; x19 = driver
0xfffffe0009009878  cbz  x1, 0x...98c8      ; NULL check
0xfffffe0009009880  mov  x0, x20
0xfffffe0009009880  bl   0xfffffe000902fea8  ; <-- the "unidentified stub"
0xfffffe0009009884  tbnz w0, #0, 0x...98bc  ; if bit0 set -> skip release entirely
0xfffffe000900988c  bl   0xfffffe000900990c  ; iterate driver+0xe0 array (2 entries)
0xfffffe0009009890  ldr  x16, [x20]         ; userClient vtable
0xfffffe000900989c  autda x16, x17
0xfffffe00090098a4  add  x16, x16, #0x2f0
0xfffffe00090098a8  ldr  x8, [x16]
0xfffffe00090098b8  blraa x8                ; virtual release()
```

The "stub" at `0xfffffe000902fea8` is a **PLT-style trampoline**:
`adrp x17, <page>; add x17, x17, #0x680; ldr x16, [x17]; braa x16, x17`.

Resolving the pointer it loads — `__DATA_CONST` at `0xfffffe00080e1680`, a chained fixup
(auth=1, key IA) — gives **`0xfffffe000b2ffac0`** in `__TEXT_EXEC`.

### What that function does

```
0xfffffe000b2ffac0  pacibsp
0xfffffe000b2ffacc  ldr  x16, [x0]        ; object vtable
0xfffffe000b2ffadc  autda x16, x17
0xfffffe000b2ffaec  mov  x17, #0x298
0xfffffe000b2ffb??  add  x16, x16, #0x298 ; vtable + 0x298
0xfffffe000b2ffae4  ldr  x8, [x16]
0xfffffe000b2ffaec  blraa x8              ; virtual call, x0 = object
0xfffffe000b2ffaf0  and  w0, w0, #1       ; return result & 1
0xfffffe000b2ffaf8  retab
```

It is a **boolean virtual-call wrapper**: call the method at vtable offset `+0x298` and return
its low bit. So whether `clientClosedGated` skips its release does **not** depend on a kernel
refcount comparison — it depends on what the *user client subclass* answers through its
`+0x298` method.

### Consequence
The dangling-pointer question now has a precise form: if the driver stores the userClient
pointer at `driver+0xe0` and releases it only when `+0x298` returns zero, then the pointer is
dangling exactly when that method keeps returning non-zero after `IOServiceClose`. The remaining
unknown is the user client's own `+0x298` implementation, recoverable from the JPEG user
client's vtable in the kext's `__DATA_CONST`.

This replaces the earlier speculative analysis; the `0xb8a2fc4` claim is withdrawn.


## Vtable identification attempt (2026-11-14)

To resolve what `+0x298` actually does, both candidate vtables were tested by decoding their
entries as chained fixups and checking how many land inside JPEG kext text
(`0xfffffe0009000000`–`0xfffffe0009040000`):

| candidate | entries into JPEG text | verdict |
|---|---|---|
| `0xfffffe00080dd320` (earlier session's "user client vtable") | 5 / 96 | **not a vtable** — claim withdrawn |
| `0xfffffe00080dbc80` (found by scanning `__DATA_CONST`/`__DATA` for contiguous runs of pointers into kext text) | 96 / 96 | a genuine function-pointer table, but its entry at `+0x298` decodes to `0xfffffe0106003…`, outside JPEG text |

So neither address is confirmed as the user client vtable:

- The `+0x298` slot of the 96-entry table does not resolve into the kext, which means either the
  table is something else (a dispatch or codec method table), or the vtable base assumed by the
  earlier analysis (`+0x298` from the object's vptr) is offset differently than assumed.
- C++ vtables are referenced through `__DATA_CONST` slots rather than `ADRP` code references, so
  a code-side xref scan for `0xfffffe00080dbc80` finds nothing — identification has to come
  from the object-creation path instead.

### Status of the UAF question
Still open, but narrowed: the release decision is made by a virtual call at vtable offset
`+0x298` (via wrapper `0xfffffe000b2ffac0`). Whether the pointer at `driver+0xe0` dangles
depends entirely on that method's behaviour after `IOServiceClose`. Identifying it requires
tracing `newUserClient` (`0xfffffe0009015df8`) to the allocation site and reading which
`OSMetaClass` vtable is installed on the new object.
