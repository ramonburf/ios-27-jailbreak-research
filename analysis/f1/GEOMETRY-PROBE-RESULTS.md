# IOSurface geometry-acceptance probes on t8150 / iOS 27.0.1 — 2026-11-08

> **UPDATE 2026-11-12 — the direct route is OPEN, not closed.**
> §9 concluded that driving the `IOSurfaceRoot` user client directly was closed
> because every shape returned `0xe00002c2`.  That conclusion was wrong: the
> **scalar input must be `0`**.  With `scalarIn[0] = 0` the call succeeds on
> **both** target devices (13 Pro / 24A5390f and 17 Pro / 24A446), the per-slice
> validation block in the kernel **is** reached and **is** live, and the
> 32-bit `(data + header) * sliceCount` overflow is reachable unprivileged.
> See the Addendum at the end of this file.

**Device:** iPhone18,1 / iPhone 17 Pro / t8150 — iOS 27.0.1 (24A446), UDID `00008150-00095CD93444C01C`
**Harness:** `~/agx-probe-project` (Xcode 27.2), app `com.nianticlabs.pokemongo.4L9HF29JJU`
**Safety:** every probe below is read-only — no Metal, no GPU submission, no writes to
any surface, no cross-object attempt. Surfaces are created, inspected, released.

---

## 0. Executive summary

| Question | Answer |
|---|---|
| Is the `IOSurfaceCreate` parser strict about unknown keys? | **No** — unknown keys are silently ignored. |
| Are single-plane dictionaries accepted? | **Yes** (with self-consistent geometry). |
| Is `IOSurfacePlaneSize` validated against `AllocSize`? | **Yes** — rejection. |
| Is `IOSurfacePlaneOffset` validated to fit? | **Yes** — rejection. |
| Are `IOSurfacePlaneHeaderRegionBytesPerSlice` / `…DataRegionBytesPerSlice` bounded? | **No observed bound** — `0xffffffff` accepted with a 16 KB allocation. |
| Are those per-slice values *proven* to be stored/consumed? | **No.** §6 shows the kernel parser is not reached through `IOSurfaceCreate` at all. |
| Are same-size IOSurface allocations contiguous? | **Yes** — exact `0x10000` stride over four surfaces. |
| Does the kext contain per-slice validation code? | **Yes** — with a 32-bit `(data+header)*sliceCount` multiply (§7). |
| Is that code reachable via `IOSurfaceCreate`? | **No** — it is gated and the gate keys are sanitized away by the userspace library (§6). |
| Is that code reachable via the `IOSurfaceRoot` user client directly? | **No evidence of it** — selector 0 returns `kIOReturnBadArgument` for every input shape and payload encoding tried (§9). |

The **only** hard finding is negative-but-useful: the kernel does *not* reject a
surface whose declared per-slice regions vastly exceed its allocation, while it
*does* reject plane-level oversubscription. That asymmetry is the thing worth
pursuing. It is **not** yet a primitive, because we have not shown the per-slice
values are consumed.

---

## 1. Probe v1 — first attempt (superseded)

`geom.log`, 2026-11-08 14:34 UTC.

Design: sweep `IOSurfacePlaneHeaderRegionBytesPerSlice` on an invented
"F1-shaped" plane dictionary, compare against the A16/27.3β transcript.

Result: **every** plane-dict case was rejected, including the control.

```
plain 64x64:  OK base=0x10054c000 alloc=0x4000 bpr=256 h=64 w=64 pf=0x42475241
plain 512x64: OK base=0x10054c000 alloc=0x20000 bpr=2048 h=64 w=512
f1base hdr=0x4000: REJECTED
hdrPerSlice=0x0 … 0xffffffff: all REJECTED
```

**v1 conclusion was wrong** if read as "the kernel refuses this geometry." The
dictionary was malformed:

* `IOSurfacePlaneWidth = 512`, `IOSurfacePlaneBytesPerElement = 4` requires
  `IOSurfacePlaneBytesPerRow >= 2048`; v1 supplied `512`.
* `IOSurfacePlaneOffset = 0x88` is not aligned to the plane's required
  alignment.
* `sliceCount = 4` with two `0x4000` regions per slice implies `0x20000`
  of coverage against `AllocSize = 0x10000`.

v1 is retained only as evidence that **the parser does validate plane-level
geometry consistency** (the kext string `Address ranges do not cover requested
allocation size` matches this class of failure).

Also note: `pf=0x42475241` is the little-endian uint32 whose byte order in
memory is `41 52 47 42` = ASCII `ARGB`. So the descriptor bytes at `+0x48`
recorded in `F1-PRIMITIVE-EVIDENCE.md` are consistent with the numeric fourcc
`'BGRA'` (0x42475241) stored little-endian, **not** a byte string. The earlier
"ARGB vs ASGR" correction stands on the bytes, but the *field role* should be
described as "a 32-bit pixel-format value whose memory bytes spell ARGB", not
"an ASCII string field".

---

## 2. Probe v2 — controls and separation

`geom2.log`. Purpose: separate "malformed dictionary" from "geometry refused".

### A. Parser strictness — all accepted

```
A1 plain 64x64                          OK alloc=0x4000 planes=0
A2 plain + IOSurfaceTotallyUnknownKey=1 OK alloc=0x4000 planes=0
A3 plain + IOSurfaceSliceCount=1        OK alloc=0x4000 planes=0
A4 plain + IOSurfaceSliceCount=4        OK alloc=0x4000 planes=0
A5 plain + IOSurfaceBogus="hello"       OK alloc=0x4000 planes=0
```

→ Unknown keys are ignored. Any rejection elsewhere is therefore about a **known**
key's value, not about key presence.

### B. Minimal plane trees

```
B1 1 plane 64x64 off=0 size=0x4000      OK planes=1
B2 1 plane, offset/size omitted         OK planes=1
B3 2 planes 64x64 @0/0x4000             REJECTED
B4 1 plane + SliceCount=1               OK planes=1
B5 1 plane + SliceCount=4 alloc=0x10000 OK planes=1
```

B3's rejection is a geometry-consistency failure (the two-plane layout did not
match the declared top-level `Width/BytesPerRow`), not a slice issue.

### C. Per-slice region keys on a valid single-plane tree — all accepted

```
hdr=0x0       sc=1 alloc=0x4000     OK
hdr=0x1000    sc=1 alloc=0x5000     OK
hdr=0x4000    sc=1 alloc=0x8000     OK
hdr=0x10000   sc=1 alloc=0x14000    OK
hdr=0x100000  sc=1 alloc=0x104000   OK
hdr=0x1000000 sc=1 alloc=0x1004000  OK
hdr=0x0       sc=4 alloc=0x10000    OK
hdr=0x4000    sc=4 alloc=0x20000    OK
hdr=0x1000000 sc=4 alloc=0x4010000  OK
data=0x1000/0x4000/0x10000 sc=4     OK
tileRow=0x100/0x200/0x400           OK
tileData=0x400/0x800/0x1000         OK
```

### D. Deliberately inconsistent arithmetic — the interesting part

```
hdr=0x40000000  sc=4  alloc=0x10000   OK  → alloc=0x10000
hdr=0x40000000  sc=2  alloc=0x10000   OK  → alloc=0x10000
hdr=0x7fffffff  sc=4  alloc=0x10000   OK  → alloc=0x10000
data=0x40000000 sc=4  alloc=0x10000   OK  → alloc=0x10000
data=0x7fffffff sc=2  alloc=0x10000   OK  → alloc=0x10000
plane size 0x100000 vs alloc 0x4000   REJECTED
plane off=0x8000 size=0x4000 vs 0x4000 REJECTED
```

