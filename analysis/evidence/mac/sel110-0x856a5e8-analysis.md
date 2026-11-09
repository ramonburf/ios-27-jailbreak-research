# `sel=0x110` / `0xfffffe000856a5e8` disassembly check

Source: local `analysis/agx_disasm.txt`, extracted `analysis/com.apple.AGXG18P`.
The user-supplied script referenced `G:/iOS 27.0.1/...`, which is not present on this machine,
so this analysis uses the local kext disassembly instead.

## Address mapping

- Kext `__TEXT_EXEC` range: `0xfffffe00084b1960` .. `0xfffffe0008589960`
- `0xfffffe000856a5e8` = `__text+0xb8c88`
- `0xfffffe0008556f54` = `__text+0xa55f4`

## What `0xfffffe000856a5e8` actually is

It is **not** a user-input copy/write routine. It is a 256-entry indexed
slot-lookup/allocator helper:

```
int helper(obj *x0, uint32_t index /*w1*/, uint8_t *out /*x2*/, uint32_t alloc /*w3*/)
{
    if (index > 0xff) return 0;
    if (*(uint32_t *)(x0->field_48 + 0x109d4) == 0) return 0;

    table = x0->field_178;                 // 0x200 bytes, 256 * 2
    if (!table) table = zero_alloc(0x200);

    entry = table + index * 2;
    if (entry[1] & 1) {                    // already populated
        *out = entry[0];
        return 1;
    }
    if (!alloc) return 0;

    accel = x0->field_48;
    lock(accel + 0x13978);

    // Find a free bit in the 256-bit bitmap at accel+0x199a8.
    // Clear it and use the bit number as a slot index.
    slot = find_free_bit(accel + 0x199a8);
    meta = accel + 0x139a8 + slot * 0x60;
    *(uint16_t *)(meta + 0x58) = index;
    *(uint64_t *)(meta + 0x50) = x0;
    *out = slot;

    unlock(accel + 0x13978);

    entry[1] = 1;                           // mark populated
    entry[0] = *out;                        // store slot
    return 1;
}
```

If the bitmap has no free bit, the path at `0x856a76c` scans/cleans the
existing entries and eventually returns 0 if it cannot allocate.

Key points:

- It writes only to `x0->field_178`, the bitmap at `accel+0x199a8`, the
  slot metadata at `accel+0x139a8 + slot*0x60`, and `*out`.
- It uses `index` and a computed slot number; it does **not** write
  arbitrary bytes from the caller's 8-byte input.
- It is called from the command-processing function at `0x84e83ec` via
  `0x84e892c`; that caller loops over command records and uses a 16-bit
  record field (`w24`) as the index. This is not the external-method
  selector dispatcher.

## `0xfffffe000856a5e8` is not the `sel=0x110` handler

The only `0x110`-related vtable entry visible in the local metadata is the
C++ slot at `+0x110`:

```
0xfffffe0007f20380 -> 0xfffffe000b2e0d40
```

`0xfffffe000b2e0d40` is outside the extracted kext's `__TEXT_EXEC` range,
so the local kext disassembly cannot show that function. It is likely a
kernel-side implementation or a different binary. The `+0x110` vtable slot
is also a C++ virtual-method offset, not the `IOConnectCallMethod`
external-method selector `0x110`; those are different namespaces.

The helper at `0x856a5e8` is therefore not evidence of a write primitive
reachable through `sel=0x110`.

## The actual OOB candidate is `0xfffffe0008556f54`

This is the reserve/allocate function identified earlier:

```asm
fffffe0008556f54:  mov   w8, #0
fffffe0008556f58:  cbz   x1, 0xfffffe0008556fa4
fffffe0008556f5c:  ldr   x9, [x0, #0x8]
fffffe0008556f60:  cbz   x9, 0xfffffe0008556fa4
fffffe0008556f64:  ldrb  w8, [x1]              ; index = input[0], unchecked
fffffe0008556f68:  ldr   x9, [x9, #0x40]       ; table
fffffe0008556f6c:  ldr   x8, [x9, x8, lsl #3]  ; OOB read: table[index]
fffffe0008556f70:  ldrb  w8, [x8, #0x14]
fffffe0008556f74:  tbnz  w8, #5, 0xfffffe0008556f80
fffffe0008556f78:  mov   w0, #0
fffffe0008556f7c:  ret
fffffe0008556f80:  ldr   x8, [x1, #0x8]        ; mask = input+8
fffffe0008556f84:  ldr   x9, [x0, #0x18]
fffffe0008556f88:  tst   x9, x8
fffffe0008556f8c:  b.eq  0xfffffe0008556f98
fffffe0008556f90:  mov   w0, #0
fffffe0008556f94:  ret
fffffe0008556f98:  orr   x8, x9, x8
fffffe0008556f9c:  str   x8, [x0, #0x18]       ; write mask into object
fffffe0008556fa0:  mov   w8, #1
fffffe0008556fa4:  mov   x0, x8
fffffe0008556fa8:  ret
```

Contract:

- `x0` = object
- `x1` = pointer to at least 16 bytes:
  - byte 0: unchecked channel index
  - qword at +8: mask
- It reads `table[index]` with no bounds check, then ORs `mask` into
  `object+0x18`.

This requires a 16-byte `{index, mask}` input. The successful `sel=0x110`
calls used an 8-byte input, so they cannot supply the mask this function
consumes. If `0x110` passed its 8-byte buffer here, the load at `[x1+8]`
would read past the 8-byte struct.

## Conclusion

The dynamic `sel=0x110` behavior (index 0..2 succeed, 3..255 return
`kIOReturnError`, byte 7 ignored) is consistent with a small sub-selector
query handler, not with `0x856a5e8` and not with a demonstrated write
primitive. The real OOB helper is `0x8556f54`, gated behind a 16-byte
`{index, mask}` input and likely the privileged `0x105`/ownership path.

To resolve the `0x110` handler exactly, the missing piece is the
disassembly containing `0xfffffe000b2e0d40` (or the external-method
dispatch table), which is not in the extracted kext.

---

## 2026-11-06 follow-up: full-kernelcache static analysis + service enumeration

Sources used for the follow-up:

- Kernelcache: `/Users/volpidash/Desktop/JAILBREAK 27.0.1/private/firmware/24A446__iPhone18,1/kernelcache.release.iPhone18,1`
- Full kernel disassembly: `/Users/volpidash/Desktop/tools/agx-reach/kernel_analysis/full_disasm.txt`
- `AGXDeviceUserClient` vtab metadata: `/Users/volpidash/agx-probe-project/analysis/agx_uc_methods.txt`, `analysis/agx_uc.json`

Findings:

1. The OOB helper at `0xfffffe0008556f54` has only one textual reference in
   the full kernelcache disassembly, at the helper instruction address itself.
   No direct `bl`/`bra` branch target to `0xfffffe0008556f54` was found.

2. The C++ vtable method that the metadata associates with selector `0x110`,
   `AGXDeviceUserClient::fn_0x110`, is implemented at
   `0xfffffe000b2e0d40` in the full kernelcache disassembly.

3. The function at `0xfffffe000b2e0d40` is a small authenticated dispatcher:
   - calls `0xfffffe000b2a5104`;
   - uses authenticated indirect calls through vtables;
   - does not directly call `0xfffffe0008556f54`.

4. The address `0xfffffe00084e8914` previously cited as the `sel=0x110`
   handler is only a branch/call-site context inside the command-processing
   helper at `0xfffffe00084e83ec`. It is not a function boundary and not
   itself the external-method implementation.

5. Service enumeration run on the secondary device found only four
   AGX/GPU-named IOService objects (including duplicates and the firmware
   names), plus six IOUserClient instances. Only
   `AGXAcceleratorG18P` opened successfully as an IOUserClient
   (`IOServiceOpen(type=1)`), with handle `0x79d3`; all other AGX/GPU service
   opens failed with `-536870201` (`0xe00002c7`). No new AGX service was
   found that could accept the `ssize=16` input.

Interpretation: the static evidence so far does not show a direct static caller
of the OOB helper, and the dynamic `ssize=16` sweep shows that no selector in
the `0x100–0x1ff` range accepts the required 16-byte `{index, mask}` shape. The
likely remaining question is whether the `fn_0x110` vtable chain eventually
reaches the OOB helper through an indirect authenticated branch that is not
visible as a literal branch target.
