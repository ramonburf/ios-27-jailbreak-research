# Type-5 DeviceN PDF probe (iOS 27.0.1)

This directory contains minimal PDFs that exercise the `CGPDFShadingType5Init`
path with a `DeviceN` colour space that has more than four components.

## Why this file

The 27.0.1 -> 27.2 patch diff records a CoreGraphics fix:

```
27.2:  cmp  x9, #0x4        ; x9 = numComponents
       b.hi <bail>
       cmp  x10, x9
       b.ne <bail>
```

The 27.0.1 parser writes the per-vertex colour components into a fixed
four-`double` inline array.  A `DeviceN` space with more than four components
overruns it.  The reachable input is a PDF with a Type-5 (lattice) shading
whose `ColorSpace` is `DeviceN` with `numComponents > 4`.

These files are **crash probes**, not a weaponised exploit.  They are intended
for the secondary iPhone on 27.0.1, not the Mac (macOS 27.3 includes the fix).

## Files

| File | Components | Notes |
|---|---|---|
| `type5_devicen4.pdf` | 4 | control; should render black |
| `type5_devicen5.pdf` | 5 | first value over the fixed array |
| `type5_devicen8.pdf` | 8 | 4-double overrun |
| `type5_devicen16.pdf` | 16 | larger overrun |
| `type5_devicen8_flags.pdf` | 8 | flag-byte variant; less likely to be the correct layout |

All files use a 2x2 lattice (four vertices), `/BitsPerCoordinate 8`,
`/BitsPerComponent 8`, and a Type-4 tint transform that returns solid black.
They render in MuPDF (the 16-component file only warns that the colour space
is too large for MuPDF's cache).

## Device placement

The PDFs were pushed to:

```
/var/mobile/Media/Downloads/       (AFC media root)
```

They can also be placed in an app container that exposes file sharing.  The
installed `uk.prevolut.chapper` app has `UIFileSharingEnabled` and
`LSSupportsOpeningDocumentsInPlace`, so its Documents folder is visible in
Files.  Pushing there requires the phone to be unlocked (AFC returns
`PERM_DENIED` while the data protection class is locked).

## Test procedure

1. Unlock the secondary iPhone and keep it awake.
2. Open **Files** -> **On My iPhone** -> **Downloads** (or the Chapper folder).
3. Tap `type5_devicen4.pdf` first.  It should open and show a black page.
   This confirms the viewer is rendering the shading path.
4. Tap `type5_devicen8.pdf`.
5. Watch for the preview closing, a blank/black screen, or a respring.
6. Pull crash logs:

   ```powershell
   .\tools\ipsw\ipsw.exe idev crash ls
   .\tools\ipsw\ipsw.exe idev crash pull -o analysis\ios\crashes
   ```

   Look for `QuickLookUIService`, `Chapper`, `PDFKit`, `CoreGraphics`, or
   `CGPDFShadingType5Init` in the log.

If Files does not show the Downloads folder, use the local HTTP server:

```
http://<host>:8000/type5_devicen8.pdf
```

Open that URL in Safari on the phone (same Wi-Fi as the PC).

## Safety

- This is a userland memory-corruption probe.  The expected worst case is a
  crash of the PDF/Quick Look process and a possible respring.
- Do not run it on the daily phone.
- If the phone panics or reboots, stop and pull the panic log before doing
  anything else.
- No firmware, boot-chain, or restore operations are involved.

## Next step after a crash

A crash log identifies the faulting frame and the overwritten register/return
address.  That is the starting point for determining whether the overrun is a
controllable primitive.  A crash alone is not a jailbreak; the chain still
needs a sandbox escape and a kernel primitive.
