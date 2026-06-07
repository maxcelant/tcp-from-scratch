---
id: "03"
title: The Internet checksum (RFC 1071)
requires:
  files:
    - internal/checksum/checksum.go
    - internal/checksum/checksum_test.go
  symbols:
    - { pkg: ./internal/checksum, name: Sum }
    - { pkg: ./internal/checksum, name: Verify }
  tests:
    - ./internal/checksum/...
hints:
  - "The Internet checksum is the **one's complement** of the **one's complement sum** of 16-bit words. Two complements — easy to skip the outer one and ship a bug."
  - "RFC 1071 §1 has the canonical 6-line C implementation. Translate it. The key trick is `(sum & 0xffff) + (sum >> 16)` to fold the carry, repeated until no carry remains."
  - "When the buffer length is odd, the last byte is treated as the high byte of a 16-bit word, with the low byte zero. Don't forget this — it's a common source of off-by-one bugs."
  - "The checksum is endianness-agnostic by design (RFC 1071 §2.(B)). You can sum the bytes as native-endian uint16s on a little-endian machine and still get the right answer. But: byteswap the final value if you used native-endian, since the result is what goes on the wire."
  - "Common bug: writing `Verify(b)` that calls `Sum(b)` and checks for zero. That works ONLY if the checksum field is left as-is in the buffer. If you zero it before re-summing (the way RFC says to compute), you compare against the on-wire value. Pick one approach and document it."
---

# Lesson 03 — The Internet checksum (RFC 1071)

You'll write the one-function package that everyone else depends on: the Internet checksum. It's used by IPv4, ICMP, UDP, and TCP. It's also surprisingly easy to get wrong — and a wrong checksum means every packet you send is silently dropped by the kernel.

## Background

### What the Internet checksum is

From [RFC 1071](https://www.rfc-editor.org/rfc/rfc1071):

> Adjacent octets to be checksummed are paired to form 16-bit integers, and the **1's complement sum** of these 16-bit integers is formed. The checksum is the **1's complement of the 1's complement sum**.

In plain English:
1. Take your data as a sequence of 16-bit big-endian words. If the byte count is odd, treat the last byte as the high half of a 16-bit word (the low half is 0).
2. Add them all up. When the sum overflows 16 bits (carry bit set), wrap the carry back around and add it to the low 16 bits ("end-around carry").
3. Take the **bitwise NOT** of the result.

That's it.

### The reference implementation

[RFC 1071 §4.1](https://www.rfc-editor.org/rfc/rfc1071#section-4) gives this canonical C:

```c
{
    /* Compute Internet Checksum for "count" bytes
     * beginning at location "addr".
     */
    register long sum = 0;

    while( count > 1 )  {
        sum += *(unsigned short *) addr++;
        count -= 2;
    }

    if( count > 0 )
        sum += * (unsigned char *) addr;

    while (sum>>16)
        sum = (sum & 0xffff) + (sum >> 16);

    checksum = ~sum;
}
```

Notice: it sums words as **native-endian** `unsigned short` and yet produces a correct (network-endian) checksum. That's RFC 1071's §2.(B) "byte-order independence" property — you only have to be consistent. The output is the same bits regardless of host endianness, because the addition is commutative over a permutation that swaps bytes in matched pairs.

In Go, this is roughly:

```
sum := uint32(0)
for i := 0; i+1 < len(b); i += 2 {
    sum += uint32(binary.BigEndian.Uint16(b[i:i+2]))
}
if len(b)%2 == 1 {
    sum += uint32(b[len(b)-1]) << 8
}
for sum>>16 != 0 {
    sum = (sum & 0xffff) + (sum >> 16)
}
return ^uint16(sum)
```

That snippet is fine to translate verbatim into your `Sum` function — there's no creativity to be had here; RFC 1071 has been mature since 1988.

### How verification works on the wire

The trick that lets receivers verify cheaply: if you include the **on-wire** checksum field in the data you're summing, the sum becomes zero (the field is the complement of everything else). So `Verify(b)` can just call `Sum(b)` and check for `0xffff` or `0` depending on inclusion conventions.

Pick one convention and stick to it:

- **Convention A**: `Sum` computes over a buffer where the checksum field has been zeroed (typical). `Verify` calls `Sum(b)` over the full buffer (with the checksum field as-is) and returns true if the result is `0`.
- **Convention B**: `Sum` always computes over the full buffer. `Verify` requires the caller to zero the checksum field first, recompute, and compare to the saved on-wire value.

Convention A is simpler for callers. Recommend.

## What to implement

### `internal/checksum/checksum.go`

```
// Package checksum implements the Internet checksum from RFC 1071.
package checksum

// Sum computes the Internet checksum (one's-complement sum, complemented)
// over b. The returned value is the 16-bit checksum in host byte order;
// it's bit-identical to what should appear on the wire.
//
// Callers that want to *compute* a checksum to place into a packet should
// pass a buffer with the checksum field set to zero.
//
// Callers that want to *verify* an on-wire checksum can use Verify.
func Sum(b []byte) uint16

// Verify returns true if Sum(b) is zero — i.e., the on-wire checksum
// field already covers b. (The packet's existing checksum bytes are
// part of b.)
func Verify(b []byte) bool
```

That's the entire API. No more.

### `internal/checksum/checksum_test.go`

Table-driven tests covering:

1. **Empty buffer**: `Sum(nil)` should be `0xffff` (the one's-complement of zero).
2. **Single byte (odd-length edge case)**: e.g. `Sum([]byte{0xff})` — work out by hand and assert.
3. **RFC 1071 example**: The RFC §3 gives `0001 f203 f4f5 f6f7` → checksum `0x220d`. Use this exact case.
4. **Real captured IPv4 header**: read `testdata/ipv4-basic.hex`, slice out the header, call `Verify(header)` — expect true. Then flip a bit and expect false.
5. **Real captured ICMP**: read `testdata/icmp-echo.hex`, slice out the ICMP portion, verify it.

## How to test it yourself

```bash
go test ./internal/checksum/... -v
```

Quick sanity check from the dev shell:

```bash
# After Lesson 02 was already done, you can compose:
# parse an IPv4 header from a fixture, recompute its checksum, and assert match.
```

## Done when

- All five test cases above pass.
- `Sum` handles both even and odd buffer lengths.
- Empty input is well-defined.
- No imports outside of `encoding/binary`.

Run `/review`.
