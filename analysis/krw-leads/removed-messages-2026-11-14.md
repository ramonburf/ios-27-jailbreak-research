# Assertions/messages removed in iOS 27.2 — attribution

Sweep of strings present in 24A446 (27.0.1) and absent from 24B119 (27.2).
3019 strings removed total; 35 look like runtime messages.

| source file | message | VA |
|---|---|---|
| `lifs_subr.c` | "%s: override is already set for lnode %p io_lock" @%s:%d | `0xfffffe0007dcfb99` |
| `lifs_subr.c` | "%s: override is not set for lnode %p io_lock" @%s:%d | `0xfffffe0007dcfbed` |
| `IOGPUTask.cpp` | "IOGPU::systemPagingOff() timeout. %d threads still stuck.\n" @%s:%d | `0xfffffe00079984c4` |
| `EXBrightKextInterface_c.c` | "TB_FATAL: " "invalid tag in `[EXBrightKextInterface.EXBrightIndicatorState]` metadata: 0x | `0xfffffe00078db88e` |
| `AppleM2ScalerCSCHalMSR23.cpp` | "[%s] " "Failed to load MsrCPU firmware for PG\n" @%s:%d | `0xfffffe0007616355` |
| `IosaFirmwareControlMSR29Rtk.cpp` | "[%s] " "Failed to load MsrCPU firmware for reset\n" @%s:%d | `0xfffffe000761517b` |
| `-` | %lld %d AVE %s: %s:%d %s | invalid MB/CTU stats firmware buffer %p %d %lld %p %lld | `0xfffffe00072f9252` |
| `-` | %lld %d AVE %s: %s:%d %s | number of sub layer is out of range %d %d %d %d | `0xfffffe00072ffcfb` |
| `-` | %s: %s: cannot map ANEResource ID: 0x%llx | `0xfffffe000745972e` |
| `uipc_mbuf2.c` | %s: mbuf %p len (%d) < off+len (%d+%d) @%s:%d | `0xfffffe00070a6aa6` |
| `apfs_vnops.c` | %s:%d: %s Failed to invalidate %llu:%llu for ino %llu, err %d | `0xfffffe0007d7b99a` |
| `apfs_vnops.c` | %s:%d: %s Failed to msync for ino %llu | `0xfffffe0007d7b7c9` |
| `-` | +S]_panic_active | `0xfffffe000b9fb8df` |
| `AppleSEPCoreBuffer.cpp` | /Library/Caches/com.apple.xbs/7CCFDFD2-85AA-43F3-AB53-935F0D1ADD5C/TemporaryDirectory.6j4w | `0xfffffe0007745a46` |
| `AudioCodecWrapper.cpp` | AssertMacros: %s (value = 0x%lx), version: BiometricKit-577~9296, %s file: %s, line: %d | `0xfffffe000797b083` |
| `vm_fault.c` | External objects are not implemented for CoW. %p %i %i %llx %llx @%s:%d | `0xfffffe000705bcf5` |
| `CS42L79.cpp` | Failed to HallStreaming enable:%d | `0xfffffe00073ee8df` |
| `RTBuddyEntropyEndpoint.cpp` | RTBuddy(%s): Failed to append string table chunk | `0xfffffe0007b5e4d0` |
| `RTBuddyEntropyEndpoint.cpp` | RTBuddy(%s): Failed to create string table | `0xfffffe0007b5e501` |
| `TSNPacketPool.cpp` | Unexpected sync received on GM | `0xfffffe0007aad42c` |
| `AneEngine_C.c` | [ERROR] %s: %s: Failed prepareKernelSplitSections for base instance - 0x%llx: 0x%x | `0xfffffe000744bae2` |
| `-` | [ERROR] %s: %s: Failed to allocate instanceKernelSplitSections for programHandle: 0x%llx | `0xfffffe0007451668` |
| `AneEngine_C.c` | [ERROR] %s: %s: Failed to allocate prepare request for base-instance kernel splits - 0x%ll | `0xfffffe000744bb36` |
| `-` | [ERROR] %s: %s: Failed to copy kernel split section for programHandle: 0x%llx procId: %u | `0xfffffe0007451721` |
| `-` | [ERROR] %s: %s: Failed to flush inactive dart mappings | `0xfffffe000746ad45` |
| `-` | [ERROR] %s: %s: Failed to map mutable source buffer result=0x%x | `0xfffffe0007451512` |
| `AneEngine_C.c` | [ERROR] %s: %s: Failed to prepare base-instance kernel splits - 0x%llx: 0x%x | `0xfffffe000744bb93` |
| `-` | [ERROR] %s: %s: Failed to size process procedureKernelSplitSections for programHandle: 0x% | `0xfffffe00074516c2` |
| `-` | [ERROR] %s: %s: Invalid offset[0x%llx] and size[0x%llx] for endpoint[%ld]. Oversized messa | `0xfffffe0007471d83` |
| `-` | [INFO] %s: %s: vnode read advise failed, ret=%d | `0xfffffe0007459860` |
| `RTBuddyEntropyEndpoint.cpp` | failed to register disk image backing store for %s | `0xfffffe0007b5f457` |
| `RTBuddyEntropyEndpoint.cpp` | failed to register sync root for %s | `0xfffffe0007b604df` |
| `RTBuddyEntropyEndpoint.cpp` | failed to unregister disk image backing store for %s | `0xfffffe0007b5f3f7` |
| `RTBuddyEntropyEndpoint.cpp` | failed to unregister sync root for %s | `0xfffffe0007b60457` |
| `kpi_interface.c` | utun_flowswitch_attach - ifnet_detach failed: %d @%s:%d | `0xfffffe000707a040` |
