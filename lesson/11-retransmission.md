---
id: "11"
title: Retransmission (RTO)
requires:
  files:
    - internal/tcb/retransmit.go
    - internal/tcb/retransmit_test.go
  symbols:
    - { pkg: ./internal/tcb, name: Clock }
  tests:
    - ./internal/tcb/...
  lints:
    - tcb-no-io-imports
  integration: scripts/check-L11.sh
hints:
  - "When you send a segment carrying data (or a SYN/FIN), record it in a retransmit queue: (seq, payload, deadline). When an ACK advances SND.UNA past a segment's last byte, remove it. If a segment's deadline passes before it's ACKed, resend it. RFC 793 §3.7, RFC 6298 for RTO."
  - "Start with a fixed RTO (e.g. 1 second) before attempting Jacobson/Karels estimation. Get retransmission working, THEN improve the timer. RFC 6298 §2 gives the estimator if you want it: SRTT, RTTVAR, RTO = SRTT + 4*RTTVAR."
  - "To make timing testable without sleeping in tests, inject a Clock interface (Now() time.Time, and a way to schedule/fire timers — or just Now() plus a manual 'tick' the test drives). This is the one place premature abstraction pays off: deterministic time."
  - "Common bug: retransmitting a segment but advancing SND.NXT again. Retransmission reuses the SAME seq; don't bump SND.NXT on a resend."
  - "Common bug: never cancelling timers, so you resend data the peer already ACKed. Make sure Acked() prunes the retransmit queue."
---

# Lesson 11 — Retransmission (RTO)

Networks drop packets. Until now your stack assumed perfect delivery — if a segment is lost, it's lost forever and the connection stalls. Now you'll add **retransmission**: track unacknowledged segments, and resend them if they aren't ACKed within a timeout.

This is the feature that makes TCP *reliable*. (Note: this is NOT congestion control — we're not adjusting send rate based on loss. We just resend lost segments.)

## Background

### The retransmission timer (RFC 793 §3.7, RFC 6298)

The rule:
1. When you send a segment that consumes sequence space (data, SYN, or FIN), start a **retransmission timer** for it with some timeout (the **RTO**, retransmission timeout).
2. If the segment is ACKed (SND.UNA advances past its last byte) before the timer fires, cancel the timer.
3. If the timer fires first, **resend the segment** (same seq, same bytes) and restart the timer (typically with a doubled RTO — "exponential backoff").

### Picking the RTO

Start dead simple: **fixed RTO = 1 second**. Get the mechanism working. Then, if you want (optional, not required by `/review`), implement the RFC 6298 estimator:

```
On first RTT measurement R:
    SRTT   = R
    RTTVAR = R/2
    RTO    = SRTT + max(G, 4*RTTVAR)        // G = clock granularity

On subsequent measurements R':
    RTTVAR = (1-β)*RTTVAR + β*|SRTT - R'|   // β = 1/4
    SRTT   = (1-α)*SRTT   + α*R'            // α = 1/8
    RTO    = SRTT + max(G, 4*RTTVAR)

Clamp RTO to [1s, 60s].
```

You measure R by timestamping when a segment is sent and when its ACK arrives. (Skip measurement on retransmitted segments — Karn's algorithm.)

### Making time testable: the Clock interface

Retransmission is time-dependent, which makes it painful to test if you call `time.Now()` and `time.Sleep` directly. Inject a clock:

```
package tcb

// Clock abstracts time so retransmission logic is testable.
type Clock interface {
    Now() time.Time
}
```

In production you pass a real clock (`time.Now()`). In tests you pass a fake clock you advance manually, so you can assert "after 1s with no ACK, the segment is queued for resend" without any real sleeping.

This is the one place in the project where introducing an interface up front is justified — deterministic time is worth it. (Contrast with earlier lessons where we avoided premature interfaces.)

### The retransmit queue

```
package tcb

type rtxEntry struct {
    seq      uint32
    payload  []byte
    flags    uint8     // so SYN/FIN can be retransmitted too
    deadline time.Time
    sentAt   time.Time // for RTT measurement
}

type RetransmitQueue struct {
    clock Clock
    rto   time.Duration
    // ordered entries (slice or min-heap by deadline)
}

func (q *RetransmitQueue) Track(seq uint32, flags uint8, payload []byte)
func (q *RetransmitQueue) Ack(snd_una uint32)        // prune acked entries
func (q *RetransmitQueue) Expired(now time.Time) []rtxEntry  // due for resend
```

The `tcp` package runs a goroutine (a `time.Ticker` every ~200ms, say) that calls `Expired(clock.Now())` and resends each returned entry through the existing send path.

`tcb` stays pure: it imports `time` and `sync` (both allowed — not I/O) but never `os`/`net`/`syscall`. The actual resend (writing to the device) happens in `tcp`.

## What to implement

### `internal/tcb/retransmit.go`

- The `Clock` interface.
- A real clock implementation (`type realClock struct{}; func (realClock) Now() time.Time { return time.Now() }`) — or put the real one in the `tcp` package; your call, but the *interface* lives in `tcb`.
- `RetransmitQueue` with `Track`, `Ack`, `Expired`.
- Optional: RFC 6298 RTO estimation.

### `internal/tcb/retransmit_test.go`

Using a fake clock:
- Track a segment, advance the fake clock past RTO without ACK → `Expired` returns it.
- Track a segment, `Ack` it, advance clock → `Expired` returns nothing.
- Exponential backoff: after a resend, the new deadline is further out.
- Sequence wraparound in `Ack` works.

### Wire it into `internal/tcp`

- After `sendData` sends a segment, call `q.Track(...)`.
- After advancing SND.UNA on ACK, call `q.Ack(SND.UNA)`.
- A goroutine periodically resends `q.Expired(now)` segments (reusing the seq, NOT advancing SND.NXT).

## How to test it yourself

The integration check deliberately drops packets with `iptables`:

```bash
go build ./...
sudo ./scripts/net-up.sh
# The check installs an iptables rule that drops ~30% of the segments coming
# FROM your stack (so the kernel can't ACK them), then runs a transfer through
# tcp-echo and asserts it still completes.
sudo ./scripts/check-L11.sh
```

Manually, you can watch retransmits in `make tcpdump`: with loss induced, you'll see the same seq number sent more than once, and the transfer still completing.

## Done when

- `RetransmitQueue` passes its unit tests with a fake clock (no real sleeping in tests).
- `Clock` interface exists in `tcb` and the package stays pure.
- The integration check `scripts/check-L11.sh` completes a transfer through `tcp-echo` **with ~30% packet loss induced**, and tshark detects retransmitted segments.

Run `/review`.
