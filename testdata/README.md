# Golden packet fixtures

These `.hex` files are **known-good, checksum-valid** packets captured/synthesized for the parsing and serialization lessons. Each has a companion `.md` documenting every field, so your tests can assert exact values.

## Format

Each `.hex` file is whitespace-formatted hex (16 bytes per line, space-separated). **Strip all whitespace before decoding** — `encoding/hex.DecodeString` does not accept spaces:

```go
raw, _ := os.ReadFile("testdata/syn.hex")
clean := strings.Join(strings.Fields(string(raw)), "") // remove all whitespace
pkt, _ := hex.DecodeString(clean)
```

## Files

| File | Bytes | Contents | Used by |
|------|-------|----------|---------|
| `ipv4-basic.hex` | 24 | IPv4 header (proto=TCP) + 4-byte payload | L02, L03, L04 |
| `icmp-echo.hex`  | 36 | IPv4 + ICMP echo request | L02, L03, L04 |
| `syn.hex`        | 44 | IPv4 + TCP SYN (MSS option) | L05 |
| `synack.hex`     | 44 | IPv4 + TCP SYN/ACK (MSS option) | L05 |

## Network convention

All fixtures use the project's addressing: `10.0.0.1` is the kernel/peer side, `10.0.0.2` is your stack. Ports: the stack listens on `7777` (`0x1e61`); the client ephemeral port is `49152` (`0xc000`).

Every checksum in these packets is correct. `checksum.Verify` over the IPv4 header should return true; `checksum.Verify` over (TCP pseudo-header || TCP segment) should return true. If your code disagrees with these fixtures, your code is wrong — the fixtures were generated and cross-checked.
