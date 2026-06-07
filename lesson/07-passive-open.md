---
id: "07"
title: "Passive open: SYN → SYN/ACK"
requires:
  files:
    - internal/tcp/listener.go
    - internal/tcp/demux.go
  symbols:
    - { pkg: ./internal/tcp, name: Listen }
    - { pkg: ./internal/tcp, name: Listener }
    - { pkg: ./internal/tcp, name: Conn }
  lints:
    - cmd-builds
  integration: scripts/check-L07.sh
hints:
  - "A connection is identified by its 4-tuple: (local IP, local port, remote IP, remote port). Your demux needs a map keyed by that tuple. `netip.AddrPort` is comparable, so a struct of {local, remote AddrPort} works directly as a map key."
  - "On receiving a SYN to a listening port with no existing connection: create a TCB, choose ISS (a constant like 0 is fine for now; RFC 6528 wants it randomized but correctness doesn't require it), set RCV.IRS = SYN.seq, RCV.NXT = SYN.seq + 1, move to SYN-RECEIVED, and send SYN/ACK."
  - "The SYN/ACK's seq = ISS, ack = RCV.NXT (= their seq + 1). SYN consumes one sequence number — that's why ack is seq+1. RFC 793 §3.4."
  - "Common bug: wrong checksum on the SYN/ACK because the pseudo-header uses the wrong src/dst. Remember you're REPLYING — your src is the original dst, your dst is the original src."
  - "Common bug: building the IP header with the wrong protocol or total length. The total length must cover IP header + TCP header (with MSS option = 24 bytes) + 0 payload."
---

# Lesson 07 — Passive open: SYN → SYN/ACK

Now the layers connect. You'll write the read loop that pulls packets off the TUN device, demultiplexes them to connections by 4-tuple, and — for the first half of the handshake — responds to an incoming SYN with a SYN/ACK.

## Background

### Passive open

A server does a **passive open**: it announces "I'm listening on port X" and waits. When a client's SYN arrives, the server replies with SYN/ACK. This lesson implements the listener side up through sending SYN/ACK. Completing the handshake (the final ACK → ESTABLISHED) is Lesson 08.

### The read loop and demultiplexing

Your TUN device delivers raw IPv4 packets. For each packet you:

1. IPv4-parse. If protocol != TCP, drop.
2. TCP-parse the payload.
3. Build the 4-tuple: `(dstIP:dstPort, srcIP:srcPort)` from the packet's perspective — careful with direction. From *your* stack's perspective, the local side is the packet's destination and the remote side is the packet's source.
4. Look up the connection in your demux map.
   - **Found**: hand the segment to that connection's state machine.
   - **Not found, and it's a SYN to a listening port**: create a new connection in SYN-RECEIVED and reply with SYN/ACK.
   - **Not found, not a SYN**: ideally send a RST (you can defer RST to a later lesson; for now, drop).

### The 4-tuple key

```
type connKey struct {
    local  netip.AddrPort
    remote netip.AddrPort
}
```

`netip.AddrPort` is comparable, so `connKey` works as a map key with no custom hashing.

### Sending SYN/ACK — the sequence arithmetic

When a SYN arrives with sequence number `S`:
- `RCV.IRS = S`
- `RCV.NXT = S + 1`  (the SYN consumes sequence number S)
- Choose `ISS` (initial send sequence). A constant works for now.
- `SND.ISS = ISS`, `SND.UNA = ISS`, `SND.NXT = ISS + 1` (your SYN/ACK's SYN consumes ISS)
- Send a segment with: `seq = ISS`, `ack = RCV.NXT`, flags `SYN|ACK`, an MSS option (e.g. 1460), window = your RCV.WND.
- Transition to SYN-RECEIVED.

### Designing the API: `net.Listener` shape

We're aiming for `tcp.Conn` to eventually satisfy `net.Conn` and `tcp.Listener` to satisfy `net.Listener`. Start shaping toward that now:

```
// Listen binds to a local address and returns a Listener. It opens the TUN
// device internally (or accepts one — your call, but document it).
func Listen(local netip.AddrPort) (*Listener, error)

// Accept blocks until a connection reaches ESTABLISHED, then returns it.
// (In this lesson Accept may not return yet — ESTABLISHED is L08. It's fine
// for Accept to exist and block.)
func (l *Listener) Accept() (*Conn, error)
```

Internally `Listener` owns:
- the `*tun.Device`,
- the demux map (guarded by a mutex — the read loop runs in a goroutine),
- a channel of newly-established `*Conn` for `Accept` to receive from.

`Conn` owns a `*tcb.TCB` and a way to send segments (it needs access to the device or a send function). Keep the segment-building logic in one place — e.g. an unexported `func (c *Conn) sendSegment(flags uint8, payload []byte) error`.

### Goroutine model

- One goroutine runs the read loop: `for { read packet; demux; handle }`.
- `Accept` blocks on a channel.
- The demux map is shared between the read-loop goroutine and (later) `Conn.Write` calls from the user's goroutine — protect it with a `sync.Mutex` or `sync.RWMutex`.

Keep it simple: a single mutex around the whole demux + per-conn state is fine at this scale. Don't build a lock-free anything.

## What to implement

### `internal/tcp/demux.go`

- `connKey` type (the 4-tuple).
- A `demux` struct (or fields on Listener) holding `map[connKey]*Conn` + a mutex.
- A method to find-or-route a parsed segment to a Conn.

### `internal/tcp/listener.go`

- `Listen(local netip.AddrPort) (*Listener, error)`.
- `Listener.Accept() (*Conn, error)`.
- `Listener.Close() error`.
- The read loop (unexported, started as a goroutine from `Listen`).
- `Conn` type with a `*tcb.TCB` and a `sendSegment` helper.
- On SYN to the listening port: create Conn in SYN-RECEIVED, send SYN/ACK.

Recommended: a small `func (c *Conn) sendSegment(flags uint8, payload []byte) error` that builds the TCP header from the TCB's current seq/ack, marshals TCP + IP, and writes to the device. You'll reuse it everywhere.

## How to test it yourself

```bash
go build ./...
sudo ./scripts/net-up.sh

# Start a tiny program that calls tcp.Listen + Accept on 10.0.0.2:7777.
# (You'll write this as cmd/tcp-echo in L09; for now a 10-line throwaway main
#  that just Listens is fine, OR rely on the integration script which generates
#  a listener helper for you. The script connects from the kernel and checks
#  for a SYN/ACK.)

# From the host (the kernel is the client), attempt a connection. It won't
# complete yet — no final-ACK handling until L08 — but a SYN/ACK should go out:
timeout 2 nc 10.0.0.2 7777 &
sudo tcpdump -ni tun0 'tcp port 7777' -c 4 -v
```

In the tcpdump output you should see: incoming `Flags [S]` (SYN from `10.0.0.1`), then your outgoing `Flags [S.]` (SYN/ACK from `10.0.0.2`) with the correct ack number (their seq + 1) and a valid checksum (tcpdump prints `cksum 0x.... (correct)` — if it says `incorrect`, your pseudo-header is wrong).

## Done when

- `tcp.Listen`, `tcp.Listener`, `tcp.Conn` exist and the package builds.
- The integration check `scripts/check-L07.sh` opens a connection from the kernel and confirms a valid SYN/ACK was emitted **and that the kernel ACKed it** (the kernel only ACKs a SYN/ACK whose checksum and ack number are correct — a free end-to-end validation).

Run `/review`.
