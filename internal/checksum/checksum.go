package checksum

import (
	"encoding/binary"
)

func Sum(b []byte) uint16 {
	sum := uint32(0)
	// Sum as sequence of 16-bit big-endian words
	for i := 0; i+1 < len(b); i += 2 {
		sum += uint32(binary.BigEndian.Uint16(b[i : i+2]))
	}
	// If odd, treat last byte as high half of 16-bit word
	if len(b)%2 == 1 {
		sum += uint32(b[len(b)-1]) << 8
	}
	// Carry around the overflow bits to the bottom
	for sum>>16 != 0 {
		sum = (sum & 0xffff) + (sum >> 16)
	}
	// Take ones-compliment
	return ^uint16(sum)
}

// checksum + sum of header (without checksum) should equal 0
func Verify(b []byte) bool {
	return Sum(b) == 0
}