**Asymmetry:** plane-level size/offset are checked against the allocation;
per-slice region sizes are not.

### E. Adjacent keys

```
AddressFormat+AddressOffset+AddressRanges   OK (planes=0, keys ignored)
Superbuffer=0                               OK (planes=0)
```

---

## 3. Probe v3 — retention and adjacency

`geom3.log`.

### F/G. Property retention — readback is not observable

`IOSurfaceCopyValue` returned `<absent>` for **every** key on **every** surface,
including built-ins that certainly exist:

```
F1 control: id=88 base=0x1042fc000 alloc=0x4000 planes=1
    IOSurfaceAllocSize = <absent>
    IOSurfaceBytesPerRow = <absent>
    IOSurfaceSliceCount = <absent>
    IOSurfacePlaneHeaderRegionBytesPerSlice = <absent>
```

This is a **methodology limitation**, not a result. `IOSurfaceCopyValue` on this
platform does not expose the built-in property dictionary through string keys.
It must not be read as "the kernel did not store the value."

### G. No observed upper bound

```
hdr=0x7fffffff sc=1 alloc=0x4000  OK
hdr=0x80000000 sc=1 alloc=0x4000  OK
hdr=0xfffffffe sc=1 alloc=0x4000  OK
hdr=0xffffffff sc=1 alloc=0x4000  OK
```

All accepted; all returned `alloc=0x4000`.

### H. Allocation adjacency — contiguous, exact stride

Four surfaces, each `AllocSize = 0x10000`, each declaring
`hdrPerSlice = 0x40000000`, `sliceCount = 4`:

```
H0 base=0x104308000 id=88
H1 base=0x104318000 id=99
H2 base=0x104328000 id=110
H3 base=0x104338000 id=158
delta H1-H0 = 0x10000
delta H2-H1 = 0x10000
delta H3-H2 = 0x10000
```

Observations:

* Each allocation is exactly the requested `0x10000`, despite each declaring
  four slices of `0x40000000` header bytes.
* They are packed **back to back with no guard page**: the byte immediately
  after H0 is the first byte of H1.
* The size of the *requested* allocation determines the stride; the declared
  slice geometry has no effect on placement.

This establishes the spatial precondition for an overlap primitive — **if**
something later consumes the declared geometry to compute an index. It does not
establish that anything does.

---

## 4. What is actually proven, and what is not

**Proven:**

1. The `IOSurfaceCreate` property parser is lenient about unknown keys.
2. It validates plane-level geometry (`PlaneSize`, `PlaneOffset`, plane
   `BytesPerRow` versus width × bytes-per-element) against `AllocSize`.
3. It does **not** reject per-slice region values that are grossly larger than
   the allocation, including `0xffffffff`.
4. IOSurface allocations of equal size are contiguous with an exact
   `AllocSize` stride and no guard page.

**Not proven (and the labels used elsewhere must not overstate this):**

* That `IOSurfacePlaneHeaderRegionBytesPerSlice` /
  `IOSurfacePlaneDataRegionBytesPerSlice` are **consumed** by the kernel rather
  than treated as unknown keys. Every "accepted" case above is equally
  consistent with "key ignored".
* That any GPU driver path (AGX/Metal) uses those stored fields to index the
  backing buffer.
* That `IOSurfaceSliceCount` has any effect.

**Therefore the F1 overlap primitive is not yet demonstrated on t8150.** What we
have is a *candidate validation gap*, not a primitive.

---

## 5. Next step (static, no device interaction)

The decisive question is what the IOSurface kext does with
`IOSurfacePlaneHeaderRegionBytesPerSlice` after parsing it. That is answerable
statically from the already-extracted binary:

* `analysis/f1/extract/com.apple.iokit.IOSurface`
* sha256 `8c2180448de8fb2ad6b4dcf311646d834e41711caac3eef8cf8a937e1361f93f`, 314376 B
* known validation strings at file offsets `0x18a3`, `0x53f1`, `0x543f`, `0x549b`

Concretely: locate the `ADRP`/`ADD` (or literal-pool) references to those string
addresses, recover the enclosing function, and determine whether the parsed
value is (a) bounds-checked, (b) stored, and (c) later multiplied with the slice
count. A multiply that is followed by no overflow check, with the result stored
into the surface descriptor that the GPU driver reads, would upgrade this from
"validation gap" to "primitive candidate".

Do **not** proceed to any Metal-based overlap test until that static question is
answered and a controlled, explicitly-authorised harness exists.

---

## 6. Probe v4 — the gating keys (2026-11-08, later)

`geom4.log`. Hypothesis from the static work in §7: the per-slice block is
gated on two extra plane keys, so adding them should activate validation.

```
J1  no comp keys, sc=4 hdr=0x2000            OK alloc=0x4000 planes=1
K1  comp keys, no slice keys                 OK alloc=0x4000 planes=1
K2  comp sc=4 hdr=0x2000  EXPECT REJECT      OK alloc=0x4000 planes=1
K3  comp sc=4 hdr=0x1000  EXPECT ACCEPT      OK alloc=0x4000 planes=1
K4  comp sc=2 hdr=0x40000000 EXPECT REJECT   OK alloc=0x10000 planes=1
L1  comp sc=4 hdr=0x40000000 EXPECT ACCEPT   OK alloc=0x10000 planes=1
L2  comp sc=4 hdr=0x40000001 EXPECT ACCEPT   OK alloc=0x10000 planes=1
L3  comp sc=4 hdr=0x80000000 EXPECT ACCEPT   OK alloc=0x10000 planes=1
L4  comp sc=4 hdr=0xffffffff data=1          OK alloc=0x10000 planes=1
L5  comp sc=8 hdr=0x20000000                 OK alloc=0x10000 planes=1
M1  comp sc=4 data=0x2000 EXPECT REJECT      OK alloc=0x4000 planes=1
M2  comp sc=4 data=0x1000 EXPECT ACCEPT      OK alloc=0x4000 planes=1
```

**Every** case was accepted, including the three that must reject if the
validation block were live (`K2`, `K4`, `M1`). Adding
`IOSurfacePlaneCompressedTileHeaderRegionOffset` and
`…DataRegionOffset` changed nothing.

Therefore: the validation code exists in the kext but is **not executed on the
`IOSurfaceCreate` path**. The most likely explanation is that libIOSurface
parses/whitelists the property dictionary in userspace and never forwards these
private per-slice keys to `IOSurfaceRoot`. (This also matches the A16/27.3β F1
transcript, which drove the `IOSurfaceRoot` user client directly with a
serialized 1751-byte property dictionary instead of calling `IOSurfaceCreate`.)

Note also: all surfaces in v4 returned the same base and `id=88`, i.e. created
and released in a loop reusing one slot. That is expected and harmless.

---

## 7. Static analysis of `com.apple.iokit.IOSurface` (27.0.1, t8150)

Binary: sha256 `8c218044…f93f`, 314376 B, Mach-O 64-bit kext bundle arm64e.

* `__TEXT` vmaddr `0xfffffe0007a18790`, fileoff 0
* `__cstring` addr `0xfffffe0007a18ea8`, fileoff 1816
* `__TEXT_EXEC` vmaddr `0xfffffe000a3257c0`, fileoff 32768

### 7.1 The slice-count key

`IOSurfaceSliceCount` is looked up at `0xa32c644`. Parsing at `0xa32c62c`:

```
ldur x8, [x29, #-0x78]        ; parsed value
mov  x9, #-0x100000000
add  x9, x8, x9               ; value - 2^32
mov  x10, #-0xffffffff        ; 0xffffffff00000001
cmp  x9, x10
b.ls  error                   ; reject
...
mov  w8, #1                   ; default when key absent
str  w8, [x19, #0x3b8]        ; sliceCount
```

