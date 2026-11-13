# AGXG18P channel-index OOB read — 27.0.1 target verification

Date: 2026-11-05
Target: iPhone18,1 / V53AP / t8150 / iOS 27.0.1 (24A446)
Status: **unchecked code sequence confirmed live on the target build; reachability unresolved**

## Device check

`tools/ipsw/ipsw.exe idev list` identified the attached phone as:

- Product Type: `iPhone18,1`
- Hardware Model: `V53AP`
- ChipID: `0x8150` (arm64e), HardwarePlatform `t8150`
- Product Version: `27.0.1`
- BuildVersion: `24A446`
- Trusted host: yes

This is the same build the local firmware receipts describe. Serial and UDID are
intentionally omitted from this file.

## What was checked

The reference repository's AGXG17P finding is a small C++ helper that reads a
one-byte index from a caller-supplied descriptor, indexes an array of 8-byte
pointers without a bound check, then dereferences the loaded pointer:

```asm
ldrb w8, [x1]                 ; index, 0..255
ldr  x9, [x9, #0x40]          ; table->array
ldr  x8, [x9, x8, lsl #3]     ; array[index]  <-- unchecked
ldrb w8, [x8, #0x14]          ; dereference the loaded pointer
tbnz w8, #0x5, ...
```

That exact sequence exists in `com.apple.AGXG18P` on the target's 24A446
kernelcache, not only in the reference device's AGXG17P.

## Binary inputs

| Build | Kext | Size | SHA-256 | Source version |
|---|---|---:|---|---|
| 24A446 (27.0.1) | `com.apple.AGXG18P` | 1,106,000 | `61dde04c8f4a2370c04df0ef82ca0523ed56909af637ca9070368bdc9939dfe1` | `<host>.0` |
| 24B119 (27.2) | `com.apple.AGXG18P` | 1,122,416 | `c366e9a2b27d20a6b49cb8fded1218d4d3cc46bcb0c422c796b1b89add109beb` | `<host>.0` |

Extraction:

```powershell
.\tools\ipsw\ipsw.exe kernel extract firmware\24A446\kernelcache.release.macho `
  com.apple.AGXG18P -o analysis\agx\2701 --force
.\tools\ipsw\ipsw.exe macho disass analysis\agx\2701\com.apple.AGXG18P `
  -x __TEXT_EXEC.__text -q > analysis\agx\2701.disasm.txt
```

## 27.0.1 — vulnerable sequence on the target

Function entry `0xfffffe0008556f50` (`bti c`), body at `0xfffffe0008556f54`:

```asm
0xfffffe0008556f50:  bti  c
0xfffffe0008556f54:  mov  w8, #0
0xfffffe0008556f58:  cbz  x1, 0xfffffe0008556fa4
0xfffffe0008556f5c:  ldr  x9, [x0, #0x8]          ; this->table
0xfffffe0008556f60:  cbz  x9, 0xfffffe0008556fa4
0xfffffe0008556f64:  ldrb w8, [x1]                ; index
0xfffffe0008556f68:  ldr  x9, [x9, #0x40]         ; table->array
0xfffffe0008556f6c:  ldr  x8, [x9, x8, lsl #0x3]  ; unchecked array[index]
0xfffffe0008556f70:  ldrb w8, [x8, #0x14]         ; dereference
0xfffffe0008556f74:  tbnz w8, #0x5, 0xfffffe0008556f80
```

No count load, compare, or conditional bail precedes the indexed load.

## 27.2 — still unchecked

Extracted from 24B119 for comparison only. Function entry
`0xfffffe00085703bc` (`bti c`), body at `0xfffffe00085703c0`:

```asm
0xfffffe00085703d0:  ldrb w8, [x1]
0xfffffe00085703d4:  ldr  x9, [x9, #0x40]
0xfffffe00085703d8:  ldr  x8, [x9, x8, lsl #0x3]  ; still unchecked
0xfffffe00085703dc:  ldrb w8, [x8, #0x14]
0xfffffe00085703e0:  tbnz w8, #0x5, 0xfffffe00085703ec
```

So the change did not land between 27.0.1 and 27.2 on this SoC.

## Same helper class, same layout

The surrounding cluster matches the reference kext's helper shape:

| Role | 27.0.1 | 27.2 |
|---|---|---|
| popcount of `this->mask` | `0xfffffe0008556f38` | `0xfffffe00085703a4` |
| clear mask | `0xfffffe0008556fac` | `0xfffffe0008570418` |
| init `{table@+8, byte@+0x10, word@+0x14}` | `0xfffffe0008556fb8` | `0xfffffe0008570424` |
| constructor-style function | `0xfffffe0008556fec` | `0xfffffe0008570458` |

The kext contains the metadata-class string
`site.AGXBitmap<kAGXMaxChannelCount>` (file offset `0x77cc`), which is
consistent with the helper being an `AGXBitmap<kAGXMaxChannelCount>` method.
That is an identification lead, not proof of the owning call path.

## Reachability: still the decisive gap

`analysis/agx/scan_all_refs.py` scanned every Mach-O section for 8-byte words
whose chained-fixup low 32 bits encode the helper address. Result on 27.0.1:

- `0xfffffe0007f1e650` in `__DATA_CONST.__mod_init_func` -> `0xfffffe0008556f54`
- `0xfffffe0007f1e988` in `__DATA_CONST.__mod_term_func` -> `0xfffffe0008556f44`

No static vtable slot in `__DATA_CONST.__const` encodes the helper, and no
direct `bl`/`b` targets the cluster. The module init/term references are not
yet interpreted as a user-reachable call path; they may be constructor /
destructor metadata for a runtime-installed vtable. This matches the
reference finding's blocker: the vptr is installed at runtime by a constructor
that is not visible as a static xref in this kext.

Not proven:

- that the index byte is attacker-controlled from an app-sandboxed
  `IOConnectCallMethod` input;
- that an entitlement gate does not sit in front of the call;
- that the owning object is the GPU command-submission path rather than a
  kernel-internal table.

## Impact bound

Even if reachable, the primitive is an OOB **read** of an 8-byte pointer slot,
followed by a wild-pointer dereference of the loaded value. The index is one
byte, so the slot read is at most about 2 KB past a small array. The only
observable result is whether bit 5 of the dereferenced byte is set, which
controls a mask update and a 1/0 return. That is a low-bandwidth oracle and a
crash/DoS hazard, not a direct kernel write or a jailbreak chain.

## Safety / next step

Do not run a speculative probe against the daily phone. A wrong index is a
wild kernel dereference and can panic the device. The next useful work is:

1. Recover the owning class and vtable installation site (companion AGX kext
   or runtime construction), then trace the caller of slot 4.
2. Confirm whether the index originates in an ungated user-client struct.
3. If a probe is built, run it on a second test device or Corellium, never the
   primary phone.
4. Fetch and compare `AGXG18P` from 24C5037i (27.3 beta) to confirm the
   `count`/`cmp`/`b.ls` fix exists on G18P as it does on G17P.

A jailbreak is not established by this lead. It is a candidate OOB read whose
reachability is the entire open question.
