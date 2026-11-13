# AppleJPEGDriver — method inventory (2026-11-08, continued)

Source of truth: `tools/opencode-temp/lifetime-triage/cstrings_jpeg.txt` (kext string table)
plus `tools/opencode-temp/lifetime-triage/disasm/com_apple_driver_AppleJPEGDriver.__TEXT_EXEC___text.txt`.

## Driver class

- `AppleJPEGDriver::init`, `probe`, `start`, `attachCoreAnalyticsService`,
  `setPowerState_gated`, `newUserClient`, `clientClosedGated`, `turnOnJPEGHW_gated`,
  `interruptOccurred_gated`, `isSurfaceMultiPlane`, `doRestOfBufferSetupForDecode_gated`,
  `doRestOfBufferSetupForEncode_gated`, `setupBuffersForCoding_gated`, `begin_io_gated`,
  `finish_io_gated`, `sleepCommandGate`, `queue_io_gated`, `hw-type`, `getCPUType`,
  `showRequestInfo`, `dumpBitstream`, `getMCUSize`, `convertToRequestSubSampleMode`,
  `release_codec_gated`, `checkDARTException`, `assign_codec_gated`.

## QueueManager

- `QueueManager`, `deQueue`.

## HAL layer (`AppleJPEGHal`)

- `init`, `pollingForAXI`, `interruptOccurred_gated`, `checkForInterrupt`,
  `createInterruptEventSource`, `showErrorRequestInfo`, `finishCoding_gated`,
  `executeOperation_gated`, `enableDeviceClockWrapper`, `enableDeviceClockLowLevel`,
  `checkHardwareVersion`, `startDecoderGated`, `startEncoderGated`, `singleClockIndexDevice`.

## Request handling (`RequestHandling`)

- `matrixConvYUVtoRGBA`, `encodeRequestValidation`, `decodeRequestValidation`,
  `decodeHWRequestSetup`, `encodeHWRequestSetup` (+ likely `encodeHWRequestFinish`,
  `decodeHWRequestFinish`, etc.).

## Codec / dart layers

- `TulipaFunctions`, `DaisyFunctions`, `ClaryFunctions`, `ThymeFunctions`, `IxoraFunctions`,
  `BorageFunctions`, `DandelionFunctions`, `NerineFunctions`, `CatnipFunctions`, `DahliaFunctions`,
  `KopsiaFunctions`, `LotusFunctions`, `CloverFunctions`, `StockFunctions`, `HibiscusFunctions`,
  `LegacyFunctions`, `TansyFunctions` — each exposing `setupAXIRegisterOffset(uint32_t, uint64_t)`.

## Map / buffer layers

- `AppleJPEGDart::registerMapper`, `setParameter`, `iomd-cache-size`, `iomd-cache-ttl`,
  `registerErrorHandler`, `setActive`, `cacheFlushInactive`, `mapMemoryDescriptor`,
  `unmapMemoryDescriptor`, `setIomdCacheAttribute`, `iomdEarlyReclaim`, `iomdEarlyPurge`.

- `AppleJPEGDriver::doRestOfBufferSetupForDecode_gated`, `doRestOfBufferSetupForEncode_gated`,
  `setupBuffersForCoding_gated` — these take a `JpegRequest *` and complete buffer setup
  using the memory descriptors registered by the dart layer.

- `AppleJPEGHal::executeOperation_gated(ajpeg_setup_t *)` — the central dispatch into the
  actual codec (Tulipa/Daisy/...).

## Entitlements / gates

- `IOUserClientEntitlements`, `IOUserClientDefaultLocking`,
  `IOUserClientDefaultLockingSetProperties`, `IOUserClientDefaultLockingSingleThreadExternalMethod`.
- `com.apple.applejpegdriver.poweron` — gate for `setPowerState_gated`, `clientClosedGated`.
- `com.apple.applejpegdriver.ajpegtestapp` — presumably the internal test app namespace.

## Implications for probing

1. `AppleJPEGDart::mapMemoryDescriptor` is un-suffixed with `_gated`, i.e. not behind the
   power gate — but it is called from gated paths, so reachability still depends on the
   driver state.
2. `RequestHandling::decodeRequestValidation` / `encodeRequestValidation` are the natural
   places to find the input-size checks that `AppleJPEGDriver::startDecoder` performs before
   delegating.
3. The `QueueManager` / `deQueue` pair likely implements the work queue for codec operations.

## Status

- Selector dispatch table: **recovered** (see `JPEG-CODEC-CALLCHAIN-2026-11-08.md`).
- Driver methods: enumerated above; disassembly reads in progress.
- Probe autorun: blocked by stale app process; build/signing hygiene now understood.
