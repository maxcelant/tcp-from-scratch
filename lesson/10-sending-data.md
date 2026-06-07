---
id: "10"
title: Sending data
requires:
  files:
    - internal/tcb/sendbuf.go
    - internal/tcp/output.go
    - cmd/tcp-echo/main.go
  symbols:
    - { pkg: ./internal/tcp, name: Conn.Write }
  tests:
    - ./internal/tcb/...
  lints:
    - cmd-builds
    - tcb-no-io-imports
  integration: scripts/check-L10.sh
hints:
  - "Conn.Write appends to a send buffer, then the output path segments it into MSS-sized chunks, each with seq = SND.NXT, advancing SND.NXT by the chunk length. RFC 793 §3.7 'Sending Data'."
  - "Honor the peer's window: never let (SND.NXT - SND.UNA) exceed SND.WND. Don't send bytes the peer has no room for. For a first pass you can assume the window is always large enough (nc advertises ~64KB) but the check should exist."
  - "When you receive an ACK in ESTABLISHED, advance SND.UNA to seg.ack (if it's in (SND.UNA, SND.NXT]). That frees buffer space and (in L11) cancels retransmit timers."
  - "The PSH flag is informational — set it on segments that flush the send buffer. It doesn't change semantics for us. Don't overthink it."
  - "Common bug: not updating SND.WND from incoming segments' Window field. The peer tells you its receive window on every ACK; track it as SND.WND."
---

# Lesson 10 — Sending data

You can receive; now you can send. Implement `Conn.Write` (the `io.Writer` half), segment the outgoing stream into MSS-sized TCP segments, and respect the peer's advertised window. Then upgrade `tcp-echo` into a real echo server that writes received bytes back.

## Background

### Sending data (RFC 793 §3.7)

`Conn.Write(p)` doesn't immediately put `p` on the wire as one segment. It:
1. Appends `p` to the **send buffer**.
2. The output path pulls bytes from the buffer and forms segments, each at most **MSS** bytes (you negotiated MSS in the SYN; 1460 is typical, or use the peer's advertised MSS).
3. Each segment: `seq = SND.NXT`, `ack = RCV.NXT`, flags `ACK` (+ `PSH` on the last/flushing segment). After sending, `SND.NXT += len(segment_payload)`.

### Flow control: the send window

The peer advertises a **receive window** in every segment's Window field. That becomes your `SND.WND`. The invariant:

```
SND.NXT - SND.UNA  ≤  SND.WND
```

i.e. you may have at most `SND.WND` bytes "in flight" (sent but unacknowledged). Before sending a segment, check there's window room. If the window is full, the data stays in the send buffer until an ACK opens the window.

For a first pass against `nc` (which advertises ~64KB), the window will rarely be the limiting factor — but **implement the check anyway**; it's the whole point of flow control, and the L10 integration test sends enough data to matter.

### Advancing SND.UNA on ACK

When an ACK arrives in ESTABLISHED:
- If `SND.UNA < seg.ack ≤ SND.NXT`: advance `SND.UNA = seg.ack`. This acknowledges (and frees) those bytes from the send buffer.
- Update `SND.WND = seg.window`.
- (L11: this is also where you cancel/reschedule retransmit timers.)

### The send buffer

```
package tcb

// SendBuffer holds outgoing bytes not yet acknowledged.
type SendBuffer struct {
    // unacked bytes + bookkeeping mapping buffer offsets to sequence numbers
}

func (s *SendBuffer) Write(p []byte) int      // app enqueues
func (s *SendBuffer) Acked(upto uint32)        // drop bytes the peer ACKed
// plus a way for the output path to read "next unsent chunk up to n bytes"
```

Keep it pure (sync allowed, no I/O). The mapping from byte offsets to sequence numbers is the interesting part: track the sequence number of the first byte in the buffer, so `Acked(seg.ack)` can compute how many bytes to drop.

### The output path

`internal/tcp/output.go` holds the logic that turns "there are bytes to send and window allows it" into actual segments written to the device. This is where segmentation + the window check live. It's called:
- when the app calls `Conn.Write` (try to send immediately), and
- when an ACK opens the window (try to send more).

## What to implement

### `internal/tcb/sendbuf.go`

`SendBuffer` + tests (`sendbuf_test.go`):
- Write then "next chunk" returns the bytes, capped at the requested size.
- `Acked` drops the right number of bytes and is idempotent for duplicate/old ACKs.
- Sequence-number wraparound: `Acked` works correctly when sequence numbers wrap past 2³². (Use the comparison helper from RFC 793 §3.3 — `a < b` in sequence space means `int32(a-b) < 0`.)

### `internal/tcp/output.go`

- `func (c *Conn) sendData()` (or similar): while there are unsent bytes AND window room, form an MSS-sized segment and send it, advancing SND.NXT.
- Called from `Conn.Write` and from the ACK handler.

### Extend `internal/tcp/listener.go`

- On ACK in ESTABLISHED: advance SND.UNA, update SND.WND, call `sendData()` to push more if the window opened.

### `Conn.Write`

```
// Write implements io.Writer. It enqueues p for transmission and returns
// len(p) once buffered (it does not block for the bytes to be ACKed).
func (c *Conn) Write(p []byte) (int, error)
```

### Upgrade `cmd/tcp-echo/main.go`

Make it a real echo: `io.Copy(conn, conn)` — read bytes, write them straight back. (Now that Conn is both Reader and Writer, `io.Copy` just works. That's the payoff of implementing the stdlib interfaces.)

## How to test it yourself

```bash
go build ./...
sudo ./scripts/net-up.sh
sudo ./tcp-echo &

echo "round trip test" | nc -q1 10.0.0.2 7777
# Should print back: round trip test

# Bigger test — force multiple segments:
head -c 5000 /dev/urandom | base64 | nc -q1 10.0.0.2 7777 | wc -c
# Output byte count should match what was sent.
```

`make tcpdump` should show your data segments going out with increasing seq numbers, each ≤ MSS, and the peer's ACKs advancing.

## Done when

- `SendBuffer` passes unit tests including sequence wraparound.
- `Conn.Write` enqueues and segments correctly, respecting SND.WND.
- `tcp-echo` echoes data back (small and multi-segment).
- The integration check `scripts/check-L10.sh` sends a multi-segment (~6 KB) payload through the echo server and confirms it comes back byte-identical.

Run `/review`.
