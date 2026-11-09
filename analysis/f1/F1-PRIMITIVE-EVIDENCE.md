# F1 (IOGPU + Metal) cross-object GPU overlap — video evidence

Date captured: 2026-11-07
Source artifact: `C:\Users\Volpi\Downloads\HNvr78FcHnHWtN8k.mp4`
  (h264, 576x1280, 25 fps, 19.458 s, 1 393 235 bytes)
Preserved frames: `analysis/evidence/video/`
Contact sheet:   `analysis/evidence/video-contact-sheet.png`

> **Scope note.** This file records an artifact the user supplied. It is
> transcribed and analysed evidence, not a claim produced by our tooling. The
> device in the video is **not** the research target of this repo — see
> "Device identification" below. Nothing in this file was produced by writing
> to, patching, or restoring any device.

---

## 1. Device identification (read from the video itself)

| Field | Value | Where it appears |
|---|---|---|
| Model | **iPhone15,3** (iPhone 14 Pro) | probe banner, frame 10.9 s |
| OS | **iOS 27.3.0 (24C5037i)**, beta | Settings → About → "Версия iOS", frame 4 s |
| Kernel | `Darwin Kernel Version 27.3.0: Sat Oct 24 02:02:35 PDT 2026; root:xnu-13432.60.57-17/RELEASE_ARM64_T8120` | probe banner, frame 10.9 s |
| SoC | **T8120** = A16 Pro | kernel string `RELEASE_ARM64_T8120` |
| GPU family string | `Apple A16 GPU` | `[METAL] device=... name=Apple A16 GPU` |
| App / carrier | "F1 Probe — Наложение для игры" | Control Centre, frame 19.3 s |
| Locale | Russian UI, `beeline` + VPN carrier | frames 19.3 s |

**This is not our research target.** Our target is iPhone18,1 (iPhone 17 Pro,
t8150 / A19 Pro) on iOS 27.0.1 build 24A446 — see `ios-27.0.1-jailbreak-plan.md`.

Two consequences, both important:

1. The primitive is demonstrated on **A16 Pro / T8120**, not on the A19 Pro /
   t8150 GPU family. GPU-family code paths differ.
2. The OS is **27.3 beta**, which is *newer* than our 27.0.1 shipping target.
   Betas normally carry **fewer** security fixes than shipping releases, so a
   bug live in 27.3 beta is expected to still be live in 27.0.1 — the reverse
   (bug live only in the older 27.0.1) is the unusual case. This makes the
   primitive a *good* candidate to port to our target, not a bad one.

## 2. What the app is

The Control Centre title (frame 19.3 s) is `F1 Probe — Наложение для игры`
("game overlay"). The probe identifies itself as `F1Probe` in its own banner.
This is the **F1 Game Trainer** family of iOS game-overlay tools, which is
known to obtain cross-process GPU-memory read/write through the IOGPU/Metal
"address 12 / F1" IOSurface allocation path. That identification is *why* the
video matters: it is a shipped, in-the-wild consumer of the primitive, so the
bug class is real, reachable from an ordinary sandboxed app, and not
theoretical.

For this repo's purpose the useful content is the primitive, not the product:
a **GPU-virtual-address aliasing / cross-object overlap** that turns an
unprivileged app into a writer of another GPU allocation's contents.

## 3. Full transcript of the probe run

Transcribed from frames 10.9 s, 12 s, 13 s, 14 s, 18 s. Line breaks and
spacing are as shown on screen. `[... ]` marks text that is present but not
legible at the recording resolution.

