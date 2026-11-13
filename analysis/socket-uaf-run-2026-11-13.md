# Socket-UAF (CVE-2026-112514) — first on-device runs

Date: 2026-11-13

## Environment

| Piece | Detail |
|---|---|
| Build host | the build host (Xcode 27.2, arm64, macOS 27.3) over the VPN mesh |
| Deploy hosts | Windows PC (`pymobiledevice3`) for the 13 Pro; Mac (`devicectl`) for the 17 Pro |
| Target A | iPhone 13 Pro, iPhone14,2, iOS 27.0 (24A5390f), USB -> PC |
| Target B | iPhone 17 Pro, iPhone18,1, iOS **27.0.1** (exact target), USB -> Mac |
| Carrier | AGXProbe `--sockuaf` (Swift port of the public trigger) |

## Run 1 — iPhone 13 Pro

- Launched via `pymobiledevice3 developer dvt launch '<bundle> --sockuaf'` (pid 6449).
- Console: printed the banner and `[*] iter 0/3000`, then **terminated by SIGPIPE**.
- Cause: `send()` on a socket concurrently closed by the race thread raises `SIGPIPE`,
  which iOS delivers as a fatal signal — the app never got past iteration 0.
- Afterwards the 13 Pro dropped out of `usbmux` entirely (its Apple Mobile Device USB
  node still enumerates `Present=True`, but the mux protocol does not answer). Restarting
  the Apple Mobile Device Service and cycling the PnP node did not bring it back.
  Unresolved — needs a physical check/force-restart.

## Fix applied

`signal(SIGPIPE, SIG_IGN)` at the top of `runSocketUafMode()`, matching the upstream C PoC
(`main()` does the same).

## Run 2 — iPhone 17 Pro

- Rebuilt with `-destination id=<17 Pro>`; installed with `xcrun devicectl device install app`;
  launched with `--console`.
- Console: clean run through `[*] iter 1200/3000`, then **terminated by SIGKILL**.
- No `CORRUPTION DETECTED`. The device itself stayed healthy afterwards (still paired,
  no reboot, no panic log synced).
- Likely cause: the spray creates 256 sockets each with `SO_SNDBUF = 0xdeadbeef` (~3.7 GB);
  even clamped, that is enough kernel memory pressure to get the app jetsammed.

## Gap analysis vs the public PoC

The Swift port is functionally close but missing several details from
`analysis/references/socket_uaf_trigger.c`:

1. **Two race variants.** The PoC alternates `run_race_iteration()` (single fd) with
   `run_multi_fd_race()` (8 fds, close half / send other half). Our port only has the single-fd form.
2. **Timing.** PoC uses `usleep(500)` after connect, `usleep(100)` before triggering,
   `usleep(10)` before spraying, `usleep(100)` before checking. Ours uses 200/3000/300/2000 us.
3. **Non-blocking mode.** PoC uses `ioctl(fd, FIONBIO, 1)`; ours uses `fcntl(F_SETFL, O_NONBLOCK)`
   (equivalent, but worth matching exactly).
4. **Spray size.** `0xdeadbeef` per socket is what the PoC uses, so keep it but consider
   reducing the *count* to stay under jetsam limits, or alternate.
5. **Detection.** Same `getsockopt` checks; fine.

## Next steps

- Port both race variants faithfully (multi-fd is likely the higher-probability one).
- Reduce spray count / add yield points to avoid jetsam.
- Add a KASLR / kernel-pointer leak oracle so a won race is observable rather than silent.
- Decide per-device: the 17 Pro is the exact 27.0.1 target and works; recover the 13 Pro first.