Valid range is `1 … 0xffffffff`; the default when absent is **1**.

### 7.2 The gating keys

At `0xa32cc04` the plane parser looks up two keys and **skips the entire
per-slice block if either is absent**:

```
a32cc04: add  x2, x26, #0x8
a32cc0c: adrp x1, "IOSurfacePlaneCompressedTileHeaderRegionOffset"
a32cc14: bl   lookup
a32cc18: cbz  w0, skip                     ; absent -> skip
a32cc1c: add  x2, x26, #0xc
a32cc24: adrp x1, "IOSurfacePlaneCompressedTileDataRegionOffset"
a32cc2c: bl   lookup
a32cc30: cbz  w0, skip                     ; absent -> skip
```

### 7.3 The 32-bit multiply

Inside the gated block, `headerPerSlice` is validated and then the allocation
check is performed in **32 bits**:

```
a32cd70: bl   lookup("IOSurfacePlaneHeaderRegionBytesPerSlice")
a32cd74: cbz  w0, error        ; "must be present for multi-slice plane"
a32cd7c: lsr  x9, x8, #32
a32cd80: cbnz x9, error        ; "exeeds maximum value"
a32cd84: cmp  x8, x25
a32cd8c: b.lo error            ; "is smaller than expected value"
a32cd94: str  w8, [x26, #0x38] ; store headerPerSlice (full 32-bit value)
a32cd98: ldr  w9, [x26, #0x34] ; dataPerSlice
a32cd9c: add  w11, w9, w8      ; (A) 32-bit ADD   -> can wrap
a32cda0: ldr  w10, [x19, #0x3b8]; sliceCount
a32cda4: mul  w12, w11, w10    ; (B) 32-bit MUL   -> can wrap
a32cdb0: cmp  x11, x12
a32cdb4: b.lo error            ; alloc < w12 -> reject
```

Two distinct 32-bit overflow opportunities:

* **(A)** `dataPerSlice + headerPerSlice` wraps before the multiply.
* **(B)** `(data + header) * sliceCount` wraps; e.g. `0x40000000 * 4 == 0`.

The check compares the allocation against the *wrapped* product, while the
**full, unwrapped** `headerPerSlice` is stored at `[x26+0x38]`.

Error strings confirmed at their call sites:

| Address | String |
|---|---|
| `0xfffffe0007a1d9d0` | `IOSurface: kIOSurfacePlaneDataRegionBytesPerSlice %d exceeds maximum value.` |
| `0xfffffe0007a1db31` | `IOSurface: compressed plane[%d] Data region overlaps header region` |
| `0xfffffe0007a1db75` | `IOSurface: kIOSurfacePlaneHeaderRegionBytesPerSlice %d exeeds maximum value.` |
| `0xfffffe0007a1dbc3` | `… %d is smaller than expected value %d .` |
| `0xfffffe0007a1dc1f` | `… must be present for multi-slice plane %d with sliceCount %d .` |

### 7.4 Intermediate size checks

Before the slice block, the same parser performs several overflow-checked
64-bit computations, e.g.:

```
a32ccac: mul  x13, x11, x8
a32ccb0: cbnz x8, error          ; 32-bit product must fit
a32ccbc: madd x10, x13, x8(sliceCount), w10
a32ccc0: cmp  x10, x9
a32ccc4: b.hi error
```

So the parser is not naive everywhere — the *header-region* allocation check at
`a32cda4` is the one that is 32-bit.

---

## 8. Conclusion

The primitive is **not** reachable through the public `IOSurfaceCreate` API:

* libIOSurface does not forward the private per-slice keys (or the gate keys) to
  the kernel, so the whole gated block — including the 32-bit multiply — never
  runs. All dict shapes are accepted, which is indistinguishable from "ignored".

The only remaining route to exercise that code is the one the A16/27.3β
transcript used: **talk to the `IOSurfaceRoot` user client directly** with a
serialized property dictionary containing the private keys, rather than going
through libIOSurface.

That is a separate, larger step and must be done under the same safety rules
(no writes, no Metal, no cross-object attempt) until the acceptance behaviour is
understood.

**Status: not a primitive. A concrete, statically-identified 32-bit overflow
exists in the kernel parser, but it is currently unreachable from the API we can
call.**

---

## 9. Probes v5–v7 — direct `IOSurfaceRoot` user client (2026-11-08, later)

§8 left one open route: skip libIOSurface and drive the `IOSurfaceRoot` user
client directly, as the A16/27.3β transcript did. v5–v7 were written to test
exactly that. Logs: `analysis/evidence/mac/geom5.log`, `geom6.log`, `geom7.log`.

**Safety:** every call below is a surface-creation attempt (or a rejected
attempt). No Metal, no GPU submission, no writes, no cross-object attempt. The
device was verified booted and paired after every run.

### 9.1 v5 — first direct call

```
IOServiceOpen(IOSurfaceRoot, type 0) kr=0x0 conn=0x5f03
S1 sel0: sel=0 xml=968 kr=0xe00002c2 outLen=0xc68
```

`0xe00002c2` is `kIOReturnBadArgument`. The output buffer length was left at
`0xc68`, i.e. the call was rejected before writing a descriptor.

### 9.2 Static: what the dispatch table says selector 0 expects

In `__DATA_CONST` (file `0x46630`, vm `0xfffffe000837fa10`) there is a table
whose entries have stride `0x28`:

```
+0x00  u64  (padding / reserved, zero)
+0x08  u64  function pointer (arm64e auth-encoded)
+0x10  u32  scalarInputCount
+0x14  u32  structureInputSize     (0xffffffff = variable)
+0x18  u32  scalarOutputCount
+0x1c  u32  structureOutputSize
+0x20  u64  (padding / reserved, zero)
```

Entry 0 therefore reads:

```
fptr   = 0x8050bcad03345114
scalarInputCount    = 1
structureInputSize  = 0xffffffff   (variable)
scalarOutputCount   = 0
structureOutputSize = 0xc68
```

This matches the transcript's `c68` output, and it is why v6 tried one scalar
*y plus* the payload.

**Caveat on pointer resolution.** Taking the low 32 bits as the target and
rebasing on `0xfffffe0007000000` gives `0xfffffe000a345114`, which lands
*inside* a function (nearest `bti c` prologue is `0xfffffe000a345138`). Either
the rebase base is different, or this region is partly a vtable (the adjacent
region from `0x46660` on is a dense cluster of consecutive method pointers, which
looks like a vtable, not a dispatch table). The *counts* above are still the
best static hint available; the resolved function address is **not** trusted.

### 9.3 v6 — scalar-shape matrix

Payload = the same 968-byte XML dictionary (and a 794-byte stripped form), output
buffer `0xc68`.

| payload | scalar | result |
|---|---|---|
| full XML | `len` (=968) | `0xe00002c2` |
| full XML | `0` | `0xe00002c2` |
| full XML | `1` | `0xe00002c2` |
| full XML | none (0 scalars) | `0xe00002c2` |
| stripped | `len` / `0` / `1` / none | `0xe00002c2` (all) |

Selectors `1..5` were then called with scalar=`len` and the full payload:

```
sweep sel1..sel5: kr=0xe00002c2 outLen=0xc68   (all)
```

### 9.4 v7 — payload-encoding matrix

To rule out "the XML just is not the format the method wants", eight encodings
were each tried with and without a scalar length input (16 calls):

| encoding | size | result (both scalar shapes) |
|---|---|---|
| XML plist | 968 B | `0xe00002c2` |
| XML + NUL | 969 B | `0xe00002c2` |
| binary plist (`bplist00`) | 428 B | `0xe00002c2` |
| stripped `<dict>` | 794 B | `0xe00002c2` |
| stripped + NUL | 795 B | `0xe00002c2` |
| `u32` length prefix + XML | 972 B | `0xe00002c2` |
| `u64` length prefix + XML | 976 B | `0xe00002c2` |
| `u32` zero prefix + XML | 972 B | `0xe00002c2` |

