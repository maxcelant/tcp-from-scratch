---
id: "13"
title: FIN teardown
requires:
  files:
    - internal/tcp/listener.go
  symbols:
    - { pkg: ./internal/tcp, name: Conn.Close }
  lints:
    - cmd-builds
  integration: scripts/check-L13.sh
hints:
  - "Like SYN, FIN consumes one sequence number. When you send a FIN, SND.NXT advances by 1. When you receive a FIN, RCV.NXT advances by 1 and you ACK it. RFC 793 §3.5."
  - "Closing side (active close): Conn.Close sends FIN, moves ESTABLISHED → FIN-WAIT-1. On ACK of your FIN → FIN-WAIT-2. On peer's FIN → send ACK → TIME-WAIT. RFC 793 §3.5 figure 13."
  - "Receiving side (passive close): peer's FIN arrives in ESTABLISHED → ACK it, move to CLOSE-WAIT, surface io.EOF to Conn.Read. When the app calls Close → send FIN → LAST-ACK. On ACK → CLOSED."
  - "TIME-WAIT should wait 2*MSL before fully closing. MSL is nominally 2 minutes; for testing use 1-2 seconds. Use your Clock from L11 so tests don't actually sleep 4 minutes."
  - "Common bug: not delivering io.EOF to a blocked Conn.Read when the peer's FIN arrives. Your RecvBuffer.CloseWrite (from L09) is what wakes the reader with EOF."
---

# Lesson 13 — FIN teardown

A connection that never closes leaks. This lesson implements graceful shutdown: the FIN handshake that closes each direction of the connection independently, walking through FIN-WAIT, CLOSE-WAIT, LAST-ACK, and TIME-WAIT. After this, `Conn` fully satisfies `io.Closer` (and is close to a complete `net.Conn`).

## Background

### FIN consumes a sequence number

Like SYN, a FIN occupies one byte of sequence space. If your last data byte was seq 1000, your FIN is seq 1001, and the peer ACKs 1002. This is why a clean close is "+1" everywhere.

### The two teardown paths (RFC 793 §3.5)

TCP close is symmetric — each side closes its own direction. Two roles:

**Active close (you call `Close()` first):**
```
ESTABLISHED
   │ app calls Close(): send FIN
   ▼
FIN-WAIT-1
   │ recv ACK of our FIN
   ▼
FIN-WAIT-2
   │ recv peer's FIN: send ACK
   ▼
TIME-WAIT
   │ wait 2*MSL
   ▼
CLOSED
```

**Passive close (peer closes first):**
```
ESTABLISHED
   │ recv peer's FIN: send ACK, deliver EOF to Read
   ▼
CLOSE-WAIT
   │ app calls Close(): send FIN
   ▼
LAST-ACK
   │ recv ACK of our FIN
   ▼
CLOSED
```

(There's also a simultaneous-close path through CLOSING — implement it if you like, but the integration test uses the two common paths above.)

### TIME-WAIT

After the active closer sends the final ACK, it waits **2×MSL** (Maximum Segment Lifetime) before truly closing, in case that ACK was lost and the peer retransmits its FIN. MSL is nominally 2 minutes (so TIME-WAIT is ~4 minutes on real systems). **For testing, use 1–2 seconds** — and use the `Clock` interface from Lesson 11 so unit tests can advance time instantly instead of sleeping.

### Delivering EOF

When the peer's FIN arrives, the receive direction is done. A `Conn.Read` blocked waiting for data must return `io.EOF`. Your `RecvBuffer.CloseWrite()` (defined in L09) marks the buffer closed; the next drained `Read` returns `io.EOF`. Wire the FIN handler to call it.

## What to implement

Extend `internal/tcp/listener.go` (and the shared segment handlers):

1. **`Conn.Close()`** (`io.Closer`):
   - From ESTABLISHED: send FIN (seq = SND.NXT, which then advances by 1), go to FIN-WAIT-1.
   - From CLOSE-WAIT: send FIN, go to LAST-ACK.
   - Idempotent: calling Close twice shouldn't double-send.

2. **Incoming FIN handling** in each relevant state:
   - ESTABLISHED + FIN: ACK it (RCV.NXT += 1), CloseWrite the recv buffer (EOF), go to CLOSE-WAIT.
   - FIN-WAIT-1 + ACK-of-our-FIN: go to FIN-WAIT-2.
   - FIN-WAIT-2 + peer FIN: ACK, go to TIME-WAIT, start the 2*MSL timer.
   - LAST-ACK + ACK-of-our-FIN: go to CLOSED, remove from demux.
   - TIME-WAIT timer expiry: go to CLOSED, remove from demux.

3. **TIME-WAIT timer** using the L11 Clock.

Keep using the per-state switch/dispatch shape. The state machine is now substantial — this is a good moment to make sure each state's handler is a small, named, readable method.

## How to test it yourself

```bash
go build ./...
sudo ./scripts/net-up.sh
sudo ./tcp-echo &

# nc closes its side after sending; your echo server should see EOF, echo
# remaining data, and close cleanly.
echo "bye" | nc -q1 10.0.0.2 7777
# Expect: "bye" echoed back, then clean FIN exchange.
```

In `make tcpdump` you should see a clean teardown: `F.` (FIN/ACK) from one side, `.` (ACK), `F.` from the other, `.` — and crucially **no RST**. A RST during teardown means a state-machine bug.

## Done when

- `Conn.Close()` implements `io.Closer` and drives the active-close path to TIME-WAIT → CLOSED.
- Incoming FIN drives the passive-close path and delivers `io.EOF` to `Conn.Read`.
- TIME-WAIT uses the Clock (no 4-minute real sleeps in tests).
- The integration check `scripts/check-L13.sh` runs a connection that the client closes (`nc -q1`) and confirms a clean FIN exchange (FIN from both sides, no RST).

Run `/review`.
