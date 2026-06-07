---
id: "06"
title: TCB & state machine skeleton
requires:
  files:
    - internal/tcb/state.go
    - internal/tcb/tcb.go
    - internal/tcb/state_test.go
  symbols:
    - { pkg: ./internal/tcb, name: State }
    - { pkg: ./internal/tcb, name: TCB }
  tests:
    - ./internal/tcb/...
  lints:
    - tcb-no-io-imports
hints:
  - "RFC 793 §3.2 has the canonical state diagram. There are 11 states: CLOSED, LISTEN, SYN-SENT, SYN-RECEIVED, ESTABLISHED, FIN-WAIT-1, FIN-WAIT-2, CLOSE-WAIT, CLOSING, LAST-ACK, TIME-WAIT. Model them as an enum (`type State int` + iota constants)."
  - "The TCB (Transmission Control Block) holds the send/receive sequence variables. RFC 793 §3.2 names them: SND.UNA, SND.NXT, SND.WND, ISS (send), RCV.NXT, RCV.WND, IRS (receive). Group them into a Send and Recv struct — it reads better than 8 loose fields."
  - "This package must stay PURE — no `os`, `net`, `syscall` imports. It's just state and arithmetic. The /review lint enforces this. If you're tempted to import `net`, you want `net/netip` for addresses instead (that's allowed; it's a value type)."
  - "Give State a `String()` method covering all 11 states. The /review check and your own debugging both rely on it. A missing case returning \"State(7)\" is a smell."
  - "Don't implement transitions yet — just the types and a way to hold the 4-tuple (local addr/port, remote addr/port) plus the sequence variables. Behavior comes in L07+."
---

# Lesson 06 — TCB & state machine skeleton

Before we touch the wire again, we model TCP's brain: the **state machine** and the **Transmission Control Block (TCB)**. This lesson is pure data modeling — no I/O, no packets. The payoff is that all of TCP's tricky sequence-number logic becomes unit-testable without sockets.

## Background

### The TCP state machine (RFC 793 §3.2)

A TCP connection is a finite state machine. There are 11 states:

```
                              +---------+
                              |  CLOSED |
                              +---------+
                          (passive open)  (active open: send SYN)
                                |               |
                                v               v
                          +---------+      +----------+
                          | LISTEN  |      | SYN-SENT |
                          +---------+      +----------+
                   (recv SYN: send SYN/ACK)|     |
                                |          (recv SYN/ACK: send ACK)
                                v          v
                          +--------------+
                          | SYN-RECEIVED |
                          +--------------+
                          (recv ACK)  |
                                      v
                          +--------------+
                          | ESTABLISHED  |  <─── data transfer happens here
                          +--------------+
            (close: send FIN) |        | (recv FIN: send ACK)
                              v        v
                       +-----------+  +------------+
                       |FIN-WAIT-1 |  | CLOSE-WAIT |
                       +-----------+  +------------+
                          |    |            | (close: send FIN)
       (recv ACK of FIN)  |    |(recv FIN)  v
                          v    |       +----------+
                  +-----------+|       | LAST-ACK |
                  |FIN-WAIT-2 ||       +----------+
                  +-----------+|            | (recv ACK)
                          |    v            v
                          | +--------+   +--------+
                          | |CLOSING |   | CLOSED |
                          | +--------+
                          |    |(recv ACK)
                          v    v
                       +----------+
                       |TIME-WAIT | (wait 2*MSL, then CLOSED)
                       +----------+
```

Don't try to absorb every transition now — you'll implement them across L07–L13. What you need this lesson is the **set of states** as a Go type.

### The Transmission Control Block

The TCB is the per-connection state. RFC 793 §3.2 defines the sequence variables it must track:

**Send Sequence Space:**
```
       1         2          3          4
  ----------|----------|----------|----------
         SND.UNA    SND.NXT    SND.UNA
                              +SND.WND

  1 - old sequence numbers which have been acknowledged
  2 - sequence numbers of unacknowledged data
  3 - sequence numbers allowed for new data transmission
  4 - future sequence numbers which are not yet allowed
```

- `SND.UNA` — oldest unacknowledged sequence number.
- `SND.NXT` — next sequence number to send.
- `SND.WND` — send window (how much the peer will accept).
- `ISS` — initial send sequence number (chosen at connection start).

**Receive Sequence Space:**
```
       1          2          3
  ----------|----------|----------
         RCV.NXT    RCV.NXT
                   +RCV.WND

  1 - old sequence numbers which have been acknowledged
  2 - sequence numbers allowed for new reception
  3 - future sequence numbers which are not yet allowed
```

- `RCV.NXT` — next sequence number expected from the peer.
- `RCV.WND` — receive window (how much you'll accept).
- `IRS` — initial receive sequence number (the peer's ISS, learned from their SYN).

### Why a separate `tcb` package?

This is the SOLID payoff of the project. `tcb` is **pure state**: given the current TCB and an incoming segment's header, it can decide what the new state should be and what to send — all as plain arithmetic, no file descriptors, no goroutines. That makes it trivially unit-testable. The `tcp` package (L07+) will wire `tcb` to the TUN device.

**The `/review` lint `tcb-no-io-imports` enforces purity**: if `internal/tcb` imports `os`, `net`, `syscall`, or `golang.org/x/sys`, the check fails. (`net/netip` is allowed — it's a pure value type.)

## What to implement

### `internal/tcb/state.go`

```
package tcb

// State is a TCP connection state per RFC 793 §3.2.
type State int

const (
    StateClosed State = iota
    StateListen
    StateSynSent
    StateSynReceived
    StateEstablished
    StateFinWait1
    StateFinWait2
    StateCloseWait
    StateClosing
    StateLastAck
    StateTimeWait
)

// String returns the RFC name, e.g. "SYN-RECEIVED".
func (s State) String() string
```

### `internal/tcb/tcb.go`

```
package tcb

import "net/netip"

// Send holds the send sequence space (RFC 793 §3.2).
type Send struct {
    UNA uint32 // oldest unacknowledged
    NXT uint32 // next to send
    WND uint16 // send window
    ISS uint32 // initial send sequence
}

// Recv holds the receive sequence space.
type Recv struct {
    NXT uint32 // next expected
    WND uint16 // receive window
    IRS uint32 // initial receive sequence
}

// TCB is the Transmission Control Block for one connection.
type TCB struct {
    State State
    Local  netip.AddrPort
    Remote netip.AddrPort
    Snd Send
    Rcv Recv
}
```

You may add small helpers you'll want later, but keep them pure:
- `func (t *TCB) String() string` for debugging.
- A `Key` type or method returning the 4-tuple for use as a map key in L07 (`netip.AddrPort` pairs are comparable, so a struct of two of them works as a map key directly).

### `internal/tcb/state_test.go`

- Assert `State(i).String()` returns the correct RFC name for all 11 states.
- Assert an out-of-range State doesn't panic (returns something like `"State(99)"`).
- A trivial TCB construction test (set fields, read them back) — mostly to anchor the package.

## How to test it yourself

```bash
go test ./internal/tcb/... -v
go list -deps ./internal/tcb/... | grep -E '^(os|net|syscall)$' && echo "IMPURE" || echo "pure"
```

The second command should print `pure`.

## Done when

- All 11 states exist with correct `String()` output.
- `TCB`, `Send`, `Recv` types match the RFC variable names.
- The `tcb` package imports nothing from `os`/`net`/`syscall`/`golang.org/x/sys`.
- Tests pass.

Run `/review`.