Every one rejected with the identical error.

### 9.5 Interpretation

The failure is **identical across 16 payload encodings and selectors 0–5**. That
rules out "XML syntax" and "wrong scalar value" as explanations; the rejection
happens on an input-shape or precondition check that is independent of the
payload bytes.

Two candidate explanations remain:

1. **Selector numbering / client type differs from the A16 case.** The transcript
   came from a different SoC and a beta build; the t8150 shipping kext may expose
   create under a different selector, or require `IOServiceOpen` with a non-zero
   type.
2. **The opened connection is not the client that implements create.** Opening
   `IOSurfaceRoot` with type 0 succeeded, but success does not prove which
   `IOUserClient` subclass was instantiated.

What was **not** tried: other `IOServiceOpen` types, other service names
(`IOSurfaceRootUserClient`, `IOGPU*`), scalar-output shapes, structure inputs
larger than `0x1000`, and any entitlement-bearing client.

### 9.6 Conclusion

The direct `IOSurfaceRoot` route is **closed for the shapes and payloads tested**.
The A16/27.3β transcript cannot be reproduced on t8150 / 27.0.1 with:

* service `IOSurfaceRoot`, open type `0`;
* selector `0` (and `1..5` for the sweep);
* XML, binary, stripped, NUL-terminated and length-prefixed payloads;
* scalar input counts `0` or `1` with values `{len, 0, 1}`.

There is **no evidence** that the kernel per-slice parser was entered. The
statically-identified 32-bit multiply in §7.3 remains unreachable.

**Status: F1 is not a reachable primitive on t8150 / 27.0.1.** It is demoted
below the unexamined kext-lifetime work; see `analysis/LEAD-ASSESSMENT.md` §10.
Re-opening it would require first establishing the correct user-client type /
selector, which is a static-plus-device task of its own and does not itself
produce a primitive.


---

## 11. Addendum 2026-11-12 — the direct route works: the scalar input must be 0

`tools/opencode-temp/ContentView-v119.swift` (mode `--geom`), run on the 13 Pro and
then the 17 Pro.  The call is the A16/F1 shape, unchanged:

```
IOConnectCallMethod(conn, /*sel*/ 0,
                    scalars = { 0 },        // <-- ONE scalar, value 0
                    inputStruct  = <NUL-terminated XML property list>,
                    inputStructCnt = 1750,
                    outputStruct = 0xc68 bytes, outputStructCnt = 0xc68)
```

The **only** difference from the failed v5-v7 matrix is the value of the single
scalar input.  `scalar = len`, `scalar = 1` and "no scalars" all still return
`0xe00002c2`; `scalar = 0` returns `OK` and fills the descriptor.

### 11.1 Control matrix (the test v5-v7 never ran)

The kernel's plane parser validates `(dataPerSlice + headerPerSlice) * sliceCount`
**in 32 bits** (`0xa32ccf8`) and compares the **wrapped** product against the
allocation, while storing the full 32-bit `headerPerSlice` (`0xa32cd94`).  So a
surface whose declared geometry is ~4 GiB can be backed by 64 KiB.  The
distinguishing test is therefore not "is it accepted" but "**is the
non-wrapping case rejected?**" — that is what proves the parser is live.

Same payload, only the per-slice values differ:

| case | header | data | sliceCount | alloc | result |
|---|---|---|---|---|---|
| A | `0x40000000` | `0x4000` | 4 | `0x10000` | **OK** — product wraps to `0x10000` <= alloc |
| B | `0x4000` | `0x4000` | 4 | `0x10000` | `0xe00002c2` — product `0x20000` > alloc, **rejected** |
| C | (no per-slice keys) | `0x4000` | 4 | `0x10000` | `0xe00002c2` — "must be present for multi-slice plane" |
| D | `0x40000000` | `0x40000000` | 4 | `0x10000` | **OK** — product wraps to 0 |
| E | `0x10000000` | `0x10000000` | 1 | `0x10000` | `0xe00002c2` — no wrap, too big |

**B and E are the control.**  If the parser were not running, they would have
been accepted like A and D.  They are rejected, so the parser runs, and A/D are
accepted only because the 32-bit multiply wraps.  (C shows the per-slice block
is additionally gated on `IOSurfacePlaneCompressedTileHeaderRegionOffset` and
`...CompressedTileDataRegionOffset`, exactly as §7.2 predicted.)

### 11.2 Both target devices

```
13 Pro  24A5390f (iOS 27.0)    A -> OK base=0x104e7c000 id=16 alloc=0x10000 planes=1
                              D -> OK base=0x104ea8000 id=18 alloc=0x10000 planes=1
                              B/C/E -> 0xe00002c2
17 Pro  24A446  (iOS 27.0.1)  A -> OK base=0x10181c000 id=87 alloc=0x10000 planes=1
                              D -> OK base=0x106188000 id=82 alloc=0x10000 planes=1
                              B/C/E -> 0xe00002c2
```

The descriptor matches the A16/27.3beta F1 transcript **byte for byte** (same
field offsets, same `04 00 01 01` at `+0x60`, same `ARGB` fourcc at `+0x48`),
and the kernel backing pointer is disclosed at `+0x00` — the same unprivileged
kernel-pointer disclosure the F1 transcript relied on.

### 11.3 What this unlocks, and what is still missing

The size-confusion **primitive** is now reachable on both targets:

* a surface whose declared per-slice geometry is ~4 GiB while its backing
  store is 64 KiB, created by an ordinary sandboxed app;
* the kernel backing pointer of that surface, disclosed in the descriptor.

What is **not** yet demonstrated is the *consumer* of that geometry:

* the F1 route: bind the surface to Metal, let the GPU map it with the bogus
  size, and write past the end of the 64 KiB allocation into the neighbouring
  GPU allocation (`F1-PRIMITIVE-EVIDENCE.md` §3: `delta = ctrlga - figa`,
  `WRITE idx = 0x3a00` -> "CROSS-OBJECT HIT").  That is a **GPU-VA** write, not
  yet a kernel write;
* a possible kernel-side consumer: any kext path that trusts the stored
  per-slice values when it copies or maps plane data would be a **kernel**
  OOB, which is the primitive a jailbreak needs.

The next falsifiable step is to enumerate the consumers of the stored
`headerPerSlice` (`plane+0x38`) / `dataPerSlice` (`plane+0x34`) in
`com.apple.iokit.IOSurface` and in the GPU mapping path, then drive the one
that yields a kernel-side access.

### 11.4 What is *not* the consumer: the user mapping

`IOSurfaceGetAllocSize` on the bogus surfaces returns **65536** (the real
allocation), not the claimed 4 GiB — the kernel's own allocation is correct and
only the *metadata* is bogus.  `IOSurfaceLock` returns **false** for the bogus
surface *and* for a plain, self-consistent surface created the same way, so
the lock path is not reachable from this probe (it fails for unrelated reasons
and is therefore not evidence either way).

That leaves the GPU path as the consumer to test: if the IOMMU/segment mapping
for the surface is built from the *claimed* size, a 4 GiB mapping of a 64 KiB
allocation would let the GPU reach physical pages outside it — the same
physical-access primitive the reference jailbreak tool obtains through
`pmap`.


### 11.5 The GPU half: what reproduces and what does not (2026-11-12, later)

