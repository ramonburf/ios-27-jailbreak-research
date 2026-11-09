# Debugger attach to iPhone 17 Pro (iOS 27.0.1, 24A446) — status

Date: 2026-11-07
Device: iPhone18,1 / iOS 27.0.1 (24A446) / UDID `00008150-00095CD93444C01C`
Host: Windows PC (no macOS/Xcode)

> **Superseded in part.** The section "Why the attach still fails" below was
> written before the `vAttach`-must-be-first discovery and is retained only as
> a record of what was tried. The current status is at the end of this file
> and the full protocol detail is in
> **`analysis/agx/DEBUG-PROTOCOL-FINDINGS.md`**.

## Summary (as originally written — now outdated)

The **gdb-remote transport to the device's debugserver is finished and clean**.
LLDB now completes a full, correctly framed handshake with the on-device
debugserver and the session is stable (no NAKs, no framing errors).

The **attach itself is still blocked**: the debugserver acknowledges every
attach/launch packet but never acts on any of them, and never acquires an
inferior. Everything reachable from the raw gdb-remote socket has been tried
(see "What was tried").

## Tooling (all under `tools/opencode-temp/`, drive G:)

| file | purpose |
|---|---|
| `agx_debug_win.py` | Main driver: RSD tunnel → custom debugproxy relay → LLDB (Windows) |
| `agx_sweep_lldb.py` | LLDB python driver (`agxwhere`, `agxrun`, `agxsweep`) |
| `agx_sweep_payload.c` | C payload the sweep evaluates inside the app |
| `probe_*.py` | One-off protocol probes (attach variants, DTX channels, …) |

## The three protocol bugs that were cracked (all fixed in the relay)

The device's debugserver speaks plain gdb-remote, but its framing collides
with LLDB's parser in three places. `agx_debug_win.py` rewrites packets in the
relay; the device itself is never modified.

1. **`$QStartNoAckMode`** — the device answers `OK` and then stops computing
   real checksums (all replies get `#00`). LLDB only leaves ack mode when the
   reply *is* `OK`, so the packet is rewritten to `$qHostInfo`; the device stays
   in ack mode and keeps sending valid checksums.
2. **`$QEnableCompression:type:zlib-deflate;`** — after this the device switches
   to LLDB's compressed framing `"$N<payload>#<cksum>"`. LLDB's
   `DecompressPacket()` strips the `N` but keeps the checksum the device
   computed *with* the `N`, so the second checksum check fails and LLDB NAKs
   every reply. Rewriting this packet to `$qHostInfo` keeps the session plain.
   (LLDB only enables compression if the reply to this packet is `OK`.)
3. **Bogus process/thread reporting** — the device answers `qC` with `QC0` and
   `qfThreadInfo` with an empty `OK`. LLDB then concludes `pid = tid = 1`
   (`GetCurrentProcessAndThreadIDs` falls back to `(1, 1)`) and blocks forever
   in `GetStopReply()`. The relay rewrites those two replies to `E01` so
   `process connect` completes in the "connected, no inferior" state, which is
   the state LLDB needs before it can issue `vAttach`.

After these rewrites the wire log is clean: every reply has a correct
checksum, LLDB never NAKs, and the handshake runs to completion.

## Why the attach still fails (historical — resolved later the same day)

> **OUTDATED.** Everything in this section was measured with a *completed
> handshake* already on the wire. The device turns out to honour `vAttach`
> **only when it is the very first packet on a fresh connection**; once any
> query has been sent it ignores every attach packet while continuing to
> answer ordinary queries, which is exactly what made this look like "the
> debugserver has no target-selection mechanism".
> See `analysis/agx/DEBUG-PROTOCOL-FINDINGS.md` §2.

With the transport clean, every attach spelling was tried on a fresh
connection **after a completed handshake**:

```
vAttach;<hexpid>        (LLDB/Apple form)  -> ack only, no reply
vAttach;<decpid>                           -> ack only, no reply
vAttachOrWait;<hexpid>                     -> ack only, no reply
vAttachWait;<hexpid>                       -> ack only, no reply
vAttachName;AGXProbe                       -> ack only, no reply
vAttach;<hexpid>;1                         -> ack only, no reply
vAttach;<pid>:0        (gdb form)          -> $E96 (error 150)
qAttach;<pid>                              -> $#00 (empty)
A,<len>,0,<hex path>    (LLDB launch form)  -> ack only, no reply
```

State queries confirm there is never an inferior:

```
?           -> $E02   (no process)
qProcessInfo-> $E68
qfThreadInfo-> $OK   (empty)
qC          -> $QC0
```

