# iOS 27.0.1 debugserver — gdb-remote protocol findings

Date: 2026-11-07
Device: iPhone18,1 / iOS 27.0.1 (24A446) / UDID `<device-udid>`
Host: Windows PC, no macOS/Xcode
Driver: `tools/opencode-temp/agx_debug_win.py`
Probes: `tools/opencode-temp/probe_*.py`

Everything here was established by reading the raw bytes on the gdb-remote
socket. **No device state was modified**; the only device interaction was
opening debug sessions and querying state.

---

## 1. Transport

* The device's debugserver is reachable through the RSD userspace tunnel via
  the lockdown service `com.apple.internal.dt.remote.debugproxy`
  (port 54592) and `com.apple.coredevice.debugserverproxy` (port 54559).
  Both are `UsesRemoteXPC: True` with entitlement
  `com.apple.private.CoreDevice.canDebugApplicationsOnDevice`.
* Both services answer **raw gdb-remote** — there is no XPC handshake to
  perform before the `$...#xx` stream starts.
* `start_lockdown_service()` **hangs** on these services. Use
  `start_lockdown_service_without_checkin()`.
* `pymobiledevice3`'s `LockdownTcpForwarder` opens the service but delivers
  **no bytes** for it. A custom byte relay is required
  (`DebugProxyForwarder` in `agx_debug_win.py`).
* RSD userspace tunnel addressing: the **device** is `fdXX:…::1`, the
  **host** is `fdXX:…::2`
  (`pymobiledevice3.remote.userspace_tunnel.userspace_stack_addr()`).
* LLDB must be spawned with `asyncio.create_subprocess_exec` and `-b` with
  `stdin=DEVNULL`. A blocking parent event loop starves the relay's forwarder
  and the handshake times out.
* Useful setting: `plugin.process.gdb-remote.packet-timeout` (seconds).

## 2. The breakthrough — `vAttach` must be the FIRST packet

> The device's debugserver only honours `vAttach;<hexpid>` when it is the
> **very first gdb-remote packet on a fresh connection**.

Raw proof (`tools/opencode-temp/probe_vattach_first.py`):

```
FIRST vAttach;4a31
     -> b'+$T11thread:518dee;...'
```

The device stops the target and answers with a full `$T<signal>thread:…;…`
stop packet immediately. Consequences:

* If **any** query precedes it (`qHostInfo`, `qSupported`, …), the device
  silently ignores `vAttach` and every later attach packet — while still
  answering ordinary queries normally, so the failure looks like "the
  debugserver has no target-selection mechanism".
* The relay therefore **injects** `vAttach;<hexpid>` as the first packet on
  the lldb→device stream, before any LLDB handshake packet.

