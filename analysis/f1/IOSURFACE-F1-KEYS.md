# IOSurface — F1 geometry keys on t8150 / iOS 27.0.1 (24A446)

Date: 2026-11-08
Target: iPhone18,1 / V53AP / A19 Pro / t8150 / iOS 27.0.1 build 24A446
Source: `firmware/24A446/kernelcache.release.macho` (MH_FILESET)
Status: **static confirmation** — the F1 geometry knob exists on our target.

---

## 1. Where the F1 path actually lives

The earlier working assumption was that the IOSurface/F1 allocation path is in
`com.apple.iokit.IOGPUFamily`. **That is wrong.** String attribution shows:

| kext | `Slice`/`PerSlice`/`TileData`/`IOSurfaceAddress` strings |
|---|---|
| `com.apple.iokit.IOSurface` | **present** (`PerSlice` ×10, `Slice` ×11, `TileData` ×5, `IOSurfaceAddress` ×4) |
| `com.apple.iokit.IOGPUFamily` | **absent** (0 hits) |

The IOSurface object, its property parser, its user client
(`IOSurfaceRootUserClient`) and its property keys all live in
`com.apple.iokit.IOSurface`. That is the kext to read for the F1 primitive.

### Extraction

```powershell
cd G:\iOS 27.0.1\iOS
.\tools\ipsw\ipsw.exe kernel extract firmware\24A446\kernelcache.release.macho `
    com.apple.iokit.IOSurface -o analysis\f1\extract --force
