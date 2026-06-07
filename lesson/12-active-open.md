---
id: "12"
title: Active open (client)
requires:
  files:
    - internal/tcp/dial.go
  symbols:
    - { pkg: ./internal/tcp, name: Dial }
  lints:
    - cmd-builds
  integration: scripts/check-L12.sh
hints:
  - "Active open is the mirror of passive open. You SEND the first SYN (seq = ISS, no ACK flag), move to SYN-SENT, and wait. RFC 793 §3.4."
  - "On receiving SYN/ACK in SYN-SENT: check seg.ack == ISS+1, set RCV.IRS = seg.seq, RCV.NXT = seg.seq+1, SND.UNA = seg.ack, send a bare ACK, move to ESTABLISHED."
  - "You need an ephemeral local port. Pick a random port in 49152-65535, or just hardcode one for testing. Your stack's address (10.0.0.2) is not a kernel-local address, so the kernel has no sockets there to collide with — just don't reuse a 4-tuple already in your demux map."
  - "Dial shares almost all machinery with Listen: same demux map, same read loop, same Conn. Refactor so both passive and active opens create a Conn and register it in the demux. Don't duplicate the read loop."
  - "Common bug: your source address. You MUST send the SYN with src = 10.0.0.2 so the server's reply (dst 10.0.0.2) routes back into tun0. If you accidentally use 10.0.0.1, replies go to the kernel itself and you'll never see them. Watch for instant RSTs in tcpdump."
---

# Lesson 12 — Active open (client)

So far your stack has been a server (passive open — it waits for SYNs). Now make it a client: `tcp.Dial` initiates a connection by sending the first SYN. This is what the capstone `curl-lite` needs to connect to an HTTP server.

## Background

### Active vs passive open

```
   ACTIVE (Dial)                      PASSIVE (Listen)
   ------------                       ----------------
   send SYN  ───────────────────────►  receive SYN
   SYN-SENT                            send SYN/ACK, SYN-RECEIVED
   receive SYN/ACK  ◄────────────────  
   send ACK  ───────────────────────►  receive ACK
   ESTABLISHED                         ESTABLISHED
```

You've implemented the right column (L07–L08). The left column is this lesson.

### SYN-SENT handling (RFC 793 §3.4, §3.9)

1. `Dial`:
   - Pick a local ephemeral port.
   - Create a Conn, set `ISS`, `SND.UNA = ISS`, `SND.NXT = ISS + 1`.
   - Send a SYN: `seq = ISS`, flags `SYN`, MSS option, window = RCV.WND.
   - Transition to SYN-SENT.
   - Register in the demux map.
   - Block until ESTABLISHED (or timeout).

2. On segment arrival in SYN-SENT:
   - Expect `SYN|ACK`.
   - Validate `seg.ack == SND.NXT` (= ISS+1). If not, RST/drop.
   - Set `RCV.IRS = seg.seq`, `RCV.NXT = seg.seq + 1`, `SND.UNA = seg.ack`, `SND.WND = seg.window`.
   - Send a bare ACK (`seq = SND.NXT`, `ack = RCV.NXT`, flags `ACK`).
   - Transition to ESTABLISHED.
   - Signal whatever `Dial` is blocked on.

### Refactor, don't duplicate

`Dial` and `Listen` share: the TUN device, the read loop, the demux map, the Conn type, the segment handlers for ESTABLISHED. Refactor so there's **one** read loop and **one** Conn implementation, with passive/active differing only in how the Conn is born and the SYN-SENT vs SYN-RECEIVED handlers.

A clean shape:
- An unexported `engine` (or reuse `Listener`'s internals) owns the device + demux + read loop.
- `Listen` creates an engine in listening mode.
- `Dial` creates an engine (or reuses one), registers an active Conn, sends SYN.

If your L07 design hardcoded everything into `Listener`, this lesson is partly a refactor. That's intended — real understanding shows up when you make the passive and active paths share code without special-casing everywhere.

### Ephemeral ports

Pick a local port in the dynamic range (49152–65535). Your stack lives at `10.0.0.2`, which is not a kernel-local address, so the kernel keeps no sockets there to collide with — just don't reuse a 4-tuple that's already in your demux map.

### Who's the server? The kernel.

In the client lessons, the "real server" you dial is the **Linux kernel's own TCP stack**, running `python3 -m http.server --bind 10.0.0.1`. Your stack (as `10.0.0.2`) sends a SYN to `10.0.0.1:8080`; the kernel — which *does* own `10.0.0.1` — accepts it and runs the server side. Its SYN/ACK (dst `10.0.0.2`) routes back out `tun0` to your program. Source address discipline matters: always send as `10.0.0.2`.

## What to implement

### `internal/tcp/dial.go`

```
// Dial actively opens a connection to remote, returning an ESTABLISHED Conn
// (or an error / timeout). It performs the SYN → SYN/ACK → ACK handshake.
func Dial(remote netip.AddrPort) (*Conn, error)
```

Plus the SYN-SENT segment handler (likely in `listener.go`/the shared handler switch, or a new `handleSynSent` method).

You'll probably also need:
- A way to choose the local address. For our setup your stack's address is `10.0.0.2`; you can hardcode it or make `Dial` take it. Keep it simple — a package-level configurable local IP, or a `DialFrom(local, remote netip.AddrPort)` variant. (Remember: the SYN's source MUST be `10.0.0.2` so replies route back to tun0.)
- A timeout (use the retransmit machinery from L11 — the SYN should be retransmitted if no SYN/ACK comes, and `Dial` should give up after a few tries).

## How to test it yourself

```bash
go build ./...
sudo ./scripts/net-up.sh

# Run a REAL server on the kernel side (10.0.0.1):
python3 -m http.server 8080 --bind 10.0.0.1 &

# A throwaway main that dials and prints state:
#   c, err := tcp.Dial(netip.MustParseAddrPort("10.0.0.1:8080"))
#   log.Println(c.State(), err)   // want: ESTABLISHED <nil>
```

`make tcpdump` should show your SYN (src `10.0.0.2`), the kernel's SYN/ACK, your ACK — and then nothing (a held-open connection). If you see a RST after the SYN/ACK, your ACK validation, checksum, or source address is wrong.

## Done when

- `tcp.Dial` exists and reaches ESTABLISHED against a real `python3 -m http.server` bound to `10.0.0.1`.
- Passive (Listen) and active (Dial) paths share the read loop and Conn — no duplicated handshake state machine.
- The integration check `scripts/check-L12.sh` starts a real HTTP server on `10.0.0.1` and confirms your `Dial` reaches ESTABLISHED with no RST.

Run `/review`.
