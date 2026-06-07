package ipv4

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net/netip"

	"github.com/maxcelant/tcp-from-scratch/internal/checksum"
)

type Header struct {
	Version        uint8
	IHL            uint8
	TOS            uint8
	TotalLength    uint16
	Identification uint16
	Flags          uint8
	FragOffset     uint16
	TTL            uint8
	Protocol       uint8
	Checksum       uint16
	SourceAddr     netip.Addr
	DestAddr       netip.Addr
	HeaderLength   int
}

const HeaderMinLength = 20

var protocols = map[uint8]string{1: "ICMP", 6: "TCP", 17: "UDP"}

var (
	ErrTooShort             = errors.New("ipv4: buffer too short")
	ErrBadVersion           = errors.New("ipv4: not IPV4")
	ErrInvalidIHL           = errors.New("ipv4: IHL extends past buffer")
	ErrUnidentifiedProtocol = errors.New("ipv4: protocol identified is unknown")
)

func Parse(raw []byte) (Header, []byte, error) {
	h := Header{}
	if len(raw) < HeaderMinLength {
		return h, nil, ErrTooShort
	}
	h.Version = raw[0] >> 4
	if h.Version != 4 {
		return h, nil, ErrBadVersion
	}
	h.IHL = raw[0] & 0x0F
	h.HeaderLength = int(h.IHL * 4)
	if h.HeaderLength > len(raw) {
		return h, nil, ErrInvalidIHL
	}
	h.TOS = raw[1]
	h.TotalLength = binary.BigEndian.Uint16(raw[2:4])
	if int(h.TotalLength) > len(raw) || int(h.TotalLength) < h.HeaderLength {
		return h, nil, ErrTooShort
	}
	h.Identification = binary.BigEndian.Uint16(raw[4:6])
	flagsFragment := binary.BigEndian.Uint16(raw[6:8])
	h.Flags = uint8(flagsFragment >> 13)  // top 3 bits
	h.FragOffset = flagsFragment & 0x1FFF // bottom 13 bits
	h.TTL = raw[8]
	_, ok := protocols[raw[9]]
	if !ok {
		return h, nil, ErrUnidentifiedProtocol
	}
	h.Protocol = raw[9]
	h.Checksum = binary.BigEndian.Uint16(raw[10:12])
	h.SourceAddr = netip.AddrFrom4([4]byte{raw[12], raw[13], raw[14], raw[15]})
	h.DestAddr = netip.AddrFrom4([4]byte{raw[16], raw[17], raw[18], raw[19]})
	return h, raw[h.IHL*4 : h.TotalLength], nil
}

func (h *Header) Marshal(dst []byte) (int, error) {
	if len(dst) < HeaderMinLength {
		return 0, ErrTooShort
	}
	dst[0] = byte((h.Version << 4) + h.IHL)
	dst[1] = h.TOS
	dst[2] = byte(h.TotalLength >> 8)
	dst[3] = byte(h.TotalLength & 0xFF)
	dst[4] = byte(h.Identification >> 8)
	dst[5] = byte(h.Identification & 0xFF)
	dst[6] = byte(h.FragOffset>>8) + (h.Flags << 5)
	dst[7] = byte(h.FragOffset) // truncating the 16 bit into 8 bit removes left top half
	dst[8] = h.TTL
	dst[9] = h.Protocol
	// Compute checksum at the end
	dst[10] = 0
	dst[11] = 0
	addr4 := h.SourceAddr.As4()
	dst[12] = addr4[0]
	dst[13] = addr4[1]
	dst[14] = addr4[2]
	dst[15] = addr4[3]
	addr4 = h.DestAddr.As4()
	dst[16] = addr4[0]
	dst[17] = addr4[1]
	dst[18] = addr4[2]
	dst[19] = addr4[3]
	sum := checksum.Sum(dst)
	dst[10] = byte(sum >> 8)
	dst[11] = byte(sum & 0xFF)
	return 20, nil
}

func (h Header) Print() {
	fmt.Printf("Version: %d\n", h.Version)
	fmt.Printf("IHL: %d\n", h.IHL)
	fmt.Printf("TOS %d\n", h.TOS)
	fmt.Printf("TotalLength: %d\n", h.TotalLength)
	fmt.Printf("Identification: 0x%04x\n", h.Identification)
	fmt.Printf("Flags: 0x%x\n", h.Flags)
	fmt.Printf("FragOffset: %d\n", h.FragOffset)
	fmt.Printf("TTL: %d\n", h.TTL)
	fmt.Printf("Protocol: %s\n", protocols[h.Protocol])
	fmt.Printf("Checksum: 0x%04x\n", h.Checksum)
	fmt.Printf("SourceAddr: %s\n", h.SourceAddr)
	fmt.Printf("DestAddr: %s\n", h.DestAddr)
}
