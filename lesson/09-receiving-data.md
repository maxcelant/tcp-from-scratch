---
id: "09"
title: Receiving data + ACKing
requires:
  files:
    - internal/tcb/recvbuf.go
    - internal/tcp/listener.go
    - cmd/tcp-echo/main.go
  symbols:
    - { pkg: ./internal/tcp, name: Conn.Read }
  tests:
    - ./internal/tcb/...
  lints:
    - cmd-builds
    - tcb-no-io-imports
  integration: scripts/check-L09.sh
hints:
  - "In ESTABLISHED, a segment with a payload whose seq == RCV.NXT is in-order data. Append it to the receive buffer, advance RCV.NXT by len(payload), and send an ACK with ack = new RCV.NXT. RFC 793 §3.7 'Receiving Segments'."
  - "For now, accept ONLY in-order segments (seq == RCV.NXT). If seg.seq != RCV.NXT, drop the payload but still ACK with your current RCV.NXT (a duplicate ACK) so the sender knows where you are. No reassembly queue yet."
  - "Conn.Read should satisfy io.Reader: block until data is available, copy into the caller's buffer, return n. Use a condition variable (sync.Cond) or a channel to wake Read when the read-loop goroutine appends data."
  - "Common bug: ACKing the wrong number. ack is the NEXT byte you expect, i.e. RCV.NXT AFTER you advanced it, not the seq of the segment you just got."
  - "Common bug: deadlock between the read-loop goroutine (producer) and Conn.Read (consumer). Keep the lock discipline simple: lock, mutate buffer + RCV.NXT, signal, unlock; Read waits on the same cond."
---

# Lesson 09 — Receiving data + ACKing

Your connection is ESTABLISHED. Now make it carry data: receive application bytes from the peer, buffer them, ACK them, and expose them through `Conn.Read` (an `io.Reader`). You'll prove it with a partial echo server that prints what it receives.

## Background

### Receiving in-order data (RFC 793 §3.7)

When a data segment arrives in ESTABLISHED:

1. **Sequence check**: is `seg.seq == RCV.NXT`? 
   - **Yes** → it's the next expected byte(s). Accept it.
   - **No** → out of order (future) or a retransmit (past). For this lesson, **drop the payload** and send a duplicate ACK (ack = current RCV.NXT). We are NOT implementing the reassembly queue — in-order delivery only. (Real TCP buffers out-of-order segments; we keep it simple.)
2. **Accept the data**: append `seg.payload` to the receive buffer, advance `RCV.NXT += len(payload)`.
3. **Send an ACK**: a segment with no payload, flags=ACK, `ack = RCV.NXT` (the new value), `seq = SND.NXT`.

ACKing every segment is fine — we're not implementing delayed ACKs.

### The receive buffer

A simple bounded byte buffer:
- The read-loop goroutine **appends** received bytes.
- `Conn.Read` **consumes** bytes (FIFO).
- When empty, `Conn.Read` **blocks** until data arrives or the connection closes (returns `io.EOF` after FIN — that's L13; for now, block).

This belongs in `internal/tcb/recvbuf.go` as a pure data structure — no I/O, just bytes and synchronization primitives... but wait: synchronization is fine (`sync` is pure, not I/O). The `tcb-no-io-imports` lint only forbids `os`/`net`/`syscall`/`x/sys`. `sync` is allowed.

Design:
```
package tcb

// RecvBuffer is an in-order byte buffer fed by the network and drained by Read.
type RecvBuffer struct {
    // bytes + a sync.Cond or a chan to wake readers
}

func (r *RecvBuffer) Write(p []byte)        // called by the stack (append)
func (r *RecvBuffer) Read(p []byte) (int, error) // called by the app (blocks if empty)
func (r *RecvBuffer) CloseWrite()           // mark EOF (used in L13)
```

(Naming `Write` for "network appends" and `Read` for "app consumes" mirrors a pipe. If that confuses you, name them `Push`/`Read`.)

### `Conn.Read`

```
// Read implements io.Reader. It returns received application bytes,
// blocking until at least one byte is available. After the peer's FIN has
// been processed and the buffer drained, it returns io.EOF (full FIN
// handling is Lesson 13).
func (c *Conn) Read(p []byte) (int, error)
```

It just delegates to the connection's `RecvBuffer`.

## What to implement

### `internal/tcb/recvbuf.go`

The `RecvBuffer` described above. Pure package (sync allowed; no os/net/syscall).

Add tests in `internal/tcb/recvbuf_test.go`:
- Write then Read returns the bytes in order.
- Read of a buffer smaller than available returns a partial read and leaves the rest.
- A blocked Read wakes up when Write is called from another goroutine.
- After CloseWrite + drained, Read returns `io.EOF`.

### Extend `internal/tcp/listener.go`

- Handle data segments in ESTABLISHED: sequence-check, append to RecvBuffer, advance RCV.NXT, send ACK.
- `Conn.Read` delegating to RecvBuffer.

### `cmd/tcp-echo/main.go`

A first cut of the echo server (we'll extend it in L10–L11). **Listen on `10.0.0.2:7777`** — that's your stack's address (the integration checks assume this):
1. `tcp.Listen(netip.MustParseAddrPort("10.0.0.2:7777"))`.
2. `Accept()` a connection.
3. Loop: `Read` into a buffer, print what was received (`log.Printf("got: %q", buf[:n])`).
   (Echoing it *back* requires `Conn.Write` — that's Lesson 10. For now just print.)

## How to test it yourself

```bash
go build ./...
sudo ./scripts/net-up.sh
sudo ./tcp-echo &

printf 'hello\nworld\n' | nc -w1 10.0.0.2 7777
# tcp-echo should print:  got: "hello\nworld\n"
```

Watch `make tcpdump`: you should see the PSH/ACK with the data arrive, and your ACK go back with the right ack number (initial RCV.NXT + 12 for "hello\nworld\n").

## Done when

- `RecvBuffer` passes its unit tests (including the blocking-Read wakeup and EOF cases).
- `Conn.Read` returns received bytes in order.
- `cmd/tcp-echo` prints data sent by `nc`.
- The integration check `scripts/check-L09.sh` sends a known string from the kernel and confirms the echo server logged it (proving the in-order data path + Conn.Read work).
- `tcb` package still passes the no-io-imports lint.

Run `/review`.