The Metal toolchain component was installed (`xcodebuild -downloadComponent MetalToolchain`,
838.9 MB) and `probe.metal` (two kernels: `readU32`/`writeU32` on a device pointer at a
**byte** offset) is now compiled by Xcode into the app's `default.metallib`.

Note: a hand-built metallib (`xcrun -sdk iphoneos metal ... -target air64-apple-ios14.0`)
is rejected by the device with `MTLLibraryErrorDomain Code=1 "Invalid library file"`,
and so is the SDK-default build. **Xcode's own** metallib loads fine
(`device.makeDefaultLibrary()`), so the library must come from the app bundle.

What works on the 13 Pro (iOS 27.0, A15 GPU):

```
library loaded
F1 surface created id=16 kbase=0x102a6c000 alloc=0x10000
F1 buffer wrap ok gpuAddress=0x1500000000 len=65536
CTRL buffer gpuAddress=0x1500018000
READ idx=0x0 -> 0x0
READ idx=0x8000 (out of the 0x10000 buffer) -> 0x0
delta = 0x18000
WRITE at +0x18000 status=completed
CPU view of the control buffer: hit=-1 word0=0x0
GPU view of the control buffer: word0=0x0 word1=0x0
no marker in the control buffer (GPU view)
```

* `makeBuffer(bytesNoCopy: <kernel backing pointer>)` **works** - the driver accepts a
  kernel VA as the buffer's backing and gives it a GPU VA.
* A compute-kernel write **past** the 64 KiB buffer **executes** (`status=completed`).
* But it has **no effect**: the control buffer (GPU readback, not the CPU view) is
  unchanged. The A15 GPU masks the write to the buffer's own allocation.

Re-reading `F1-PRIMITIVE-EVIDENCE.md` §4.5 with this in mind: the transcript's
`*** CROSS-OBJECT HIT ctrl off=0x0 ***` is the tool's **own arithmetic** ("we aimed at
`ctrlga`, so by construction we hit it") - the transcript contains **no independent
readback** of the control buffer after the F1 write (the `[CTRLBUF] READ` lines all
read the control buffer *through the control buffer*, before the F1 write). So the F1
cross-object claim is weaker than it reads, and on our device the mechanism does not
reproduce: the write is silently dropped.

### 11.6 Why: the descriptor on 27.0/27.0.1 does not carry the per-slice values

The F1 transcript's descriptor dump (27.3 beta) has the header size at `+0x68`:

```
0060: 04 00 01 01 00 00 00 00   00 00 00 04 00 00 00 00
      -> +0x60 = 0x01010004       +0x68 = 0x40000000   <- headerPerSlice
```

Our descriptor (27.0 / 24A5390f and 27.0.1 / 24A446) for the *same* payload:

```
desc[0x40..0xc8]
40:0000000000000000 48:0000000042475241 50:0000000000010000 58:0000000000000001
60:0000000001010004 68:0000000000000000 70:0000000000000000 78:000000000001ccb3
80:0000000000000000 88:0000000000000040 90:0000000000000040 98:0000000000000000
a0:0000000000000000 a8:0000000000000200 b0:0000000000010000 b8:0000000001010004
descriptor occurrences of the per-slice values: [0x20=0x10000] [0x50=0x10000] [0xb0=0x10000]
```

**`0x40000000` and `0x4000` are absent** - only the real allocation size survives.
(The layouts are also shifted by 8 bytes between the two builds.) The kernel *parsed*
and *validated* the per-slice values - cases B and E are rejected, which is only
possible if the parser ran - but the values are not propagated into the descriptor
that the driver reads. So on 27.0/27.0.1 the GPU is never told about the bogus
geometry, and there is nothing for it to size an oversized mapping from.

**Consequence.** The F1 route (steer the surface's GPU mapping to alias another
allocation) depends on the per-slice values reaching the driver, and that does not
happen on these builds. What remains open is the *kernel-side* consumer: any path in
`com.apple.iokit.IOSurface` that trusts the stored `headerPerSlice`
(`plane+0x38`) / `dataPerSlice` (`plane+0x34`) when it copies or maps plane data
would be a kernel out-of-bounds access, which is the primitive a jailbreak needs.
That is a static hunt over the kext: find every read of the plane struct's
`+0x34`/`+0x38` after `0xa32cd18`/`0xa32cd94` store them.


### 11.7 Verdict on the per-slice overflow (2026-11-12, final)

The consumer hunt for the stored per-slice values came back **empty**:

* Every instruction in `com.apple.iokit.IOSurface` that reads a `+0x34` / `+0x38`
  word other than the parser (`0xa32b7b4`) belongs to a **doubly-linked-list node
  helper** (the `next`/`prev` idiom at `+0x38`/`+0x40` with the
  `cmp`/`brk #0xbffd` back-pointer checks) - not to the plane structure.
* The only reads of the plane's `dataPerSlice` (`plane+0x34`) and `headerPerSlice`
  (`plane+0x38`) are the parser's own validation (`0xa32cd18` stores the data
  value, `0xa32cd94` stores the header value, `0xa32cd98` reads the data value
  back for the coverage check).
* The values never reach the driver: the 0xc68 descriptor on 27.0 / 27.0.1 does
  not contain them (§11.6), and `newTextureWithDescriptor:iosurface:plane:`
  **fails** for a surface created through the raw user-client path (it is not a
  shared/importable IOSurface), so the GPU never maps it either.
* The user-mapping path is closed: `IOSurfaceLock` returns false even for a
  self-consistent surface.

**So the overflow is a real validation bug with no exploitable consequence on
these two builds.** It is worth reporting as a finding (the parser's
`(data + header) * sliceCount` is computed in 32 bits, so a surface can claim a
1 GiB per-slice header region against a 64 KiB allocation, and the parser accepts
it) - but on 27.0 / 27.0.1 there is no consumer for the stored values, so it
cannot be escalated here.

### 11.8 The F1 transcript's GPU addresses are 32-bit-truncated

The F1 transcript prints `figa=0x15000000` and `ctrlga=0x15000e8000` - a
32-bit-looking address space. On our devices the same buffer reports
`gpuAddress=0x1500000000` (64-bit). The F1 tool therefore computed
`delta = ctrlga - figa = 0xe8000` on **truncated** addresses, and its
`*** CROSS-OBJECT HIT ***` is that arithmetic, not an independent readback
(the transcript has no read of the control buffer after the F1 write; the
`[CTRLBUF] READ` lines all read the control buffer *through the control buffer*,
before the write). Re-running the recipe here: the out-of-bounds compute write
executes (`status=completed`) but changes nothing - the A15 GPU masks it to the
buffer's own allocation.

Combined with §11.6/§11.7, the F1 lead is **not** a path to a jailbreak on
iOS 27.0 / 27.0.1.


---

## 12. Fresh-bug hunt status (2026-11-12)

Tooling built today, reusable for the hunt:

* `tools/opencode-temp/ContentView-v122.swift` - the AGXProbe harness with four
  modes: `--geom` (the IOSurfaceRoot create + control matrix), `--metal`
  (Metal compute cross-object test), `--fuzz` (IOSurfaceRoot method sweep) and
  the older race mode.
* The IOSurfaceRootUserClient dispatch table is decoded (60 selectors, with
  scalar-input counts and structure sizes), so every method can be called with
  the shape the kernel expects - `tools/opencode-temp/methmap.py` /
  `selmap3.py` rebuild it from the kernelcache.
* Metal works end to end now: the Metal toolchain component is installed and
  `probe.metal` is compiled by Xcode into the app's `default.metallib`
  (a hand-built metallib is rejected by the device with
  `MTLLibraryErrorDomain Code=1 "Invalid library file"` - it has to come from
  the app bundle).

### 12.1 IOSurfaceRoot method sweep (`--fuzz`), both devices