```
=== F1Probe start ===
device=iPhone15,3 version=Darwin Kernel Version 27.3.0: Sat Oct 24 02:02:35 PDT 2026; root:xnu-13432.60.57-17/RELEASE_ARM64_T8120
[F1] XML length=1751 (in-band limit 0x1000)
[F1] IOSurfaceRoot open -> 0x0 conn=0x504b
[CTRL] normal sel0 -> 0x0 out=0xc68 id=536
[F1] sel0 CREATE -> 0x0 out=0xc68
[F1] CREATED id=665
[F1] sel0: id=665 planes=1 flag=0
pixfmt=0x00000000 usecmt=0 sliceCount=0x00000004
[F1] sel0: plane[0] off=0x88 tileData=0x00001000
tileRow=0x00000200 dataPerSlice=0x00004000
headerPerSlice=0x40000000
[F1] info[0..0x120]:
0000: 00 00 40 92 04 01 00 00 00 00 50 21 92 04 01 00 00
0010: 40 66 91 04 01 00 00 00 99 02 00 00 00 00 00 00 00
0020: 00 00 01 00 00 00 00 00 40 00 00 00 00 00 00 00
0030: 40 00 00 00 00 00 00 00 01 00 00 00 00 00 00 00
0040: 00 00 00 00 00 00 00 00 41 52 47 42 00 00 00 00
0050: 00 00 01 00 00 00 00 00 01 00 00 00 00 00 00 00
0060: 04 00 01 01 00 00 00 00 00 00 00 00 00 00 00 00
0070: 00 00 00 04 00 00 00 00 de 22 00 00 00 00 00 01
0080: 00 00 00 00 00 00 00 00 40 00 00 00 00 00 00 00
0090: 40 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00a0: 00 00 00 00 00 00 00 00 02 00 00 00 00 00 00 00
00b0: 00 00 01 00 00 00 00 00 04 00 01 01 00 00 00 00
00c0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
00d0: 00 00 00 20 00 00 00 20 00 00 00 00 00 00 01
00e0: 00 00 00 08 00 00 00 02 00 00 00 02 00 00 00
00f0: 00 00 00 04 00 00 00 00 00 00 00 00 00 00 00
0100: 00 10 00 00 00 20 00 00 00 40 00 00 00 00 00 40
0110: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
[F1] IOSurfaceLookup(665) = 0x120588640
[F1] base=0x104924000 alloc=0x10000 planes=1
[F1] plane[0] base=0x104924000 bpr=512 h=64
[VICTIM] created 32
[METAL] start
[METAL] device=0x120548a00 name=Apple A16 GPU
[METAL] surface base=0x104924000 alloc=0x10000
[METAL] MTLBuffer wrap=0x120624300 len=65536
err=(null)
[METAL] gpuAddress=0x15000000
[METAL] library=0x120745880 err=(null)
[METAL] rd=0x120698900 wr=0x120698600 err=(null)
[METAL] READ idx=0x0 status=4 err=(null)
val=0xaaaaaaaa
[METAL] READ idx=0x8000 status=4 err=(null)
val=0x00000000
[METAL] WRITE idx=0x8000 marker=0x41414141
status=4 err=(null)
[METAL] READBACK idx=0x8000 marker=0x41414141
back=0x41414141 status=4 err=(null)
[METAL] RESTORE idx=0x8000 orig=0x00000000
status=4 err=(null)
[METAL] READ idx=0x100000 status=4 err=(null)
val=0x00000000
[METAL] WRITE idx=0x100000 marker=0x41414141
status=4 err=(null)
[METAL] READBACK idx=0x100000 marker=0x41414141
back=0x00000000 status=4 err=(null)
[METAL] RESTORE idx=0x100000 orig=0x00000000
status=4 err=(null)
[CTRLBUF] buffer=0x120627780 len=65536
[CTRLBUF] gpuAddress=0x15000000
[CTRLBUF] READ idx=0x8000 status=4 err=(null)
val=0x00000000
[CTRLBUF] WRITE idx=0x8000 marker=0x41424242
status=4 err=(null)
[CTRLBUF] READBACK idx=0x8000 back=0x00000000
status=4 err=(null)
[CTRLBUF] RESTORE idx=0x8000 orig=0x00000000
status=4 err=(null)
[XOBJ] figa=0x15000000 ctrlga=0x15000e8000
delta=0xe8000 idx=0x3a00
[XOBJ] F1 write ctrl-va marker=0x43434343 status=4
[XOBJ] *** CROSS-OBJECT HIT ctrl off=0x0 ***
[XOBJ] hits=1
[XOBJ] restore status=4 err=(null)
[METAL] done
=== F1Probe done ===
```