The Instruments DTX channel `com.apple.instruments.server.services.debugserver`
**exists** on the device (it opens successfully), but the device **cancels the
channel on the first invocation** of every selector tried
(`requestConnectionAtPort:`, `attachToProcessWithIdentifier:`,
`launchSuspendedProcessWithDevicePath:…`), while the same launch selector
works fine on the `processcontrol` channel. So the legacy Instruments
debugserver path is not usable either.

Supporting facts:
* `isPidDebuggable:` (DVT process control) returns **True** for the probe app.
* The app is dev-signed with `get-task-allow`; `is_debuggable` → True.
* The device's debugproxy service advertises the feature
  `com.apple.coredevice.feature.debugserverproxy` and is RemoteXPC-framed, but
  it still answers raw gdb-remote without any XPC handshake.

**Conclusion (historical):** the debugserver behind `com.apple.internal.dt.remote.debugproxy`
answers queries but has no target-selection mechanism reachable from the raw
gdb-remote socket. The remaining plausible route is the CoreDevice/RemoteXPC
envelope that Xcode's own client sends before the gdb-remote stream starts
(the XPC request that names the process/launch mode). Reverse-engineering that
envelope is the next task.

> **RESOLVED.** No CoreDevice envelope was needed. The missing ingredient was
> packet *ordering*: `vAttach;<hexpid>` as the very first packet on a fresh
> connection attaches and returns a full `$T11thread:…` stop packet. The
> relay now injects it ahead of LLDB's handshake. See below.

## Environment facts learned

* RSD userspace tunnel: device address `fdXX:…::1`, **host** address `fdXX:…::2`
  (`pymobiledevice3.remote.userspace_tunnel.userspace_stack_addr()`).
* The device's debugserver is reachable at
  `com.apple.internal.dt.remote.debugproxy` (port 54592) and
  `com.apple.coredevice.debugserverproxy`; both behave identically.
* `start_lockdown_service()` (with RSD check-in) **hangs** on these services —
  they are RemoteXPC, not plist, so `start_lockdown_service_without_checkin()`
  is correct.
* `LockdownTcpForwarder` does not deliver bytes for the debugproxy service;
  a custom relay is required (see `DebugProxyForwarder` in `agx_debug_win.py`).
* LLDB must be spawned with `asyncio.create_subprocess_exec` (not
  `subprocess.run`) or the relay's event loop is starved; use `-b` and
  `stdin=DEVNULL`.
* Useful LLDB setting: `plugin.process.gdb-remote.packet-timeout` (seconds).

## Device state

All AGXProbe instances were killed after the probes; `crash ls` shows no
AGXProbe crash reports (only unrelated system logs). No firmware writes,
restores, updates or boot-chain changes were made at any point.

---

## Current status (2026-11-07, end of day)

**The attach works.** The device stops the target and returns a full stop
packet with register and thread state. What is still missing is LLDB-side
bookkeeping, not device capability.

### Confirmed working

* Clean gdb-remote handshake — every reply has a correct checksum, zero NAKs.
* `vAttach;<hexpid>` injected as the first packet → `$T11thread:…;threads:…;thread-pcs:…`
  stop packet with full thread/register state.
* Request/response type-aware correlation, so `?` always receives the stop
  packet and never a stray `$m…` thread-list packet.

### Remaining blocker

LLDB's `process connect` performs its own stop-reply check and rejects the
session:

```
error: Process 1 was reported after connecting to 'connect://127.0.0.1:12345',
       but state was not stopped: invalid
error: ... no stop reply packet was received
```

Two contributing device quirks:

* `GetCurrentProcessID()` cannot get a sane pid — `qProcessInfo` returns a
  pid but `qC` carries a **thread** id and `qfThreadInfo` returns `$m<tid>`,
  which LLDB parses as a pid, landing on its bare-iron fallback `pid = 1`.
* The device answers `?` with an **empty** `$#00` because the stop event was
  already consumed by the `vAttach` reply.

### Fix being built

Cache the `vAttach` stop packet in the relay, hide it from LLDB, and replay
it in answer to LLDB's `?`; and rewrite `qProcessInfo` / `qC` /
`qfThreadInfo` / `qsThreadInfo` to `$E01` so `GetCurrentProcessID()` returns
`LLDB_INVALID_PROCESS_ID` and `process connect` takes the
"connected, no inferior" path.

### Once that lands

1. `agxwhere` — confirm the target, its modules and its thread list.
2. `agxrun` — confirm the process can be resumed and stopped through the relay.
3. `agxsweep` — evaluate `tools/opencode-temp/agx_sweep_payload.c` in-process
   (selector 0x100–0x1FF × scalarIn 0–5 × structIn 0–0x100 step 4, all-zero
   buffers) and pull `Documents/lldb_sweep.txt` with
   `python -m pymobiledevice3 apps pull $BUNDLE Documents/lldb_sweep.txt`.

Full detail: `analysis/agx/DEBUG-PROTOCOL-FINDINGS.md`.