Sweep of the methods that take a caller-sized structure, using each method's
real scalar count and structure size from the decoded table, with hostile
lengths and contents (zeros / all-ones / 0x41 pattern / 0x7fff... / an
offset-like value).

| outcome | 13 Pro (24A5390f) | 17 Pro (24A446) |
|---|---|---|
| `BadArgument` (0xe00002c2) | 719 | 719 |
| `BadMatching` (0xe00002c1) | 5 | 5 |
| `0xe00002bf` (IPCError) | 5 | 5 |
| `NoMemory` (0xe00002bd) | 1 | 1 |

**The two kernels behave identically** - no differential, and no crash or
panic on either device.  The three calls that get past the argument check are:

| call | result | note |
|---|---|---|
| `sel 0x06, 32-byte struct of zeros` | `NoMemory` | `0x06` = `create_surface_fast_path`; the struct is `{u32 count, values...}` and the kernel maps the values onto six fixed keys (`IOSurfaceBytesPerRow`, `IOSurfaceWidth`, `IOSurfaceHeight`, `IOSurfacePixelFormat`, `IOSurfaceAllocSize`, `IOSurfaceAddress`) |
| `sel 0x1e, 1 scalar, no struct` | `BadMatching` | a name/service lookup |
| `sel 0x22, 1 scalar, no struct` | `0xe00002bf` | dispatches an IPC - this is the `IOSurfaceShared` / "client shared id" family (`IOSurfaceRootUserClient: asked to allocate client shared id %08x not known by IOSurfaceRoot`) |

Everything else is rejected at the entry check, so a length-handling bug in
those paths needs the *exact* shape first, then hostile contents.

### 12.2 What is established about the two IOSurface leads

| lead | status on 24A5390f / 24A446 |
|---|---|
| per-slice 32-bit overflow (IOSurface plane parser) | reachable unprivileged, control-verified (§11.1), **inert** - the values are stored but never consumed, and the descriptor does not carry them (§11.6/§11.7) |
| notify UAF (CVE-2026-112477) | reliable dangling nodes (hundreds per run), but PAC-authenticated: read-or-panic, no write |
| F1 GPU cross-object write | does not reproduce here: the surface is not importable as a texture, the descriptor lacks the per-slice values, the OOB GPU write is masked, and the transcript's own addresses are 32-bit-truncated (§11.8) |

Neither can carry a jailbreak, so the hunt continues on new surfaces:
the `IOSurfaceShared` / "client shared" IPC path (`0x22`), the memory-pool and
descriptor-family methods (`0x1a`, `0x2e`, `0x36`, `0x0a`), and - beyond
IOSurface - the sandbox-reachable kexts with no entitlement gate, where a
lifetime bug would give a real kernel write.


### 12.3 Probe of the two deep paths (2026-11-12, later)

`--probe` on the 13 Pro:

```
sel0x22 client-shared-id sweep 0...256: 0xe00002bf=257
0x1e <name> s0/s1/s2 -> BadArgument   (IOSurfaceDescriptorContext,
   IOSurfaceMemoryPoolBunch, IOSurfaceDescriptorComponent, IOSurfaceShared,
   IOSurfaceRoot, IOSurfaceRootUserClient, IOSurfaceClient)
```

* `sel 0x22` answers `0xe00002bf` (IPCError) for **every** id 0..256 - the
  scalar is not a client-shared id (or the shared region table is empty, which
  is the expected state for a fresh client), so the "allocate a client shared
  id" path is not reachable from a fresh connection yet.
* `sel 0x1e` gets *worse* (BadArgument instead of BadMatching) once the struct
  carries a name, so the struct is not a plain C string - the name is probably
  an `OSString`/CF object pointer or the name lives in a different field.

Both need the exact ABI. The efficient way to get it: the handler for `0x1e`
and `0x22` can be read straight out of the dispatch table
(`tools/opencode-temp/methmap.py` -> handler -> thunk), then the *kext's own
string table* gives the key names the method expects (the strings around
`IOSurfaceDescriptorContext` / `IOSurfaceMemoryPoolBunch` /
`IOSurfaceDescriptorComponent` in
`firmware/24A446/kernelcache.release.macho` at
`0xfffffe0007a1bc91`+). Those two families - the descriptor context and the
memory-pool bunch - are the newest code in the kext and the only place left in
IOSurface where a userspace-controlled length meets a kernel allocation.

The other IOSurface lead worth one more shot is `sel 0x06`
(`create_surface_fast_path`): its 32-byte struct is `{u32 count, values...}`
and the kernel allocates `count * 0x40` bytes and copies the values onto six
fixed keys. `count` is user-controlled and the copy reads `count` u32s out of a
32-byte struct - i.e. it reads past the end of the kernel's copy of the
structure when `count > 8`. That is an out-of-bounds *read* of the kernel's
method buffer (an info leak, not a write) and needs `count` to be accepted:
the fast path rejected our attempts with `NoMemory`/`BadArgument`, so the
struct's remaining fields still have to be filled in.

### 12.4 Order of work from here

1. Read the `0x1e` / `0x22` handlers from the dispatch table and reconstruct
   their input ABI; re-probe with the exact shape.
2. Fill in the `0x06` fast-path struct (all eight u32s) so `count` is
   accepted, then sweep `count` (1..64) for the OOB read.
3. Move outside IOSurface: the assessment's Lead #2 (kext lifetime / UAF over
   sandbox-reachable, non-entitlement-gated kexts) is still unexamined and is
   where a real kernel *write* is most likely to live.


### 12.5 Probe results for `0x06` / `0x22` (13 Pro and 17 Pro, identical)

```
sel0x22 client-shared-id sweep 0...256: 0xe00002bf=257
sel0x06 fast-path count sweep 0...64:  BadArgument=65
```

`0x06` was tried three ways, all rejected at the entry check:
1. struct = `{u32 count, u32 values[6]}` (count swept 0..64);
2. the same with `count` replaced by a real 0x40-byte **userspace pointer** in the
   first slot (the handler does `ldr x0,[x23]; cbz` and, when non-NULL,
   allocates 0x40 bytes and calls the object with the `IOSurfaceAddress` key);
3. the same with the six values in the order
   BytesPerRow / Width / Height / PixelFormat / AllocSize / Address.

So `0x06` needs more than a 32-byte structure - most likely the *client* must
first own a property set (the fast path reuses the client's stored properties
and the structure only supplies the six values), which is why
`create_surface_fast_path` was never reachable with a bare structure.

`0x22` answers IPCError for every client-shared id: the shared-region table is
empty on a fresh connection, so the "allocate client shared id" path needs a
prior allocation (probably `0x2f`/`0x30`/`0x32`, the variable-structure
methods) before `0x22` can be driven.

