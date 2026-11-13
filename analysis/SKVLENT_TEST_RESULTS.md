# SKVLENT iOS27-Research-Exploits — Testing Results

## What We Did

1. **Cloned** https://github.com/SKVLENT/iOS27-Research-Exploits to `G:\iOS 27.0.1\iOS\tools\opencode-temp\SKVLENT-repo`
2. **Built** the Bench27 app from SKVLENT's source using xcodebuild on the Mac (UIKit/SwiftUI mismatch caused crashes — resolved by using SwiftUI mode)
3. **Wrote v44 probe** with the EXACT SKVLENT IOSurface request shape (including all HTPC-compressed plane keys that our earlier v42/v43 probes were missing)
4. **Tested on both devices** — iPhone 17 Pro (A19 Pro, 27.0.1) and iPhone 13 Pro (A14, 27.0 beta 4)

## Key Finding: SKVLENT Finding #01 CONFIRMED

**IOSurface sel0 with HTPC-compressed planes + HBR=0x40000000 returns `kr=0x0` (success) on both devices.**

### iPhone 17 Pro (A19 Pro, iOS 27.0.1 24A446)
```
sel0 SKVLENT HTPC: kr=0x0 outSz=3176
  surface id=168 a0=0x102340000 alloc=0x10000 planes=1
AGX sel8: kr=0xffffffff (-1)
  out00=0x10000000000 out20=0x100000000 out28=0x10000
```

### iPhone 13 Pro (A14, iOS 27.0 beta 4)
```
sel0 SKVLENT HTPC: kr=0x0 outSz=3176
  surface id=19 a0=0x10263c000 alloc=0x10000 planes=1
AGXAcceleratorG18P service NOT FOUND (13 Pro has G14P, not G18P)
```

### Why our earlier probes failed

Our v42/v43 probes returned `0xe00002c2` (BadArgument) for the same HBR values because they were **missing the HTPC-compressed plane keys**:
- `IOSurfacePlaneCompressionType = 4`
- `IOSurfacePlaneCompressedTileWidth/Height = 32`
- `IOSurfacePlaneBytesPerCompressedTileHeader = 8`
- `IOSurfacePlaneBytesPerTileData = 4096`
- `IOSurfacePlaneWidthInCompressedTiles = 2`
- `IOSurfacePlaneHeightInCompressedTiles = 2`
- `IOSurfacePlaneBytesPerRowOfTileData = 8192`
- `IOSurfacePlaneCompressedTileHeaderRegionOffset = 65536`
- `IOSurfacePlaneCompressedTileDataRegionOffset = 0`
- `IOSurfacePlaneBytesPerRowOfCompressedTileHeaderGroups = 0`

With these keys present, sel0 succeeds.

## Limitation

Per SKVLENT's own report: **"No expansion of accessible memory was observed."** The 4 GiB header region is declared but only 64 KiB is actually mapped. This is a **validation defect only** — not an exploitable kernel read/write primitive.

## Other SKVLENT Findings Reviewed

| # | Direction | SKVLENT Verdict | Our Assessment |
|---|-----------|-----------------|----------------|
| 01 | IOSurface size validation | Demonstrated | ✅ Confirmed on both devices |
| 02 | Metal GPU VA | Partially demonstrated | Same-context cross-page access only, not cross-process |
| 03 | mediaplaybackd/FigXPC | Partially demonstrated | NULL dereference = DoS only |
| 04 | AppleAVE2 | Partially demonstrated | Fixed-address write = DoS only |
| 05 | ANE reachability | Not demonstrated | Not reachable from sandbox |
| 06 | AppleM2ScalerCSCDriver | Not demonstrated | Property path is inert |
| 07 | Container path disclosure | Demonstrated | Info disclosure only |
| 08 | Image parser surfaces | Not demonstrated (entitlement) | All selectors return BadArgument |
| 09 | External leads | Not demonstrated (closed) | All three leads closed |
| 10 | Sandbox escape (worse_query) | Demonstrated | Userland container R/W only, no kernel |

## Bottom Line

SKVLENT's research confirms what we found independently: **no kernel read/write primitive or jailbreak has been demonstrated on iOS 27.0.1.** Finding #01 (IOSurface size validation) is real but produces no exploitable primitive. The worse_query sandbox escape (finding #10) gives userland container read/write but cannot install Sileo/tweaks without kernel code execution.

## Files

- `G:\iOS 27.0.1\iOS\tools\opencode-temp\ContentView-v44.swift` — v44 probe with exact SKVLENT shape
- `G:\iOS 27.0.1\iOS\tools\opencode-temp\SKVLENT-repo/` — Cloned SKVLENT repository
- `G:\iOS 27.0.1\iOS\analysis\CURRENT_STATUS.md` — Full project status
