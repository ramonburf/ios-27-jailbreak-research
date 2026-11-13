# AGXProbe / AppleJPEGDriver — end-of-session state (2026-11-08, continued)

## Completed this session

1. **Selector dispatch table recovered** (was the top open problem in
   `analysis/reach/APPLEJPEGDRIVER-SURFACE.md`).
   * User client vtable: `0xfffffe00080dd320`.
   * Dispatch table: `__DATA_CONST.__const`, VA `0xfffffe00080dd990`, **10 entries × 40 B**.
   * Consumed by kernel core `sub_fffffe000b37475c` (`__stub_fffffe000b8acf58`),
     `dispatchCount = 0xa`.
2. **Dispatch table contents** recovered and mapped to codec entry points, struct
   sizes (in/out) and gating. See
   `analysis/reach/JPEG-CODEC-CALLCHAIN-2026-11-08.md`.
3. **Codec entry points ungated** for selectors 1–7 (startDecoder/startEncoder and
   Ext/2024 variants); selectors 8/9 (power on/off) gated by
   `com.apple.applejpegdriver.poweron`.
4. **Field offsets observed in `startDecoder`** (0x900bdf4) recorded in the callchain
   doc.

## Deliverables touched

* `analysis/reach/APPLEJPEGDRIVER-SURFACE.md` — added "Dispatch table (RECOVERED)",
  updated Status and Open problems / Next steps.
* `analysis/reach/JPEG-CODEC-CALLCHAIN-2026-11-08.md` — new: dispatch + call chain + fields.
* `analysis/reach/JPEG-RESEARCH-2026-11-08-CONT.md` — new: session status.
* `analysis/reach/AGXPROBE-JPEG-PROBE-STATUS.md` — new: probe status.
* `analysis/LEAD-ASSESSMENT.md` — added §12 (dispatch table recovered, consequence).

## Probe engineering state

* `tools/opencode-temp/ReachProbe.swift` extended with `runJPEGProbe()`.
* Builds: BUILD_RC=0 (build11/12/13).
* Installs + launches OK; `--autorun` writes the v8 log (works).
* `--autorun-jpeg` / default launches: no new log (app process residency issue).

## Blocking item

A clean `runJPEGProbe` capture is still needed before driving selector 1 with a
structurally valid (or zeroed) 88-byte structure.

## Next moves

1. Terminate the currently-resident AGXProbe process cleanly and relaunch with
   `--autorun-jpeg`; capture the v9 log.
2. Drive selector 1 (`startDecoder`) and selectors 3/4/5/6/7 with shaped structures.
3. Watch for kernel fault / bad-argument transitions with crash-log pulling armed.