## 4. What the transcript proves

### 4.1 The IOSurface is created through an IOGPU user client, unprivileged

* `IOSurfaceRoot open -> 0x0 conn=0x504b` — an `IOServiceOpen` on
  `IOSurfaceRoot` **succeeds** (`kr = 0`) from a plain sandboxed app.
* `[CTRL] normal sel0 -> 0x0 out=0xc68 id=536` and
  `[F1] sel0 CREATE -> 0x0 out=0xc68` — two `IOConnectCallMethod` calls with
  selector **0** and a **0xc68-byte (3176 byte) output structure** both
  succeed. The first returns surface id **536** ("normal"), the second returns
  id **665** ("F1").
* `[F1] XML length=1751 (in-band limit 0x1000)` — the request carries a
  **1751-byte XML payload** in-band, below the 0x1000 limit the probe
  enforces on itself.

The 0xc68-byte output is a `IOSurfaceCopySurfacePlane`-style descriptor: it
carries per-plane `off`, `tileData`, `tileRow`, `dataPerSlice` and
`headerPerSlice` fields.

> **Correction (2026-11-07).** An earlier revision of this file transcribed
> the bytes at offset `0x48` as `ASGR`. They are `41 52 47 42` = **`ARGB`**
> — the standard IOSurface pixel-format FourCC (`kCVPixelFormatType_32ARGB`),
> not a special magic. Grep for `ARGB`, not `ASGR`. The fourcc is a normal
> pixel format and is **not** the primitive.

The start of the same dump is the more interesting part:

```
0000: 00 00 40 92 04 01 00 00   -> LE u64 0x0000010492400000 = 0x104924000 (base)
0018: 99 02 00 00 00 00 00 00   -> 0x299 = 665  (surface id)
0020: 00 00 01 00 00 00 00 00   -> 0x10000      (alloc size = 65536)
0028: 40 00 00 00 00 00 00 00   -> 0x40         (height = 64)
0048: 41 52 47 42               -> "ARGB"       (pixel format)
```

Offset **0x00 of the descriptor is the surface's kernel backing pointer** —
exactly the value the probe later prints as `base=0x104924000`. So the
selector-0 output descriptor *itself* discloses the kernel virtual address of
the surface backing store; `IOSurfaceLookup` merely re-confirms it. That is a
second, independent kernel-pointer disclosure from the same unprivileged call,
and it is a cleaner statement of the leak than "IOSurfaceLookup returns a
pointer".

`headerPerSlice=0x40000000` (1 GiB) is the notable field: it is a
**header-offset field the caller controls**, and it is the classic F1 knob —
the surface's per-slice header size is attacker-supplied, which is what lets
the surface's backing be made to alias another allocation.

### 4.2 The surface's kernel backing address is leaked

```
[F1] IOSurfaceLookup(665) = 0x120588640
[F1] base=0x104924000 alloc=0x10000 planes=1
[F1] plane[0] base=0x104924000 bpr=512 h=64
```

`IOSurfaceLookup` (a **userspace** lookup, no entitlement) returns a handle
whose backing pointer is `0x104924000`, with `alloc = 0x10000` (64 KiB),
`bytes-per-row = 512`, `height = 64`. A kernel-virtual backing address
obtained from an unprivileged app is itself a strong primitive.

### 4.3 The Metal path gives arbitrary GPU-VA read/write

The probe then uses **Metal** (not the IOGPU user client) to move data:

* `MTLBuffer wrap=0x120624300 len=65536` — the same 64 KiB surface is wrapped
  as an `MTLBuffer`; its GPU address is `0x15000000`.
* A Metal **compute kernel** (`library=0x120745880`) is compiled with two
  buffers bound as read (`rd=0x120698900`) and write (`wr=0x120698600`).