```

| file | size | SHA-256 |
|---|---|---|
| `analysis/f1/extract/com.apple.iokit.IOSurface` | 314 376 | `8c2180448de8fb2ad6b4dcf311646d834e41711caac3eef8cf8a937e1361f93f` |
| `analysis/f1/extract/com.apple.iokit.IOGPUFamily` | 414 016 | (no F1 strings) |

---

## 2. The AIO reference fields map to real IOSurface property keys

The A16 / 27.3-beta transcript
(`analysis/f1/F1-PRIMITIVE-EVIDENCE.md` §3) prints a selector-0 descriptor
with these fields. Each one is a real, named IOSurface property on t8150 /
27.0.1:

| transcript field (A16) | IOSurface property key on t8150 | file offset in the kext |
|---|---|---|
| `planes` | `IOSurfacePlaneInfo` | `0x100c`, `0x1c37`, `0x3e50` |
| `pixfmt` | `IOSurfacePixelFormat` | `0xfce` |
| `sliceCount` | `IOSurfaceSliceCount` | `0x1869` |
| plane `off` | `IOSurfacePlaneOffset` | `0x101f` |
| plane size | `IOSurfacePlaneSize` | — |
| `tileData` | `IOSurfacePlaneBytesPerTileData` | `0x1826` |
| `tileRow` | `IOSurfacePlaneBytesPerRowOfTileData` | `0x1845`, `0x4d8d` |
| `dataPerSlice` | `IOSurfacePlaneDataRegionBytesPerSlice` | `0x187d`, `0x524c`… |
| **`headerPerSlice`** | **`IOSurfacePlaneHeaderRegionBytesPerSlice`** | `0x18a3`, `0x53f1`… |
| alloc size | `IOSurfaceAllocSize` | `0xfe3` |
| width / height / bpr / bpe | `IOSurfaceWidth` / `IOSurfaceHeight` / `IOSurfaceBytesPerRow` / `IOSurfaceBytesPerElement` | — |

**Conclusion 1.** Every geometry knob the F1 primitive depends on exists on
our exact target build. The single field that matters most —
`headerPerSlice`, the caller-controlled 1 GiB value in the transcript — is
`kIOSurfacePlaneHeaderRegionBytesPerSlice`, and it is present.

---

## 3. These fields are validated — and that is the real question

Presence of a key is not the same as an unvalidated key. The kext contains a
family of validation strings (exact bytes, from the same binary):

```
IOSurface: kIOSurfacePlaneHeaderRegionBytesPerSlice %d exeeds maximum value.
IOSurface: kIOSurfacePlaneHeaderRegionBytesPerSlice %d is smaller than expected value %d .
IOSurface: kIOSurfacePlaneHeaderRegionBytesPerSlice must be present for multi-slice plane %d with sliceCount %d .
IOSurface: kIOSurfacePlaneDataRegionBytesPerSlice %d exceeds maximum value.
IOSurface: kIOSurfacePlaneDataRegionBytesPerSlice %d is smaller than expected value %d .
IOSurface: kIOSurfacePlaneDataRegionBytesPerSlice must be present for multi-slice plane %d with sliceCount %d .
IOSurface: multi-slice interchange compressed plane[%d] (DataRegionBytesPerSlice %d + HeaderRegionBytesPerSlice %d) * sliceCount %d size is greater than total planeSize %lld
IOSurface: sliceCount provided %d is out of bound for maximum / minimum number of required slices.
```

So on t8150 the per-slice header/data values are **checked against a maximum**
(and a minimum) and must be present for multi-slice planes. The F1 transcript
on A16 has `sliceCount=4` with `headerPerSlice=0x40000000` and
`dataPerSlice=0x4000`, and it succeeded there — so whatever the maximum is, it
does not reject `0x40000000` on A16.

**The open question is therefore precise and testable:**

> On t8150/27.0.1, what is the maximum accepted
> `IOSurfacePlaneHeaderRegionBytesPerSlice`, and does the accepted value still
> produce a GPU mapping that aliases another allocation?

That is a *device* question, and it is now a cheap one, because the Mac with
Xcode is available and the property keys are known.

---

## 4. Two adjacent primitives worth noting (also present on t8150)

The same kext exposes, on our target build:

* **`IOSurfaceAddressRanges` / `IOSurfaceAddressOffset` / `IOSurfaceAddressFormat`**
  — properties that let a surface be described in terms of caller-supplied
  address ranges. There is a check string
  `%s error - Address ranges do not cover requested allocation size`, so this
  path is guarded, but it is the closest thing in the kext to a
  "map this surface over these addresses" primitive and deserves a read.
* **`IOSurfaceSuperbuffer` / `IOSurfaceAllocateFromSuperbuffer` /
  `IOSurfaceDeviceMemoryRegion`** — surface-from-preexisting-memory paths,
  i.e. the "wrap an existing allocation" shape a cross-object overlap needs.
* **`com.apple.private.IOSurface.protected-access`** — a private entitlement
  string. Whether any of the above is gated on it must be established, not
  assumed.

---

## 5. Confidence and limits

| claim | basis | confidence |
|---|---|---|
| F1 keys live in `com.apple.iokit.IOSurface`, not IOGPUFamily | string attribution over both extracted kexts | **high** |
| `kIOSurfacePlaneHeaderRegionBytesPerSlice` exists on 24A446 | exact string in the extracted binary | **high** |
| per-slice values are range-checked on t8150 | exact validation strings in the binary | **high** |
| `0x40000000` is accepted on t8150 | — | **unknown** (device test needed) |
| the accepted value still aliases another allocation | — | **unknown** (device test needed) |
| anything is gated on `com.apple.private.IOSurface.protected-access` | — | **unknown** |

Nothing in this document was produced by writing to, flashing, restoring or
updating any device. It is pure static analysis of a kernelcache already held
in this repo.

## 6. Next step

Write a **read-only geometry-acceptance probe** for the Mac/Xcode pipeline:

1. `IOSurfaceCreate` with a caller-controlled plane dictionary carrying
   `IOSurfacePlaneHeaderRegionBytesPerSlice`, `…DataRegionBytesPerSlice`,
   `…BytesPerRowOfTileData`, `…BytesPerTileData`, `IOSurfaceSliceCount`.
2. Scan `headerPerSlice` upward (e.g. `0x1000 … 0x40000000 … 0xFFFFFFFF`) and
   log accept/reject plus the returned surface's `IOSurfaceGetBaseAddress`,
   `IOSurfaceGetAllocSize`, `IOSurfaceGetBytesPerRow`, `IOSurfaceGetHeight`.
3. **No writes, no Metal, no cross-object attempt.** The probe only answers
   "which geometry values does the kernel accept on t8150, and what does the
   resulting surface look like". A rejected value returns `NULL`; that is a
   safe outcome.

Only if step 3 shows the geometry is still caller-controlled *and* the shape
matches A16 would a Metal-based overlap test be justified — and that would be
a separate, explicitly-authorised step.
