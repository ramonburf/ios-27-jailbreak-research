# `m_sum16` / `m_adj_sum16`: identified functions, caller map, and reachability

Date: 2026-11-14. Images: `firmware/24A446/kernelcache.release.macho` (27.0.1) and
`firmware/24B119/kernelcache.release.macho` (27.2).
Related: `analysis/kernelcache-mbuf-len-truncation-2026-11-14.md`,
`analysis/krw-leads/network-surface-reachability-2026-11-14.md`.

## 1. The functions were unidentified; they are now named

The four changed sites found by the boundary-free diff live in two named functions of
`uipc_mbuf2.c`, plus one unnamed checksum core:

| address (24A446) | name | evidence |
|---|---|---|
| `0xfffffe000b166da8` | **`m_sum16`** | panic block loads the string `m_sum16` at `0xfffffe00070a6ad4` into the `%s:` slot of `"%s: mbuf %p len (%d) < off+len (%d+%d) @%s:%d"` |
| `0xfffffe000b166b5c` | **`m_adj_sum16`** | its panic block uses the string `m_adj_sum16` at `0xfffffe00070a6a9a` |
| `0xfffffe000ab4b600` | checksum core (unnamed) | SIMD `uadalp` reduction + RFC1071 ones-complement fold (`add w0,w0,w1` repeated) |

Source-file string `uipc_mbuf2.c` is at `0xfffffe00070a6a0e`; the validator's message is at
`0xfffffe00070a6aa6`. Function boundaries are authoritative from `LC_FUNCTION_STARTS`
(`tools/opencode-temp/kc_fstarts.py`).

### 1.1 `m_sum16` shape

```
m_sum16(mbuf *m /*x0*/, u_int off /*x1*/, u_int len /*x2*/) -> u16
  walk chain: total += m_len            ; 32-bit accumulator w9
  w10 = len + off                       ; <-- the 32-bit arithmetic Apple widened
  if (total < w10) panic("%s: mbuf %p len (%d) < off+len (%d+%d)", ...)
  call checksum_core(m, len, off)
  return result & 0xffff
```

In 27.2 the span becomes `x10 = (u64)len + (u64)off` compared against `(u64)total`
(`add x10,x10,w8,uxtw; cmp x10,x9,uxtw`), so an `off + len` that wraps modulo 2^32 is no
longer accepted.

### 1.2 Why a wrap is a bug

If `off + len >= 2^32`, the 27.0.1 check computes a small value, passes when the chain is
longer, and then calls the checksum core with the *unwrapped* `len` and `off`. The core
walks the chain consuming `len` bytes from `off`, reading past the end of the chain into
adjacent kernel memory. So the pre-fix form is a potential out-of-bounds **read** — but only
if some caller can supply such a pair.

## 2. Caller map (all `BL` xrefs, 24A446)

`m_sum16` is called from ~30 sites; `m_adj_sum16` from ~12. Identified by their own string
references:

| caller (24A446) | function identity (from strings) |
|---|---|
| `0xaf5c5cc` | `inet_cksum` (`in_cksum.c`) |
| `0xb035690` | `inet6_cksum` (`in6_cksum.c`) |
| `0xaf5c4b8`, `0xaf5c804`, `0xaf5dff0`, `0xaf62b30`, `0xaf63548` | IGMP (`igmp_sendpkt`, `igmp_v1v2_queue_report`) |
| `0xb023fa0` | MLD6 (`mld6.c`) |
| `0xb039390` | `nd6_prproxy.c` |
| `0xb01bf1c`, `0xb01dea8` | IPsec (`ipsec4_output_internal`, `ip6_input`) |
| `0xae24c8c`, `0xae25530` | bridge checksum path (`IPv4 checksum`, `IP checksum SW`) |
| `0xaf1d874`, `0xaf1fba8` | UDP per-flow / flowswitch paths |
| `0xae47910`, `0xaf8d72c`, `0xaf8f908`, `0xafa9890`, `0xb2282fc`, `0xb229ce4` | TCP/mbuf checksum-offload paths (`mbuf_csum`, tcp rtt strings) |
| `0xb03fa9c`, `0xafde0ec`, `0xafed0a4`, `0xafed270`, `0xb082334` | netinet6 / network-accounting neighbours |

Several argument pairs are **differences of header fields**, which is the natural source of a
negative value that becomes a huge `u_int`:

```
0xae47910:  ldr w8,[x19,#0x60] ; sub w2,w8,w20   ; len = [obj+0x60] - w20
0xaf8ea30:  ldrh w1,[x0,#0x6a] ; ldrh w8,[x26,#2]; sub w3,w8,w1
0xb229ce4:  ...                  ; sub w2,w26,w22
```

`w2`/`w3` are passed straight into `m_sum16`/`m_adj_sum16`, so an underflow there becomes
`0xFFFFFFFF`-scale `len` and makes `off + len` wrap. That is exactly the mechanism Apple
fixed by widening the comparison.

## 3. Reachability verdict: not app-reachable

The `--rawsock` device probe (`analysis/krw-leads/network-surface-reachability-2026-11-14.md`)
measured on both iPhones that `SOCK_RAW` (IPv4/IPv6), `PF_NDRV` and `/dev/bpf*` are all
refused with `EPERM` from the app sandbox. Without raw sockets or BPF there is no way for an
app to make the kernel process a packet whose header-derived lengths are chosen by the
attacker.

⇒ **`m_sum16`/`m_adj_sum16` is a real, Apple-fixed integer-wrap/OOB-read defect but it is
reachable only by a network peer.** It matches the `AV:N` class of the advisories, not the
app-carried requirement of this project, so it is recorded as a bounded lead and a candidate
for an Apple Security Bounty report — not as a jailbreak primitive.

## 4. Tooling

`kc_fstarts.py` (boundaries), `kc_find_func.py` (string refs), `kc_find_calls.py` (BL xrefs),
and the scratch scripts used here (`scratch/mbuf_fn2.py`, `scratch/mbuf_xref.py`,
`scratch/mbuf_callers.py`, `scratch/cmp_w0_3.py`).
