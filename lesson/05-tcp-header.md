---
id: "05"
title: TCP header parse/serialize
requires:
  files:
    - internal/tcp/header.go
    - internal/tcp/header_test.go
  symbols:
    - { pkg: ./internal/tcp, name: Header }
    - { pkg: ./internal/tcp, name: Parse }
    - { pkg: ./internal/tcp, name: Header.Marshal }
  tests:
    - ./internal/tcp/...
hints:
  - "TCP header is 20 bytes minimum (RFC 793 §3.1), same as IPv4. The Data Offset field (top nibble of byte 12) is the header length in 32-bit words — exactly like IPv4's IHL. Options live between byte 20 and DataOffset*4."
  - "The flags are the low 6 bits of byte 13: URG, ACK, PSH, RST, SYN, FIN from high to low. Define them as named bit constants and store a single `Flags uint8` field, or store individual bools — your choice, but bit constants are cleaner and match the wire."
  - "The checksum covers a *pseudo-header* (src IP, dst IP, zero byte, protocol=6, TCP length) PLUS the TCP header PLUS the TCP payload. RFC 793 §3.1 'Checksum'. This is the single most common place to get TCP wrong."
  - "The MSS option is kind=2, length=4, then a 2-byte value. Options are a TLV list terminated by kind=0 (End of Option List) or padded with kind=1 (No-Op). For now you only need to parse/emit MSS; skip unknown options by honoring their length byte."
  - "Common bug: computing the TCP checksum over only the TCP segment and forgetting the pseudo-header. If your SYN/ACK gets silently dropped in L07, this is why."
---

# Lesson 05 — TCP header parse/serialize

Now the main event. You'll write a TCP header parser and serializer, including the MSS option and the all-important pseudo-header checksum. This is pure bytes work like Lessons 02–04, but TCP's checksum has a twist that trips everyone up the first time.

## Background

### The TCP header (RFC 793 §3.1)

```
  0                   1                   2                   3
  0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |          Source Port          |       Destination Port        |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                        Sequence Number                        |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                    Acknowledgment Number                      |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |  Data |           |U|A|P|R|S|F|                               |
 | Offset| Reserved  |R|C|S|S|Y|I|            Window             |
 |       |           |G|K|H|T|N|N|                               |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |           Checksum            |         Urgent Pointer        |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                    Options                    |    Padding    |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
 |                             data                              |
 +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
```

| Field | Size | Notes |
|-------|------|-------|
| Source Port | 2 bytes | big-endian |
| Dest Port | 2 bytes | |
| Sequence Number | 4 bytes | byte position of first data octet in this segment |
| Ack Number | 4 bytes | next seq the sender expects (valid only if ACK set) |
| Data Offset | 4 bits | header length in 32-bit words; min 5 |
| Reserved | 6 bits | zero |
| Flags | 6 bits | URG ACK PSH RST SYN FIN |
| Window | 2 bytes | receive window size |
| Checksum | 2 bytes | pseudo-header + header + data |
| Urgent Pointer | 2 bytes | only if URG; we ignore |
| Options | variable | MSS, window scale, SACK, timestamps... we only do MSS |

### The flags

```
URG = 0x20
ACK = 0x10
PSH = 0x08
RST = 0x04
SYN = 0x02
FIN = 0x01
```

Define these as constants. Store a single `Flags uint8` on your Header — it maps cleanly to the wire and tests like `h.Flags&SYN != 0` read well.

### The pseudo-header checksum (the twist)

TCP's checksum doesn't just cover the TCP segment. It covers a **pseudo-header** built from fields in the IPv4 header, concatenated (conceptually) in front of the TCP segment:

```
 +--------+--------+--------+--------+
 |           Source Address          |   (4 bytes, from IP header)
 +--------+--------+--------+--------+
 |         Destination Address       |   (4 bytes, from IP header)
 +--------+--------+--------+--------+
 |  zero  |  PTCL  |    TCP Length   |   (1 + 1 + 2 bytes)
 +--------+--------+--------+--------+
```