**Status of the hunt:** IOSurface is now characterised end to end and offers no
r/w path on 24A5390f / 24A446 (§11.6, §11.7, §12.5). The next candidate
surface is outside IOSurface: sandbox-reachable kexts with no entitlement gate
(the assessment's Lead #2), where a lifetime bug would give a real kernel write.


### 12.6 Descriptor-family ABI (recovered) and the probe results

Recovered from the dispatch table + handler prologues
(`tools/opencode-temp/abi.py` dumps the thunk and the first instructions of the
real function for any selector).

**The external-method argument blob** (as the kext sees it):

| offset | meaning |
|---|---|
| `+0x20` | scalar input array pointer (`+0x28` = count) |
| `+0x30` | structure input pointer (`+0x38` = size) |
| `+0x40` | a **user pointer that the kernel dereferences** (`+0x48` = scalar output) |
| `+0x58` | structure output pointer (`+0x60` = size) |

**Per-selector findings:**

* `0x1e` - `ldrb w8,[x0,#0x122]; tbz w8,#0,...` : the method is gated on a
  **client capability bit** (`client+0x122` bit 0) that an unprivileged
  type-0 client does not have, so this path is entitlement-gated.
* `0x22` - takes `scalarIn[0]` + a structure output and immediately dispatches an
  IPC; it answers `0xe00002bf` for every client-shared id 0..256, i.e. the
  shared-region table is empty on a fresh connection.
* `0x1a` - `x23=[args+0x30]` (structure in), `w25=[args+0x38]` (size),
  `x0=[args+0x40]` (a **user pointer**, dereferenced as an object),
  `x24=[args+0x58]` (structure out), `w27=[args+0x60]` (size). The kext's own
  field names for this family are *Descriptor address*, *Pool Id*, *Components*,
  and per component *Length* / *Options* - so the structure is a
  `{u64 descriptorAddress; u32 poolId; u32 componentCount; ...}` plus a component
  array read through the user pointer. **This is the one place where a
  userspace pointer and a userspace count meet a kernel walk** - the shape that
  yields an OOB - so it is the best remaining candidate inside IOSurface.
* `0x06` (`create_surface_fast_path`) - the 32-byte structure is
  `{u64 pointer; u32 values[6]}`; the first slot is a user pointer that the
  handler tests with `ldr x0,[x23]; cbz` and, when non-NULL, allocates 0x40
  bytes and calls the object with the `IOSurfaceAddress` key. Tried three ways
  (count-as-u32, a real 0x40-byte user pointer, the six keys in order) - all
  `BadArgument`: the fast path reuses the client's stored properties, so a bare
  structure is never enough.

**Descriptor-family probe** (`0x1a`, `0x13`, `0x18`, `0x2e`, `0x36`, `0x2f`,
`0x30`, `0x32` x {componentCount 0,1,2,8,64,1024} x {poolId 0,1} x a real
0x4000-byte user buffer): **every** combination returns `BadArgument`. The
structures need their real layout - the component array is probably an array of
kernel-side objects rather than a user array, and `0x1a`'s `+0x40` pointer may be
a *context object* rather than a plain user buffer.

**Next:** read the `0x1a` handler past the entry check to see how it uses
`x0` (`args+0x40`) and `w25` (the structure size) - that is where the user
pointer and the length meet.


### 12.7 Reordering the chain: sandbox escape first, then the kernel bug

The reference tool's transcript does exactly this, and the order matters:

```
Preparing system services... / Preparing execservice...
Escaping sandbox...                 <- stage 1: user space
Execution returned.
Preparing kernel access...          <- stage 2: kernel
Preparing privileged execution... proc/task/map/pmap
```

**Why the escape must come first.** The IOSurfaceRootUserClient capability bit
that gates the interesting methods (`client+0x122` bit 0, checked by selector
`0x1e`) is enforced by the *sandbox*, not by the kernel: a client opened
from our sandboxed app never gets it. Escaping the sandbox (or moving the
exploit into a process whose sandbox profile is broader) is what makes the
gated IOSurfaceRoot paths - the descriptor / memory-pool family, where a
userspace pointer and a userspace length meet a kernel walk - reachable at all.

**What we have for stage 1:**

| primitive | state |
|---|---|
| CVE-2026-111497 (Brotli `ProcessCommandsInternal` OOB write) | verified on both devices; **silent** heap corruption (no fault), with the 23,068,693-byte stage 1 + 127-byte stage 2 reproducer and the "runaway output" signature (`analysis/brotli-CVE-2026-111497-repro.md`) |
| reachability | any process decoding `Content-Encoding: br` - CFNetwork / `nsurlsessiond` / the WebKit **Networking** process. The WebKit networking service is a *system* XPC service, so a `WKWebView` in our app is enough to make it decode our bytes |
| open foothold | the Terminal-app SSH server on the 13 Pro (`python3 ~/Documents/sshd.py`, port 2222) runs as `mobile` outside our app's sandbox; it is **currently down** |
| dev platform | **none - the 6s+ is off limits.** Everything runs on the 13 Pro, positives confirmed on the 17 Pro |

**Stage 1 plan** (the part that is not done yet):

1. Serve the Brotli payload (stage 1 + stage 2, `Content-Encoding: br`) from
   the Mac and make a system WebKit process decode it - a `WKWebView` in our
   app is enough, no user interaction.
2. Turn the silent corruption into controlled writes: the wild `memmove16`
   has an attacker-controlled source and length, so with heap grooming it can
   hit a chosen object (an Objective-C instance pointer, a block's
   `isa`/function pointer).
3. From the hijacked system process, re-open `IOSurfaceRoot` and compare
   `client+0x122` with what our sandboxed app gets. If the capability bit is
   set, the gated descriptors/pool methods become callable - that is the
   "better vision" the escape buys, and it is exactly the surface where a
   userspace-controlled length reaches a kernel allocation.
4. Only then drive the kernel bug from that process (where the entitlement
   lets us reach the gated paths), get r/w, and patch for Sileo.

**Needed from the user:** start the Terminal-app SSH server on the 13 Pro
(`python3 ~/Documents/sshd.py`) so we have an out-of-sandbox foothold on the
target for step 3's comparison, and so the stage-1 chain can be developed
against the device itself.


### 12.8 The out-of-sandbox foothold, and the key inversion it exposed

The Terminal-app SSH server on the 13 Pro (a-Shell's `ios_system()` engine, no
fork/exec) gives an out-of-app-sandbox context:

```
uid=501(mobile) gid=501(mobile)
Darwin localhost 27.0.0 Darwin Kernel Version 27.0.0 ... RELEASE_ARM64_T8110 iPhone14,2
python3 -c "print(6*7)"   ->  42        # python3 works via the subprocess path
ls /var/mobile            ->  Operation not permitted
```

Commands must be piped over the SSH channel (the session is an interactive
a-Shell, not an exec channel), and the working directory is `~/Documents`
(`/tmp` is not writable).  Files are transferred by serving them from the Mac
and fetching with `urllib.request` - that avoids the quoting problems of
pushing a long base64 blob through the shell.

**The inversion.**  From this context, `IOSurfaceRoot` cannot be opened **at
all**:

```
IOSurfaceRoot service = 0xa703
IOServiceOpen(IOSurfaceRoot, type=0..7) -> BadArgument (all eight)
match IOSurfaceRootUserClient -> 0x0      # does not exist
match IOSurfaceUserClient     -> 0x0
```

while our **sandboxed app** opens `IOSurfaceRoot` with type 0 without complaint
(the free-provisioned profile grants it).  So the Terminal/`mobile` context is
*more* restricted for IOKit than the app - the opposite of "better vision".

**Consequence for the chain.**  A generic sandbox escape is *not* enough: the
escape has to land in a **system daemon** that already holds the IOKit
entitlements - the WebKit **Networking** process is the natural target, because
it (a) decodes `Content-Encoding: br` and (b) legitimately uses IOSurface.
WebKit's networking service is a separate system XPC process, so a `WKWebView`
in our app is enough to make it decode our Brotli payload - no user interaction
and no Safari needed.

**Revised stage 1 (the part that is not done):**

1. Serve the Brotli stage1+stage2 payload (23,068,693 + 127 bytes,
   `Content-Encoding: br`) from the Mac; make a `WKWebView` in our app fetch it.
2. Turn the silent corruption into a controlled write: the wild `memmove16` has an
   attacker-controlled source and length, so heap grooming can aim it at a chosen
   object (an Objective-C instance pointer, a block's `isa`).
3. From the hijacked WebKit networking process, open `IOSurfaceRoot` and read
   `client+0x122` bit 0 - WebKit's entitlements should set it, which is exactly
   what selector `0x1e` and the descriptor/pool family require.
4. Drive those gated paths to the kernel OOB, get r/w, patch, install Sileo.

All of steps 1-2 run on the **13 Pro** (the secondary research device).  The 6s+ is
explicitly off limits and is never contacted.


### 12.9 Stage 1 reachability: CONFIRMED (WebKit networking process)

`--web` mode in `tools/opencode-temp/ContentView-v122.swift` puts a `WKWebView`
in the app; the Mac serves on `:8777` (`tools/opencode-temp/brserver.py`, logs
every request with its User-Agent).  Run on the 13 Pro:

```
REQ GET /brtest ua='Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X)
                   AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148'
```

The request came from **WebKit**, i.e. from the WebKit *networking* XPC service -
a **system daemon**, separate from our app, which (a) decodes `Content-Encoding: br`
and (b) legitimately uses IOSurface and therefore holds the IOKit entitlements that
set the `client+0x122` capability bit the gated IOSurfaceRoot methods need.

**This is the whole point of doing the escape first**: the same trigger that is
useless inside our own app runs in a daemon that can open `IOSurfaceRoot` with a
privileged client, which is what unlocks selectors `0x1e` and the
descriptor/memory-pool family.

**Next, concretely:**

1. Generate the trigger payload on the Mac with the existing Swift CLI
   (`tools/opencode-temp/brotlirepro.swift`, `-DBROTLI_CLI`): stage1
   (23,068,693 B) followed by stage2 (127 B) into one file, served as
   `Content-Encoding: br` from `/trigger`.
   *Safety:* the decoder's corrupted state produces unbounded output (127 B in ->
   gigabytes out), so the server must **abort the connection** right after
   stage2 - the heap corruption has already happened at that point, and the
   runaway output never gets buffered.
2. Watch the 13 Pro: the WebKit networking process should die (or misbehave) -
   that is the trigger firing in a system daemon.
3. Turn the corruption into control there: the wild `memmove16` has an
   attacker-controlled source and length, so heap grooming can aim it at a chosen
   object (an Objective-C instance pointer, a block's `isa`, a `__block` pointer).
4. From the hijacked daemon, open `IOSurfaceRoot`, read `client+0x122` bit 0, and
   if it is set, drive the descriptor/pool methods to the kernel OOB; then r/w,
   patch, Sileo.

**All of this happens on the 13 Pro** (the secondary research device); the 6s+ is
explicitly off limits and is never contacted.  Positives are confirmed on the 17 Pro.

Note: the Mac's `libcompression` has **no Brotli encoder** (decode only - an
encode call segfaults), so the payload must be produced by our own generator, not
by compressing on the Mac.


### 12.10 Stage 1 executed: the trigger reached the WebKit networking daemon

Built on the Mac (from `tools/opencode-temp/brotlirepro.swift`, `-DBROTLI_CLI`):

```
[br] stage1=23068693 B stage2=127 B chunk=65536
[br] VERDICT: CORRUPTED STATE REACHED (runaway output 16777216 B from 127 B input)
shasum -a 256 /tmp/stage1.bin
  87a88ee96e68f6d17a17e1ea01857326b30689cf23337dfbb319424b2a761fcf   (matches the
  documented value)
```

`/tmp/brtest` = stage1 ‖ stage2 (23,068,820 B), served by
`tools/opencode-temp/brserver.py` with `Content-Encoding: br`; the server aborts
the connection immediately after the body so the decoding daemon never buffers
the runaway output.

Fired from the 13 Pro with the app's `--web` mode (a `WKWebView`):

```
REQ GET /brtest ua='Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X)
                   AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148'
```

The 23 MB Brotli body was fetched and decoded **by the WebKit networking
process** - a system daemon - twice in a row ✓.

**No crash and no jetsam of the daemon**, which is exactly what the Brotli
repro predicts: the wild `memmove16` lands in mapped heap, so the corruption is
**silent** (`analysis/brotli-CVE-2026-111497-repro.md`: "silent heap corruption,
not a reliable crash").  A crash is therefore the wrong detector; the reliable
detectors are (a) the runaway output (the daemon balloons) and (b) a controlled
write landing on a chosen object.

**So stage 1 is: reachability ✓, delivery ✓, corruption very likely ✓, and the
remaining work is the hard part - turning a silent, wild `memmove16` with
attacker-controlled source and length into a chosen write inside a foreign
system daemon.**  Concretely:

1. Find the wild write's destination control.  `memmove16` uses
   `dst = ringbuffer + pos`, where `pos` is the corrupted output position.  The
   parameters are `d15=d19=d23=0x7fffffff`, `b7=8` - so the *length* is
   attacker-influenced and the *source* is attacker-controlled, but `pos` is
   derived from the output position.  Sweeping `d15/d19/d23` and `b7` changes
   where the write lands; find a combination that lands on a heap object we can
   groom (an Objective-C instance pointer, a block's `isa`, a C++ vtable).
2. Groom the daemon's heap: the trigger body is 23 MB of decoder output, which
   gives plenty of allocation churn to place a chosen object right after the
   ring buffer.
3. Detect RCE in the daemon from outside (the page runs in the *WebContent*
   process, so the daemon's state has to be observed indirectly - e.g. the daemon
   stops servicing requests, or a marker shows up in a later response).
4. From RCE in the networking daemon: open `IOSurfaceRoot` (it has the
   entitlement) and read `client+0x122` bit 0 - if set, the gated
   descriptor/memory-pool methods unlock, which is where the kernel OOB and
   ultimately r/w live.  Then patch and install Sileo.

All of steps 1-3 run on the **13 Pro** (the secondary research device).  The 6s+ is
explicitly off limits and is never contacted.


### 12.11 Automating the aim sweep (running on the 13 Pro)

`brotlirepro.swift` now takes parameter overrides in its `--dump` CLI mode:

```
/tmp/brotlicli --dump --cmdcount=<log2> --b7=<n> --d15=<hex> --d19=<hex> --d23=<hex>
```

* `--cmdcount` sets `2^n` metablock commands, i.e. the size of stage 1 - `cmdcount=20`
  gives a 1.44 MB stage 1 instead of 23 MB (16x faster iterations).
* `--b7` is the block-switch bit pattern that corrupts the decoder's output position.
* `--d15/--d19/--d23` are the distance codes that drive the backward-reference copy,
  i.e. the length and source of the wild `memmove16` - these are what move the write.

`/tmp/sweep.sh` on the Mac runs the grid unattended on the **13 Pro** (the 6s+ is not
contacted): for each combination it regenerates the payload, serves it (the server
allowlists only 192.168.1.48), fires the app's `--web` mode so the WebKit networking
daemon decodes it, then pulls the crash logs and looks for a `WebKit` crash - a crash
means the wild copy landed on something fatal, i.e. the aim worked.

Results stream to `/tmp/sweep.log` on the Mac:

```
cc=20 b7=8 d=7fffffff size=1441940 req=1 -> none
cc=20 b7=8 d=10000    size=1441940 req=1 -> none
```

`req=1` means the daemon fetched the body (delivery confirmed); `none` means the
corruption stayed silent.  A hit (`CRASH ...`) is the signal that a combination lands
fatally - that is the first foothold towards aiming it at a chosen object instead.

**Sweep pacing.** Each iteration is dominated by the crash-log pull (the whole
`systemCrashLogs` tree is copied back), so an iteration is ~5-7 minutes rather than
the ~80 s the payload generation alone would take; the 36-combination grid is
therefore a multi-hour unattended run on the 13 Pro, appending to `/tmp/sweep.log`.
It is safe to leave running: the server allowlists only 192.168.1.48, every payload
is served with a post-body connection abort, and the 6s+ is never contacted.
