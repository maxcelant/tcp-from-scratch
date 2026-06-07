# icmp-echo.hex

A full IPv4 packet carrying an ICMP echo request (a `ping`). 20-byte IPv4 header + 16-byte ICMP message. Use it for `ipv4.Parse`, `checksum.Verify` (both the IP header checksum and the ICMP checksum), and as the input your L04 `icmp-echo` responder must reply to.

```
45 00 00 24 00 01 40 00 40 01 26 d6 0a 00 00 01
0a 00 00 02 08 00 54 35 12 34 00 01 61 62 63 64
65 66 67 68
```

## IPv4 header (bytes 0–19)

| Bytes | Hex | Field | Value |
|-------|-----|-------|-------|
| 0 | `45` | Version / IHL | 4 / 5 |
| 1 | `00` | TOS | 0 |
| 2–3 | `00 24` | Total Length | 36 |
| 4–5 | `00 01` | Identification | 0x0001 |
| 6–7 | `40 00` | Flags / Frag | DF, offset 0 |
| 8 | `40` | TTL | 64 |
| 9 | `01` | Protocol | 1 (ICMP) |
| 10–11 | `26 d6` | Header Checksum | 0x26d6 (valid) |
| 12–15 | `0a 00 00 01` | Source | 10.0.0.1 |
| 16–19 | `0a 00 00 02` | Destination | 10.0.0.2 |

## ICMP message (bytes 20–35)

| Bytes | Hex | Field | Value |
|-------|-----|-------|-------|
| 20 | `08` | Type | 8 (echo request) |
| 21 | `00` | Code | 0 |
| 22–23 | `54 35` | Checksum | 0x5435 (valid, covers ICMP only) |
| 24–25 | `12 34` | Identifier | 0x1234 |
| 26–27 | `00 01` | Sequence | 1 |
| 28–35 | `61…68` | Data | ASCII `abcdefgh` |

## Assertions for your test

- IPv4: `Protocol == 1`, src `10.0.0.1`, dst `10.0.0.2`, `checksum.Verify(pkt[:20])`
- ICMP: type byte `payload[0] == 8`, `checksum.Verify(payload)` true (the ICMP checksum covers the whole ICMP message)
- An echo *reply* you build flips type to `0`, copies id/seq/data, recomputes the ICMP checksum, and swaps the IP src/dst.