- `PTCL` = 6 (TCP protocol number).
- `TCP Length` = length of the TCP header + payload (NOT including the pseudo-header, NOT including the IP header).

To compute the checksum:
1. Build the 12-byte pseudo-header.
2. Concatenate: pseudo-header + TCP header (with checksum field zeroed) + TCP payload.
3. If the total is odd, the checksum routine pads with a zero byte (your `checksum.Sum` already handles odd lengths).
4. Run `checksum.Sum` over the whole thing.
5. Write the result into the TCP checksum field.

**Why a pseudo-header?** It lets TCP detect misrouted/corrupted packets where the IP addresses got mangled. The TCP checksum effectively cross-checks the IP layer.

This means `Marshal` for TCP needs to know the source and destination IPs — they're not in the TCP header itself. Design your API to accept them.

### Sequence number arithmetic

Sequence and ack numbers are `uint32` and **wrap around** (mod 2³²). You'll do a lot of `seq + len` arithmetic in later lessons. For now just store them as `uint32`; Go's unsigned arithmetic wraps correctly by default.

## What to implement

### `internal/tcp/header.go`

```
package tcp

const (
    FlagFIN = 1 << 0
    FlagSYN = 1 << 1
    FlagRST = 1 << 2
    FlagPSH = 1 << 3
    FlagACK = 1 << 4
    FlagURG = 1 << 5
)

const HeaderMinLen = 20

// Header is a parsed TCP header. Multi-byte fields are host byte order.
type Header struct {
    SrcPort, DstPort uint16
    SeqNum, AckNum   uint32
    DataOffset       uint8  // in 32-bit words
    Flags            uint8
    Window           uint16
    Checksum         uint16 // on-wire value
    Urgent           uint16
    MSS              uint16 // 0 if no MSS option present
    // (you may store raw options too, but MSS is all we use)
}

// Parse decodes a TCP header at the start of b. Returns the header and the
// payload (bytes after the header per DataOffset). Errors on short buffers
// or a DataOffset that points past len(b).
func Parse(b []byte) (Header, []byte, error)

// Marshal writes the TCP header + the given payload into dst, computing the
// checksum using the pseudo-header derived from src and dst IPs. Returns the
// total number of bytes written (header + payload).
//
// src and dst are the IPv4 addresses that WILL be used in the enclosing IP
// header — they're needed for the pseudo-header checksum.
func (h Header) Marshal(dst []byte, srcIP, dstIP netip.Addr, payload []byte) (int, error)
```

Design notes:
- Put the MSS option emission logic inside Marshal: if `h.MSS != 0`, emit a kind=2/len=4 option and set DataOffset to 6 (24-byte header). Otherwise DataOffset=5.
- Provide a helper for the pseudo-header checksum. It can be unexported (`func pseudoHeaderChecksum(...)`), but consider exposing `func Checksum(srcIP, dstIP netip.Addr, segment []byte) uint16` so tests can call it directly.

### `internal/tcp/header_test.go`

- Round-trip a real SYN: read `testdata/syn.hex`, IPv4-parse to get the TCP segment + the src/dst IPs, `tcp.Parse` it, assert fields (ports, seq, flags=SYN, MSS option value). Document expected values come from `testdata/syn.hex.md`.
- Round-trip a real SYN/ACK: `testdata/synack.hex`. Assert flags = SYN|ACK and the ack number.
- Checksum verification: take the real SYN segment + its pseudo-header and assert `checksum.Verify` over (pseudo-header || segment) is true.
- Marshal a SYN you construct, then Parse it back, and assert your computed checksum verifies.

## How to test it yourself

```bash
go test ./internal/tcp/... -v
```

The most valuable assertion is the checksum one. If your Marshal produces a segment whose checksum doesn't verify, you will spend all of Lesson 07 confused — catch it here.

## Done when

- `Parse` correctly decodes `testdata/syn.hex` and `testdata/synack.hex` including the MSS option.
- `Marshal` produces a segment whose pseudo-header checksum verifies.
- Marshal → Parse round-trips preserve all fields.
- `go vet ./internal/tcp/...` clean.

Run `/review`.
