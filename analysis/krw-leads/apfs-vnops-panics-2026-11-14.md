# Lead: APFS error-path panics (`apfs_vnops.c`) — removed in 27.2

Origin: the sweep of assertions/messages present in 24A446 and absent from 24B119
(`analysis/krw-leads/removed-messages-2026-11-14.md`). Attribution comes from the nearest
preceding source-file string in the image's string table.

## Strings

| message | VA | line |
|---|---|---|
| `%s:%d: %s Failed to msync for ino %llu` | `0xfffffe0007d7b7c9` | `0x62be` = 25278 |
| `%s:%d: %s Failed to invalidate %llu:%llu for ino %llu, err %d` | `0xfffffe0007d7b99a` | `0x6396` = 25494 |

Each has exactly one code reference:

| message | reference site |
|---|---|
| msync | `0xfffffe000a9ac0f0` |
| invalidate | `0xfffffe000a9ac62c` |

Both sites sit in the same `__TEXT_EXEC` neighbourhood of the APFS kext.

## Recovered shape

Both follow the identical pattern:

```
bl   0xfffffe000aa7a624     ; APFS operation under test
cbz  w0, <continue>         ; success -> carry on
...                        ; build panic arguments (error code, inode numbers)
adrp/add x0, <message>
bl   <panic helper>
```

So these are **error-propagation panics**: when an APFS operation returns an unexpected error,
the kernel terminates instead of returning it to userspace.

The first argument pair before each call is `(x0 = vnode-ish, x1 = ..., x2 = ..., x3 = 0,
w4 = 0xa)` for the msync path and `w4 = 0xc` for the invalidate path — consistent with a
selector-flagged APFS primitive, plausibly journal/invalidation related.

## Why this is worth attention

- It is in the **VFS layer**, the surface the community trackers identify as where modern
  iOS jailbreaks succeed (heap/type-isolation defeats object-level approaches; VM/VFS remains).
- The calls are on the path exercised by ordinary file operations: our existing `--cowfile`
  harness maps files `MAP_PRIVATE`/`MAP_SHARED`, faults them concurrently and would naturally
  drive msync and invalidation behaviour against APFS.
- A reachable panic from a sandboxed app is at minimum a reproducible denial-of-service finding.

## What is not yet known

- Which exact APFS operation `0xfffffe000aa7a624` performs, and which failure mode makes it
  return non-zero.
- Whether any failure mode is reachable without special privileges. Many fs failures come from
  media errors or corrupted images, which apps cannot easily induce on a healthy volume.
- Whether 27.2 replaced the panic with graceful error propagation (the likely fix) — that
  would confirm Apple treated this as a defect.

## Suggested next steps

1. Disassemble `0xfffffe000aa7a624` and identify the operation and its failure conditions.
2. Diff the enclosing function against its 24B119 counterpart to see whether the panic was
   replaced by error propagation.
3. Extend `--cowfile` to race `msync`/`msync`+`munmap` and file truncation against concurrent
   faults, then watch crash logs on both devices for `apfs_vnops.c` frames.


## Device test (2026-11-14): APFS race stress runs clean

Built `--apfsrace` into the carrier (`SockUafSpray.c`, `ContentView.swift`, bridging header;
`BUILD_EXIT=0`) and ran it on **both devices**.

Per round: create a 4 MB file in the app container, map it `MAP_SHARED`, dirty every page, then
run two concurrent threads — one faulting random pages continuously, the other issuing
`msync(MS_SYNC|MS_ASYNC)`, `madvise(MADV_DONTNEED)` and `fsync`. After unmapping, each round
performs an invalidation cycle of `ftruncate(0)` / restore / `fsync` x8.

Result on both the 17 Pro and 13 Pro:

```
[*] apfsrace: open=0 mmap=0 thread=0
=== apfsrace done ===
```

All stage counters zero, probe completed its full 96-round schedule, process remained alive,
and neither device produced a panic. Under this workload the APFS invalidation path did not
return the error that triggers the `apfs_vnops.c` panics.

### Note on an earlier revision
The first version truncated the file while the writer thread still had live accesses, which
killed the app with `SIGBUS` (signal 10) on both devices. That was a probe-design fault, not a
kernel fault — the devices stayed responsive and no panic log appeared. Truncation now happens
only after `munmap`.

### Interpretation
The APFS panics are error-propagation paths; ordinary msync/invalidate stress does not make
them fail. Reaching them likely requires conditions apps cannot induce on a healthy volume
(media-level errors, specific corrupted-image states). Treat as low-reachability unless a
specific trigger for `0xfffffe000aa7a624` failing can be identified.
