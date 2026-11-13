# AppleJPEGDriver research — session status (2026-11-08, continued)

## Milestone: selector dispatch table recovered (2026-11-08)

The open problem recorded in `APPLEJPEGDRIVER-SURFACE.md` §"Open problems" #1 is
**resolved**.

* User client: `AppleJPEGDriverUserClient`, vtable pointer `0xfffffe00080dd320`.
* Static dispatch table: `__DATA_CONST.__const`, VA `0xfffffe00080dd990`,
  **10 entries × 40 bytes** (`IOUserClientMethodDispatch`: fn @ +0, checkScalarInput
  @ +8, checkStructureInput @ +0xc, checkScalarOutput @ +0x10, checkStructureOutput
  @ +0x14).
* Consumed by kernel core `sub_fffffe000b37475c` via stub `__stub_fffffe000b8acf58`,
  `dispatchCount = 0xa`.

### Recovered table

| sel | dispatch fn | codec fn | structIn | structOut | gate |
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
| 9 | 0x90164d8 | 0x9009c3c | 0 | 0 | gated (`com.apple.applejpegdriver.poweron`) |

Selector = table index.

## Consequence

The codec path for selectors 1–7 is reachable without any `com.apple.private.*`
entitlement, and takes caller-supplied structure buffers (88 / 4096 / 3488 bytes).

## Probe status (AGXProbe)

* `tools/opencode-temp/ReachProbe.swift` extended with `runJPEGProbe()`:
  * `IOServiceGetMatchingServices("AppleJPEGDriver")`
  * per service: `IOServiceOpen(type=0)`
  * per selector in `[1, 3]`: build `IOExternalMethodArguments`
    (version/selector/scalarInput/structureInput(88)/structureOutput(88)) + single
    `IOExternalMethodDispatch` entry (fn = `jpegEntry`, checks all zero/88) and
    `IOConnectMethod(conn, sel, &args, &dispatch, 1, 0)`.
* Build: **BUILD_RC=0** (twice), install: OK, launch: OK.
* Author-run paths verified: `--autorun` writes the v8 sweep log (works).
  `--autorun-jpeg` and no-arg launches did not produce a new log; the currently
  running process appears to have been the source of the last successful v8 write.

## Next steps

1. Get a clean JPEG-probe autorun to actually fire and capture a `runJPEGProbe` log.
2. Reconstruct the three input structs field-by-field and pick a *meaningful*
   structure (not all-zero) to drive `startDecoder` / `startEncoder`.
3. Watch for kernel crash (`EXC_BAD_ACCESS` in codec / `kdebug` traces) with crash-log
   pulling armed.

## Honest position

No jailbreak bootstrap, Sileo package, or patch has been produced and none is
implied by these findings. The only concrete, verified, on-device-reachable,
attacker-data-consuming surface on this device is `AppleJPEGDriver`'s codec path,
whose selector table has now been fully recovered.
