# syn.hex

A full IPv4 + TCP **SYN** segment — the first packet of a 3-way handshake, from the client (`10.0.0.1:49152`) to your listener (`10.0.0.2:7777`). 20-byte IPv4 header + 24-byte TCP header (20 base + 4 bytes of MSS option).

```
45 00 00 2c ab cd 40 00 40 06 7a fc 0a 00 00 01
0a 00 00 02 c0 00 1e 61 11 22 33 44 00 00 00 00
60 02 fa f0 66 6b 00 00 02 04 05 b4
```

## IPv4 header (bytes 0–19)

| Bytes | Hex | Field | Value |
|-------|-----|-------|-------|
| 2–3 | `00 2c` | Total Length | 44 |
| 4–5 | `ab cd` | Identification | 0xabcd |
| 9 | `06` | Protocol | 6 (TCP) |
| 10–11 | `7a fc` | Header Checksum | 0x7afc (valid) |
| 12–15 | `0a 00 00 01` | Source | 10.0.0.1 |
| 16–19 | `0a 00 00 02` | Destination | 10.0.0.2 |

## TCP header (bytes 20–43)

| Bytes | Hex | Field | Value |
|-------|-----|-------|-------|
| 20–21 | `c0 00` | Source Port | 49152 |
| 22–23 | `1e 61` | Dest Port | 7777 |
| 24–27 | `11 22 33 44` | Sequence Number | 0x11223344 |
| 28–31 | `00 00 00 00` | Ack Number | 0 (no ACK) |
| 32 | `60` | Data Offset / reserved | DataOffset=6 (24-byte header) |
| 33 | `02` | Flags | SYN |
| 34–35 | `fa f0` | Window | 64240 |
| 36–37 | `66 6b` | Checksum | 0x666b (valid, pseudo-header + segment) |
| 38–39 | `00 00` | Urgent Pointer | 0 |
| 40–43 | `02 04 05 b4` | Option: MSS | kind=2, len=4, value=1460 |

## Assertions for your test

- Ports: src 49152, dst 7777
- `SeqNum == 0x11223344`, `AckNum == 0`
- `Flags & FlagSYN != 0`; `FlagACK` clear
- `DataOffset == 6`, `MSS == 1460`
- TCP checksum verifies: build the 12-byte pseudo-header from src=10.0.0.1, dst=10.0.0.2, proto=6, tcp-length=24, then `checksum.Verify(pseudo || tcpSegment)` is true.
