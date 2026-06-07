package ipv4

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net/netip"

	"github.com/maxcelant/tcp-from-scratch/internal/checksum"
)

type Header struct {
	SourceAddr netip.Addr
	DestAddr   netip.Addr
	Version    uint8
	Protocol   uint8
	Checksum   uint16

	ihl            uint8
	typeOfService  uint8
	totalLength    uint16
	identification uint16
	flags          uint8
	fragOffset     uint16
	ttl            uint8
	headerLength   int
}

const HeaderMinLength = 20

type InternetProtocol string

const (
	ProtoICMP InternetProtocol = "ICMP"
	ProtoTCP  InternetProtocol = "TCP"
	ProtoUDP  InternetProtocol = "UDP"
)

var protocols = map[uint8]InternetProtocol{1: ProtoICMP, 6: ProtoTCP, 17: ProtoUDP}

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
	h.ihl = raw[0] & 0x0F
	h.headerLength = int(h.ihl * 4)
	if h.headerLength > len(raw) {
		return h, nil, ErrInvalidIHL
	}
	h.typeOfService = raw[1]
	h.totalLength = binary.BigEndian.Uint16(raw[2:4])
	if int(h.totalLength) > len(raw) || int(h.totalLength) < h.headerLength {
		return h, nil, ErrTooShort
	}
	h.identification = binary.BigEndian.Uint16(raw[4:6])
	flagsFragment := binary.BigEndian.Uint16(raw[6:8])
	h.flags = uint8(flagsFragment >> 13)  // top 3 bits
	h.fragOffset = flagsFragment & 0x1FFF // bottom 13 bits
	h.ttl = raw[8]
	_, ok := protocols[raw[9]]
	if !ok {
		return h, nil, ErrUnidentifiedProtocol
	}
	h.Protocol = raw[9]
	h.Checksum = binary.BigEndian.Uint16(raw[10:12])
	h.SourceAddr = netip.AddrFrom4([4]byte{raw[12], raw[13], raw[14], raw[15]})
	h.DestAddr = netip.AddrFrom4([4]byte{raw[16], raw[17], raw[18], raw[19]})
	return h, raw[h.ihl*4 : h.totalLength], nil
}

func (h *Header) Marshal(dst []byte) (int, error) {
	if len(dst) < HeaderMinLength {
		return 0, ErrTooShort
	}
	dst[0] = byte((h.Version << 4) + h.ihl)
	dst[1] = h.typeOfService
	dst[2] = byte(h.totalLength >> 8)
	dst[3] = byte(h.totalLength & 0xFF)
	dst[4] = byte(h.identification >> 8)
	dst[5] = byte(h.identification & 0xFF)
	dst[6] = byte(h.fragOffset>>8) + (h.flags << 5)
	dst[7] = byte(h.fragOffset) // truncating the 16 bit into 8 bit removes left top half
	dst[8] = h.ttl
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

func (h Header) IsProtocol(proto InternetProtocol) bool {
	p, ok := protocols[h.Protocol]
	if !ok {
		return false
	}
	return p == proto
}

func (h Header) Print() {
	fmt.Printf("Version: %d\n", h.Version)
	fmt.Printf("IHL: %d\n", h.ihl)
	fmt.Printf("TOS %d\n", h.typeOfService)
	fmt.Printf("TotalLength: %d\n", h.totalLength)
	fmt.Printf("Identification: 0x%04x\n", h.identification)
	fmt.Printf("Flags: 0x%x\n", h.flags)
	fmt.Printf("FragOffset: %d\n", h.fragOffset)
	fmt.Printf("TTL: %d\n", h.ttl)
	fmt.Printf("Protocol: %s\n", protocols[h.Protocol])
	fmt.Printf("Checksum: 0x%04x\n", h.Checksum)
	fmt.Printf("SourceAddr: %s\n", h.SourceAddr)
	fmt.Printf("DestAddr: %s\n", h.DestAddr)
}
