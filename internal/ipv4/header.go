package ipv4

import (
	"encoding/binary"
	"errors"
	"fmt"
	"net/netip"
)

type Header struct {
	Version        uint8
	IHL            uint8
	TOS            *TypeOfService
	TotalLength    uint16
	Identification uint16
	Flags          uint8
	FragOffset     uint16
	TTL            uint8
	Protocol       string
	Checksum       uint16
	SourceAddr     netip.Addr
	DestAddr       netip.Addr
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
	if int(h.IHL*4) > len(raw) {
		return h, nil, ErrInvalidIHL
	}
	h.TOS = (&TypeOfService{raw: raw[1]}).Process()
	h.TotalLength = binary.BigEndian.Uint16(raw[2:4])
	h.Identification = binary.BigEndian.Uint16(raw[4:6])
	flagsFragment := binary.BigEndian.Uint16(raw[6:8])
	h.Flags = uint8(flagsFragment >> 13)  // top 3 bits
	h.FragOffset = flagsFragment & 0x1FFF // bottom 13 bits
	h.TTL = raw[8]
	proto, ok := protocols[raw[9]]
	if !ok {
		return h, nil, ErrUnidentifiedProtocol
	}
	h.Protocol = proto
	h.Checksum = binary.BigEndian.Uint16(raw[10:12])
	h.SourceAddr = netip.AddrFrom4([4]byte{raw[12], raw[13], raw[14], raw[15]})
	h.DestAddr = netip.AddrFrom4([4]byte{raw[16], raw[17], raw[18], raw[19]})
	return h, raw[:20], nil
}

func (h Header) Print() {
	fmt.Printf("Version: %d\n", h.Version)
	fmt.Printf("IHL: %d\n", h.IHL)
	h.TOS.Print()
	fmt.Printf("TotalLength: %d\n", h.TotalLength)
	fmt.Printf("Identification: 0x%04x\n", h.Identification)
	fmt.Printf("Flags: 0x%x\n", h.Flags)
	fmt.Printf("FragOffset: %d\n", h.FragOffset)
	fmt.Printf("TTL: %d\n", h.TTL)
	fmt.Printf("Protocol: %s\n", h.Protocol)
	fmt.Printf("Checksum: 0x%04x\n", h.Checksum)
	fmt.Printf("SourceAddr: %s\n", h.SourceAddr)
	fmt.Printf("DestAddr: %s\n", h.DestAddr)
}
