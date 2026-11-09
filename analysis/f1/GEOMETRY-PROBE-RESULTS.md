# IOSurface geometry-acceptance probes on t8150 / iOS 27.0.1 — 2026-11-08

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

