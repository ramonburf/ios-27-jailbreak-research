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
