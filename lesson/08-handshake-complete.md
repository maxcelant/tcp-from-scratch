---
id: "08"
title: Completing the handshake
requires:
  files:
    - internal/tcp/listener.go
  symbols:
    - { pkg: ./internal/tcp, name: Conn.State }
  lints:
    - cmd-builds
  integration: scripts/check-L08.sh
hints:
  - "In SYN-RECEIVED, the segment you're waiting for is an ACK whose ack number equals SND.NXT (your ISS+1). When it arrives, advance SND.UNA and transition to ESTABLISHED. RFC 793 §3.4 / §3.9 'SEGMENT ARRIVES'."
  - "While in SYN-RECEIVED, drop (or RST) any non-ACK segment. Don't transition on a stray SYN retransmit — just resend your SYN/ACK if you get a duplicate SYN."
  - "Accept should return the Conn only once it reaches ESTABLISHED. Use a channel: when the read loop moves a Conn to ESTABLISHED, push it onto the accept channel."
  - "Common bug: not validating the incoming ACK number. If you blindly go to ESTABLISHED on any ACK, you'll accept bogus connections. Check seg.ack == SND.NXT."
  - "Common bug: a race between the read-loop goroutine moving to ESTABLISHED and Accept reading the Conn. Make sure the state transition and the channel push are ordered correctly under your mutex."
---

# Lesson 08 — Completing the handshake

You sent a SYN/ACK in Lesson 07. Now you'll handle the client's final ACK and reach **ESTABLISHED** — a fully open TCP connection. `Accept()` will return a usable `Conn`.

## Background

### The third leg

```
   client                          your stack
     |                                  |
     |------------- SYN --------------->|   (L07: you received this)
     |<--------- SYN/ACK ---------------|   (L07: you sent this)
     |------------- ACK --------------->|   (L08: handle this → ESTABLISHED)
     |                                  |
     |======== connection open ========|
```

The client's final ACK has:
- `seq = client_ISS + 1` (= your RCV.NXT, since you already counted their SYN)
- `ack = your_ISS + 1` (= your SND.NXT)
- flags = `ACK` only (no SYN)

### State transition (RFC 793 §3.9, "SYN-RECEIVED STATE")

When a segment arrives while in SYN-RECEIVED:
1. **Check the sequence number** is acceptable (it should equal RCV.NXT — no data yet).
2. **If RST**: drop the connection.
3. **If SYN** (a retransmit): you can resend your SYN/ACK, or ignore. Don't transition.
4. **If ACK**:
   - If `seg.ack == SND.NXT` (your ISS+1): the handshake completed. Set `SND.UNA = seg.ack`, transition to **ESTABLISHED**.
   - Otherwise: the ACK is unacceptable — drop (or RST).
5. Now in ESTABLISHED, this same ACK might also carry data (in general). For this lesson the final ACK carries no data, so don't worry about it yet — Lesson 09 handles data.

### Wiring Accept

The read-loop goroutine is the one that processes the final ACK and flips the state. `Accept()` is blocked in the user's goroutine. Connect them with a channel:

- When a Conn transitions to ESTABLISHED, the read loop pushes it onto `l.accepted <- conn`.
- `Accept()` does `conn := <-l.accepted; return conn, nil`.

Guard the state read/write with the listener's mutex so `Conn.State()` is safe to call from any goroutine.

### `Conn.State()`

Add an accessor:

```
// State returns the current connection state (RFC 793).
func (c *Conn) State() tcb.State
```

This is what the integration check and your tests use to confirm ESTABLISHED.

## What to implement

Extend `internal/tcp/listener.go` (and demux as needed):

1. A handler for segments arriving at a Conn in SYN-RECEIVED:
   - Validate the ACK.
   - On valid ACK: advance `SND.UNA`, set state ESTABLISHED, push to the accept channel.
   - On RST: tear down (remove from demux map).
   - On duplicate SYN: optionally resend SYN/ACK.
2. `Conn.State() tcb.State` accessor (mutex-protected).
3. Make `Accept()` actually return on ESTABLISHED.

Keep the per-state handling readable. A `switch c.tcb.State` dispatching to small unexported methods (`handleSynReceived`, later `handleEstablished`, etc.) is the clean shape. Don't build a fancy transition table yet — a switch is fine and matches how RFC 793 §3.9 is written.

## How to test it yourself

```bash
go build ./...
sudo ./scripts/net-up.sh

# Throwaway listener main (or the integration script's helper):
#   l, _ := tcp.Listen(netip.MustParseAddrPort("10.0.0.2:7777"))
#   c, _ := l.Accept()
#   log.Println("ESTABLISHED with", c.RemoteAddr(), c.State())

# From the host (the kernel is the client), a full connect:
nc 10.0.0.2 7777
# nc should stay connected (no immediate disconnect). Type nothing — just
# confirm the connection holds open. Ctrl-C to quit.
```

Watch with `make tcpdump`: you should see S, S., then `.` (the bare ACK), and then silence (no RST). If you see a RST come back from your stack after the ACK, your validation is rejecting the legitimate ACK.

## Done when

- `Conn.State()` exists.
- A full 3-way handshake drives a Conn to ESTABLISHED and `Accept()` returns it.
- The integration check `scripts/check-L08.sh` performs a real connect from the kernel, confirms (via a helper that prints `c.State()`) the connection reaches ESTABLISHED, and confirms no RST is emitted.

Run `/review`.