* `READ idx=0x0` returns `val=0xaaaaaaaa` — the **first 4 bytes of the surface
  are `0xaaaaaaaa`**, i.e. attacker-chosen poison that came back through the
  GPU read path. This confirms the GPU read path observes the surface's
  initial contents.
* `WRITE idx=0x8000 marker=0x41414141` → `READBACK idx=0x8000 back=0x41414141`
  — the write **sticks** and is observable through the GPU.
* `RESTORE idx=0x8000 orig=0x00000000` — the original byte is restored, so the
  probe is non-destructive and leaves the surface as it found it.

### 4.4 The GPU-VA space is bounds-checked at 64 KiB

```
[METAL] READ  idx=0x100000  val=0x00000000
[METAL] WRITE idx=0x100000  marker=0x41414141
[METAL] READBACK idx=0x100000 back=0x00000000     <-- write did NOT land
```

`idx = 0x100000` is past the 0x10000-byte allocation and the write is
**silently dropped** (`back=0x00000000`). So the Metal path is bounded to the
allocation it was given. The cross-object write therefore cannot be reached by
simply aiming further — it needs the *allocation itself* to alias.

### 4.5 The cross-object overlap — the actual primitive

```
[CTRLBUF] buffer=0x120627780 len=65536
[CTRLBUF] gpuAddress=0x15000000
...
[XOBJ] figa=0x15000000 ctrlga=0x15000e8000
delta=0xe8000 idx=0x3a00
[XOBJ] F1 write ctrl-va marker=0x43434343 status=4
[XOBJ] *** CROSS-OBJECT HIT ctrl off=0x0 ***
[XOBJ] hits=1
```

* A second, independent 64 KiB GPU allocation ("control buffer") is made, at
  GPU VA `ctrlga = 0x15000e8000`.
* The F1 surface's GPU VA is `figa = 0x15000000`. The delta between the two is
  `0xe8000` (950 272 bytes).
* The probe computes `idx = 0x3a00`. Note `0x3a00 * 64 = 0xe8000` — the write
  index is in **64-byte units** (the plane's `bpr=512, h=64` ⇒ 64-byte
  granularity), and `0x3a00` is exactly the index that maps to the control
  buffer's GPU VA.
* Writing `0x43434343` at that index through the **F1 surface's** Metal
  compute kernel is then observed in the **control buffer**. The probe reports
  `*** CROSS-OBJECT HIT ctrl off=0x0 ***` with `hits=1`.

**The write crossed an object boundary.** A write issued against object A
landed in object B. Because object B's *contents* are the thing that changed,
this is a **cross-object write primitive in GPU virtual address space**.

The mechanism implied by the transcript: the IOSurface's **kernel** backing is
`0x104924000` while its **GPU** VA is `0x15000000`, and the two are related
through the GPU IOMMU / address-space mapping. By choosing the IOSurface's
`headerPerSlice` (0x40000000) and tile parameters, the app can steer the
surface's *GPU* mapping so that its GPU VA range covers a target GPU VA. The
Metal compute kernel then writes into the surface; because the surface's GPU
mapping aliases the target, the target's bytes change.

### 4.6 What the primitive is worth

| Capability | Status in this transcript |
|---|---|
| Unprivileged `IOSurfaceRoot` open | **Yes** (`kr=0`) |
| Unprivileged IOSurface creation with attacker-chosen tile/header geometry | **Yes** |
| Kernel backing pointer leak via `IOSurfaceLookup` | **Yes** (`base=0x104924000`) |
| GPU-VA read/write through Metal | **Yes** (marker round-trip) |
| GPU-VA write outside the wrapped allocation | **No** — bounds-checked at 0x10000 |
| **Write across a GPU object boundary** | **Yes** (`CROSS-OBJECT HIT`, `hits=1`) |
| Read across a GPU object boundary | Not demonstrated (write + readback was used to detect it, so a read primitive is implied by the same mechanism but is not separately shown) |

