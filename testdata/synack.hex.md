# synack.hex

A full IPv4 + TCP **SYN/ACK** segment — the second packet of the handshake, the reply your listener (`10.0.0.2:7777`) sends back to the client (`10.0.0.1:49152`). Note the ack number is the client's SYN seq + 1. 20-byte IPv4 header + 24-byte TCP header (MSS option).

```
45 00 00 2c 00 00 40 00 40 06 26 ca 0a 00 00 02
0a 00 00 01 1e 61 c0 00 55 66 77 88 11 22 33 45
60 12 ff ff 94 5c 00 00 02 04 05 b4
```

## IPv4 header (bytes 0–19)

| Bytes | Hex | Field | Value |
|-------|-----|-------|-------|
| 2–3 | `00 2c` | Total Length | 44 |
| 4–5 | `00 00` | Identification | 0 |
| 9 | `06` | Protocol | 6 (TCP) |
| 10–11 | `26 ca` | Header Checksum | 0x26ca (valid) |
| 12–15 | `0a 00 00 02` | Source | 10.0.0.2 |
| 16–19 | `0a 00 00 01` | Destination | 10.0.0.1 |

## TCP header (bytes 20–43)

| Bytes | Hex | Field | Value |
|-------|-----|-------|-------|
| 20–21 | `1e 61` | Source Port | 7777 |
| 22–23 | `c0 00` | Dest Port | 49152 |
| 24–27 | `55 66 77 88` | Sequence Number | 0x55667788 (server ISS) |
| 28–31 | `11 22 33 45` | Ack Number | 0x11223345 (= client SYN seq + 1) |
| 32 | `60` | Data Offset | 6 (24-byte header) |
| 33 | `12` | Flags | SYN \| ACK |
| 34–35 | `ff ff` | Window | 65535 |
| 36–37 | `94 5c` | Checksum | 0x945c (valid) |
| 38–39 | `00 00` | Urgent Pointer | 0 |
| 40–43 | `02 04 05 b4` | Option: MSS | 1460 |

## Assertions for your test

- Ports: src 7777, dst 49152
- `SeqNum == 0x55667788`, `AckNum == 0x11223345`
- `Flags & (FlagSYN|FlagACK)` both set
- `MSS == 1460`
- The ack number demonstrates the "+1" rule: a SYN consumes one sequence number, so the SYN/ACK acks `client_seq + 1`.
- TCP checksum verifies against the pseudo-header (src=10.0.0.2, dst=10.0.0.1, proto=6, len=24).
