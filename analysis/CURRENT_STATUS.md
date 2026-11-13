# iOS 27.0.1 Jailbreak Research — Current Status

## Objective
Develop a jailbreak for iPhone 17 Pro (iPhone18,1 / t8150 / A19 Pro) on iOS 27.0.1 (24A446).
**Real goal:** "i just want to have sileo and tweaks working"

## Devices
- **Primary:** iPhone 17 Pro (iPhone18,1 / t8150 / A19 Pro), iOS 27.0.1 (24A446), UDID `00008150-00095CD93444C01C`
- **Secondary:** iPhone 13 Pro (iPhone14,2), iOS 27.0 dev beta 4, UDID `00008110-000E095936C1801E`
- Both plugged into user's MacBook (`ssh -i "$env:USERPROFILE\.ssh\mac_ios16_ed25519" volpidash@192.168.1.99`)
- Devices are paired/booted, Developer Mode on, probes installed

## Requirements
- No firmware writes, restores, updates, downgrades or boot-chain changes
- Kernel probes only on secondary/paired devices under a no-brick rule; stop on app crash, SpringBoard respring, or reboot; pull crash logs first
- Confirm any positive result on primary iPhone 17 Pro only after verified benign on secondary
- SCP NOT enabled on Mac — transfer via `cat <local> | ssh ... 'cat > <remote>'` or write directly on Mac
- Remote commands from script files / quote-free payloads; PowerShell rejects `&&`, `||`, `head`, `tail`, `base64`; zsh mangles nested quotes
- PC temp/scratch under `G:\iOS 27.0.1\iOS\tools\opencode-temp\`, never C:
- Only do what the user tells you; don't try to fix unrelated things
- Prioritize fastest path to a working jailbreak

## Current State — What We've Tested

### IOSurfaceRoot (com.apple.iokit.IOSurface)
- Service reachable from app sandbox: `IOServiceOpen(type=0)` succeeds
- sel0 (create): works — creates surfaces with `IOSurfacePlaneInfo`
- sel1 (release): returns `0xe00002c2` for all IDs — NOT functional via struct input
- sel9 (setValue): `kr=0x0` with string value ("testname") — works but returns counter `0x03000000`
- sel10 (getValue): `kr=0x0` but empty output (`outSz=0`) — doesn't return stored property
- sel10: `0xe00002c2` for small outSize (<13), `0xe00002bd` at insz=13
- sel10 insz=16/20/24/32: `kr=0x0` but outSz=0 (empty output)
- sel26, sel46, sel47, sel48, sel50, sel54: all `0xe00002c2` (BadArgument)
- sel9 sel9 with scalarCount=1: `0xe00002c2`
- All create edge cases (Width=0, Height=0, BPE=0, BPR=0, max width/alloc, plane offset/size max, plane base, address ranges): **all return 0xE00002C2** (properly validated)
- **Superbuffer aliasing CONFIRMED** on both 13 Pro and 17 Pro: parent + child with `IOSurfaceAllocateFromSuperbuffer` and same plane offset share user pages — writes through either visible through the other. But this is within-IOSurface shared pages, not arbitrary kernel memory.

### AGX / AGXG18P
- `AGXAcceleratorG14P` (13 Pro) and `AGXAcceleratorG18P` (17 Pro) reachable via `IOServiceOpen(type=1)`
- sel=0x4: returns `0x0` with 32-byte output containing 2 pointer-like values + size=0x4000 — appears to be static userland buffer info, NOT kernel pointers, not surface-correlated
- sel=0x103: returns `0x0` with zeroed output
- All other selectors 0x0-0xFF: `0xe00002c7` (Unsupported)
- AGX channel-index OOB read at `0xfffffe0008556f54` exists in kext but is NOT reachable through any user-connectable selector (installed via module init, not dispatch table)
- AGX is **exhausted as an attack surface**

### AppleJPEGDriver
- Reachable via `IOServiceOpen(type=0 AND 1)`
- Selector 10 dispatch table recovered (10 entries)
- Selectors 1-7 callable without entitlements
- All codec selectors return `0xe00002cc` (NotResponding) or `0xe00002bc` (Error) — no exploitable behavior found yet
- AppleJPEGCodec selectors power-gated

### GitHub Repo
- Created: `https://github.com/ramonburf/iOS27-Research-Exploits`
- 3 commits pushed with analysis docs and probe scripts

## Current Build Error (v42)
The Swift probe file `ContentView-v42.swift` has repeated build errors:
- `cannot convert value of type 'Data' to expected argument type '[UInt8]'` — `callIO` expects `[UInt8]` but `Data` is passed
- `invalid redeclaration of 'u64'` / `xmlNul` — duplicate function declarations
- `cannot convert value of type '(UInt32, UInt32, UInt32)' to expected argument type '(UInt32, String, UInt32)'` — tuple type mismatch
- `cannot use mutating member on immutable value: 'p2' is a 'let' constant` — mutating a let variable
- `consecutive statements on a line must be separated by ';'` — statements collapsed onto one line
- `invalid redeclaration of 'inScalar'` / `outScalar` / `outScalarCount` — duplicate variable declarations in same scope

The root cause: the `callIO` function signature changed between versions (sometimes `(conn, sel, scalars, sdata, outSize)`, sometimes `callIO(dict:conn:sel:scalars:outSize:)`), and call sites weren't updated consistently. Also `xmlNul` was declared twice and `u64` was declared twice.

## Next Steps
1. Fix v42 Swift build errors (consistent callIO signature, remove duplicate function declarations)
2. Run v42 on iPhone 13 Pro to test IOSurface sel0 with extreme plane header/size values
3. If IOSurface path is exhausted (likely), pivot to AppleJPEGDriver codec fuzzing
4. The SKVLENT repo (https://github.com/ramonburf/iOS27-Research-Exploits) has similar research — their finding #01 (IOSurface size validation) shows a 4 GiB header region is accepted for 64 KiB allocation on iPhone 17 Pro, but they report NO exploitable primitive from it
5. Consider other surfaces: AppleJPEGDriver, AppleSARService (dropped: 0xE00002E2), AGX (exhausted)