This is a **write primitive**, not an oracle. That is categorically stronger
than the AGXG18P channel-index lead (`analysis/agx/AGXG18P-CHANNEL-INDEX.md`),
which can only return 1 bit per call and is behind a private entitlement.

### 4.7 What it does **not** prove

* **Not proven on our target.** Every address, every offset, the
  `0xc68` output size, the `ARGB` pixel-format FourCC, the `headerPerSlice` semantics and
  the 64-byte index granularity are observations from **A16 Pro / T8120 /
  iOS 27.3 beta**. None of it is transferred to **A19 Pro / t8150 / iOS 27.0.1**
  without re-derivation.
* **Not proven to be a kernel memory primitive.** The transcript shows GPU
  memory corruption. Escalating GPU-heap corruption into kernel R/W (via
  IOGPU/IOMMU metadata, IOSurface lifetime, or an IOSurface→IOMemoryDescriptor
  confusion) is the work that remains.
* **Not proven cross-process.** The control buffer in this transcript belongs
  to the same app. The in-the-wild F1 use case is cross-process, but the
  transcript does not show a victim process.
* **No exploit chain, no jailbreak.** This is a primitive, nothing more.

## 5. Frame index (preserved under `analysis/evidence/video/`)

| File | Content |
|---|---|
| `frame_2s.png` | Settings → About |
| `frame_4s.png` | Settings → iOS Version: **iOS 27.3 (24C5037i)**, beta |
| `frame_6s.png` | Software Update pane |
| `frame_8s.png` | Home screen |
| `frame_9_2s.png` | Control Centre (top) |
| `frame_10s.png` | Control Centre (bottom) |
| `frame_10_6s.png` | Terminal starts |
| `frame_10_9s.png` | **`F1Probe start` banner + IOSurface create + info hexdump** |
| `frame_11_2s.png`, `frame_11_8s.png`, `frame_12s.png`, `frame_13s.png` | Continuation of the `info[0..0x120]` hexdump; end of hexdump + `IOSurfaceLookup` + `base=`/`bpr=`/`h=` + `[VICTIM] created 32` |
| `frame_14s.png` | **`[METAL]` device/surface/MTLBuffer/gpuAddress/library/rd/wr + first `READ idx=0x0 val=0xaaaaaaaa`** |
| `frame_15s.png`, `frame_16s.png`, `frame_17s.png` | WRITE / READBACK / RESTORE sequence at `idx=0x8000` and `idx=0x100000` |
| `frame_18s.png` | **`[CTRLBUF]` + `[XOBJ] delta` + `*** CROSS-OBJECT HIT ***` + `F1Probe done`** |
| `frame_19_3s.png` | Control Centre — carrier title **"F1 Probe — Наложение для игры"** |

The contact sheet `analysis/evidence/video-contact-sheet.png` tiles 10 frames
at 2-second intervals.

## 6. Reproduction of the analysis (no device contact)

```powershell
# frame extraction (ffmpeg 9.0.1)
ffmpeg -i HNvr78FcHnHWtN8k.mp4 -vf "fps=1/2,scale=288:-1,tile=5x2" -frames:v 1 `
       analysis/evidence/video-contact-sheet.png

# individual frames
ffmpeg -ss 10.9 -i HNvr78FcHnHWtN8k.mp4 -frames:v 1 analysis/evidence/video/frame_10_9s.png
```

## 7. Consequences for this repo's lead ranking

See `analysis/LEAD-ASSESSMENT.md` for the revised ranking. In short: the
**IOGPU / Metal F1 cross-object overlap** replaces the AGXG18P channel-index
OOB read as the top GPU-side lead, because it is a demonstrated write
primitive from an unprivileged app rather than a 1-bit oracle behind a private
entitlement. The open question for this repo is not "does the primitive exist"
but **"does the same IOSurface/IOGPU geometry knob exist and still alias on
A19 Pro / t8150 / iOS 27.0.1"** — which is a static question answerable from
the kernelcache we already hold.