This single fact invalidated the earlier conclusion recorded in
`analysis/agx/debugger-attach-status.md` ("the debugserver … has no
target-selection mechanism reachable from the raw gdb-remote socket").

## 3. Attach spellings that are ignored when not first

Measured on a fresh connection with the handshake already performed:

| packet | result |
|---|---|
| `vAttach;<hexpid>` | **works only as the first packet** → `$T11thread:…` |
| `vAttach;<decpid>` | ignored |
| `vAttachOrWait;<hexpid>` | ignored |
| `vAttachWait;<hexpid>` | ignored |
| `vAttachName;AGXProbe` | ignored |
| `vAttach;<hexpid>;1` | ignored |
| `vAttach;<pid>:0` (gdb form) | `$E96` (error 150) |
| `qAttach;<pid>` | `$#00` (empty) |
| `A,<len>,0,<hex path>` (LLDB launch form) | ignored |

State queries on a session with no inferior:

```
?            -> $E02   (no process)
qProcessInfo -> $E68
qfThreadInfo -> $OK   (empty)
qC           -> $QC0
```

## 4. Three device quirks that break LLDB's parser

The relay rewrites packets; the device is never modified.

### 4.1 `$QStartNoAckMode`

The device answers `OK` and then **stops computing real checksums** — every
subsequent reply gets `#00`. LLDB only leaves ack mode when the reply *is*
`OK`, so it proceeds expecting valid checksums and NAKs everything.

**Fix:** rewrite the packet to `$qHostInfo`. The device stays in ack mode and
keeps sending correct checksums.

### 4.2 `$QEnableCompression:type:zlib-deflate;`

After this the device switches to LLDB's compressed framing `"$N<payload>#<cksum>"`.
LLDB's `DecompressPacket()` strips the `N` but keeps the checksum the device
computed *with* the `N` included, so the second checksum check fails.

**Fix:** rewrite to `$qHostInfo`. (LLDB only enables compression if the reply
to this packet is `OK`.)

### 4.3 Bogus process/thread reporting

* `qProcessInfo` replies `pid:<hex>;parent-pid:…;real-uid:…;cputype:100000c;…`.
* `qC` replies `QC<hex>` — and that hex is a **thread** id, not a process id.
* `qfThreadInfo` replies `$m<tid>` — a thread-list continuation, which LLDB's
  `GetCurrentProcessAndThreadIDs` parses as a *pid*.

The consequence is that LLDB concludes `pid = tid = 1` (its bare-iron
fallback `ids.emplace_back(1, 1)`), and then `SetThreadStopInfo()` fails its
`stop_pid != pid` check, producing:

```
error: Process 1 was reported after connecting to 'connect://127.0.0.1:12345',
       but state was not stopped: invalid
```

**Fix in progress:** rewrite `qProcessInfo` / `qC` / `qfThreadInfo` /
`qsThreadInfo` to `$E01` so `GetCurrentProcessID()` returns
`LLDB_INVALID_PROCESS_ID` and `process connect` takes the
`"connected, no inferior"` path with no stop-reply check.

### 4.4 The stop-reply problem (remaining blocker)

Even with a valid pid, `process connect` sends `?` and waits for a stop
packet. The device answers `?` with an **empty** `$#00` (or `$E02`), because
the stop event was already consumed by the `vAttach` reply. LLDB then reports
either:

```
error: ... but state was not stopped: invalid
error: ... no stop reply packet was received
```

**The fix that is being built:** cache the `$T11thread:…` stop packet that the
injected `vAttach` produced, hide it from LLDB (so it does not get consumed
as the answer to an unrelated handshake query), and replay it in response to
LLDB's `?`.

## 5. Request/response correlation

LLDB pipelines requests (it can send `qfThreadInfo` and `?` back to back
without waiting), and the device's replies can arrive inside a single TCP
chunk. LLDB's own reader takes packets from a single FIFO, so a mis-ordered
or mis-typed packet desynchronises the whole session.

The relay therefore maintains a session model that matches each device→LLDB
response to the oldest outstanding LLDB→device request of a **compatible
type**:

| request | response |
|---|---|
| `qfThreadInfo` / `qsThreadInfo` | `$m…`, `$l…` |
| `?`, `vCont`, `vAttach` | `$T…`, `$S…` |
| anything else | `$OK`, `$E…`, … (matches any request) |

The injected `vAttach` is registered as a **hidden** request: it is the only
request allowed to consume a stop-type response, and its response is cached
rather than delivered.

## 6. The Instruments DTX debugserver channel

`com.apple.instruments.server.services.debugserver` **exists** on the device
and opens successfully, but the device **cancels the channel on the first
invocation of every selector tried**:

* `requestConnectionAtPort:`
* `attachToProcessWithIdentifier:`
* `launchSuspendedProcessWithDevicePath:…`

The same launch selector works fine on the `processcontrol` channel, so the
cancellation is specific to the debugserver channel.

## 7. Supporting facts

* `isPidDebuggable:` (DVT process control) returns **True** for the probe app.
* The app is dev-signed with `get-task-allow`; `is_debuggable` → True.
* The debugproxy service advertises the feature
  `com.apple.coredevice.feature.debugserverproxy`.

## 8. Where the artefacts live

| file | purpose |
|---|---|
| `tools/opencode-temp/agx_debug_win.py` | main driver: RSD tunnel → relay → LLDB |
| `tools/opencode-temp/probe_vattach_first.py` | proof that `vAttach` must be first |
| `tools/opencode-temp/probe_attach_variants.py` | all the ignored attach spellings |
| `tools/opencode-temp/probe_dtx_debugserver2.py` | Instruments DTX debugserver channel |
| `tools/opencode-temp/probe_debug_services.py` | debugproxy service enumeration |
| `tools/opencode-temp/probe_gdbraw.py`, `probe_noack.py`, `probe_trace.py` | framing / checksum probes |
| `tools/opencode-temp/cleanup_probe_state.py` | kills leftover probe instances |
| `analysis/evidence/2026-11-07-rsd-info.json` | RSD tunnel facts |
| `analysis/evidence/2026-11-06-pymd-debugserver-lldb-run.log` | `pymobiledevice3 developer debugserver lldb` failure trace (shows the pty limitation) |

## 9. Current state

The transport is clean (valid checksums, zero NAKs) and the **attach itself
works** — the device stops the target and returns a full stop packet when the
relay injects `vAttach` first. What remains is LLDB-side: getting
`process connect` to accept the stop reply so that the attached process can
be driven (thread list, resume/stop, expression evaluation for the AGX
argument-shape sweep).
