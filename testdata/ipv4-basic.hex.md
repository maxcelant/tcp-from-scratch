# ipv4-basic.hex

A minimal IPv4 packet: a 20-byte header (no options) followed by a 4-byte payload. Use it to test `ipv4.Parse` field extraction and `checksum.Verify` over the header.

```
45 00 00 18 1c 46 40 00 40 06 0a 98 0a 00 00 02
0a 00 00 01 de ad be ef
```

## Header (bytes 0–19)

| Bytes | Hex | Field | Value |
|-------|-----|-------|-------|
| 0 | `45` | Version / IHL | Version=4, IHL=5 (20-byte header) |
| 1 | `00` | TOS | 0 |
| 2–3 | `00 18` | Total Length | 24 |
| 4–5 | `1c 46` | Identification | 0x1c46 |
| 6–7 | `40 00` | Flags / Frag Offset | DF set (0x4000), offset 0 |
| 8 | `40` | TTL | 64 |
| 9 | `06` | Protocol | 6 (TCP) |
| 10–11 | `0a 98` | Header Checksum | 0x0a98 (valid) |
| 12–15 | `0a 00 00 02` | Source Address | 10.0.0.2 |
| 16–19 | `0a 00 00 01` | Destination Address | 10.0.0.1 |

## Payload (bytes 20–23)

| Bytes | Hex | Meaning |
|-------|-----|---------|
| 20–23 | `de ad be ef` | Opaque 4-byte payload |

## Assertions for your test

- `HeaderLen() == 20`, `PayloadLen() == 4`, `TotalLength == 24`
- `Protocol == 6`, `TTL == 64`
- Source `10.0.0.2`, Destination `10.0.0.1`
- Returned payload slice equals `de ad be ef`
- `checksum.Verify(pkt[:20]) == true`
