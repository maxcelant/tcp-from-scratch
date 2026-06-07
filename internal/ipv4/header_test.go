package ipv4

import (
	"testing"
)

func TestHeaderParse(t *testing.T) {
	raw := []byte{
		0x45,       // Version=4, IHL=5
		0x00,       // ToS
		0x00, 0x3c, // Total Length = 60
		0x1c, 0x46, // Identification
		0x40, 0x00, // Flags=DF, Frag offset=0
		0x40,       // TTL = 64
		0x06,       // Protocol = 6 (TCP)
		0xb1, 0xe6, // Header checksum
		0xc0, 0xa8, 0x00, 0x01, // Source = 192.168.0.1
		0xc0, 0xa8, 0x00, 0xc7, // Dest   = 192.168.0.199
	}
	h, _, _ := Parse(raw)
	h.Print()
}
