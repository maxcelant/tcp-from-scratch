---
id: "02"
title: Parsing IPv4 headers
requires:
  files:
    - internal/ipv4/header.go
    - internal/ipv4/header_test.go
  symbols:
    - { pkg: ./internal/ipv4, name: Header }
    - { pkg: ./internal/ipv4, name: Parse }
  tests:
    - ./internal/ipv4/...
hints:
  - "Start with the wire layout (RFC 791 §3.1). The first byte holds two nibbles: version (high) and IHL (low). Mask + shift to extract them."
  - "Total Length and the other 16-bit fields are big-endian (network byte order). `encoding/binary.BigEndian.Uint16(b[i:i+2])` is your friend."
  - "Don't try to parse options yet — skip them. Just trust IHL: header is `IHL * 4` bytes, payload starts there. We'll come back to options if we ever need them (we won't)."
  - "Common bug: not validating `len(b) >= 20`. The minimum IPv4 header is 20 bytes; anything less is malformed. Return a sentinel error."
  - "Common bug: forgetting that IHL is in 32-bit words, not bytes. IHL=5 means 20-byte header."
---

# Lesson 02 — Parsing IPv4 headers

You'll write a parser that decodes the IPv4 header from a byte slice into a Go struct. No I/O — pure bytes-in, struct-out.

## Background

### The IPv4 header (RFC 791 §3.1)

```
 0                   1                   2                   3
 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|Version|  IHL  |Type of Service|          Total Length         |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|         Identification        |Flags|      Fragment Offset    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|  Time to Live |    Protocol   |         Header Checksum       |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                       Source Address                          |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Destination Address                        |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
|                    Options                    |    Padding    |
+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

Field by field, all multi-byte fields are **big-endian**:

| Field        | Size       | Notes |
|--------------|------------|-------|
| Version      | 4 bits     | Must be 4 |
| IHL          | 4 bits     | Header length in **32-bit words**. Min 5 (= 20 bytes). |
| TOS          | 1 byte     | DSCP/ECN. Ignore for now; carry through. |
| Total Length | 2 bytes    | Whole packet (header + payload) in bytes. |
| Identification | 2 bytes  | Used for fragmentation. Just carry through. |
| Flags + Frag Offset | 2 bytes | 3 flag bits + 13-bit offset. We assume no fragmentation. |
| TTL          | 1 byte     | Hop count. |
| Protocol     | 1 byte     | 6 = TCP, 17 = UDP, 1 = ICMP. |
| Checksum     | 2 bytes    | One's-complement over the **header only**. Verify it. |
| Source IP    | 4 bytes    | |
| Destination IP | 4 bytes  | |
| Options      | (IHL-5)*4 bytes | Skip; just compute the payload offset. |

### Why parse before we can checksum-verify?

A real implementation parses, then verifies the checksum, then trusts the parsed values. For now, **parse all fields including the checksum byte-for-byte**, and add a `Verify()` method or function that recomputes and compares. We'll wire up the actual checksum function in Lesson 03; for this lesson, store the on-wire checksum in the struct but **don't validate it yet** (we have no checksum implementation).

### Go's `net/netip` package

Use `net/netip.Addr` (not the older `net.IP`) for the source and destination. It's value-typed, comparable, and avoids the allocation patterns of `net.IP`. `netip.AddrFrom4([4]byte{...})` is the constructor.

## What to implement

### `internal/ipv4/header.go`

```
package ipv4

// Header is a parsed IPv4 header. All multi-byte fields are stored in host byte order.
type Header struct {
    // your fields — match the wire layout above, plus a Checksum field
    // that holds the on-wire value (do not validate yet).
}

// HeaderMinLen is the minimum IPv4 header size in bytes.
const HeaderMinLen = 20

// Protocol numbers commonly seen on the wire.
const (
    ProtoICMP = 1
    ProtoTCP  = 6
    ProtoUDP  = 17
)

// Parse decodes an IPv4 header at the start of b and returns the header plus
// the slice of b after the header (the payload). It returns an error if b is
// too short, the version isn't 4, or IHL points past len(b).
func Parse(b []byte) (Header, []byte, error)
```

You may also add:
- `func (h Header) PayloadLen() int` — convenience: `TotalLength - HeaderLen()`.
- `func (h Header) HeaderLen() int` — `IHL * 4`.

Use sentinel errors:
```
var (
    ErrTooShort       = errors.New("ipv4: buffer too short")
    ErrBadVersion     = errors.New("ipv4: not IPv4")
    ErrInvalidIHL     = errors.New("ipv4: IHL extends past buffer")
)
```

### `internal/ipv4/header_test.go`

Table-driven tests using the golden fixtures shipped in `testdata/`:

- `testdata/ipv4-basic.hex` — a known-good IPv4 packet (header + payload). The accompanying `.md` file documents every field's expected value.
- `testdata/icmp-echo.hex` — an ICMP echo request packet for variety.

Read the hex with `os.ReadFile` + `hex.DecodeString` (strip whitespace and newlines first). Assert each field matches the documented values, payload length is correct, and the returned payload byte slice starts where IHL says it does.

Also add at least these failure cases:
- `Parse(nil)` returns `ErrTooShort`.
- `Parse(make([]byte, 19))` returns `ErrTooShort`.
- A buffer with version=6 returns `ErrBadVersion`.
- A buffer with `IHL=15` but only 20 bytes long returns `ErrInvalidIHL`.

## How to test it yourself

```bash
go test ./internal/ipv4/... -v
```

You should see every table case and failure case pass.

## Done when

- `Parse` decodes both shipped fixtures correctly.
- All four failure cases return the right sentinel errors.
- `go vet ./internal/ipv4/...` is clean.
- The package imports nothing from `os`/`net`/`syscall` — it's a pure bytes package. (`net/netip` is fine; that's pure.)

Run `/review`.
