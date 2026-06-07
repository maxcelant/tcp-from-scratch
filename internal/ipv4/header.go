package ipv4

import (
	"encoding/binary"
	"fmt"
	"net/netip"
)

type Header struct {
	Version        uint8
	IHL            uint8
	TypeOfService  uint8
	TotalLength    uint16
	Identification uint16
	Flags          uint8
	FragOffset     uint16
	TTL            uint8
	Protocol       uint8
	Checksum       uint16
	SourceAddr     netip.Addr
	DestAddr       netip.Addr
	Options        string
	Padding        string
}

func Parse(raw []byte) (Header, []byte, error) {
	h := Header{}
	h.Version = raw[0] >> 4
	h.IHL = raw[0] & 0x0F
	h.TypeOfService = raw[1]
	h.TotalLength = binary.BigEndian.Uint16(raw[2:4])
	h.Identification = binary.BigEndian.Uint16(raw[4:6])
	flagsFragment := binary.BigEndian.Uint16(raw[6:8])
	h.Flags = uint8(flagsFragment >> 13)  // top 3 bits
	h.FragOffset = flagsFragment & 0x1FFF // bottom 13 bits
	h.TTL = raw[8]
	h.Protocol = raw[9]
	h.Checksum = binary.BigEndian.Uint16(raw[10:12])
	h.SourceAddr = netip.AddrFrom4([4]byte{raw[12], raw[13], raw[14], raw[15]})
	h.DestAddr = netip.AddrFrom4([4]byte{raw[16], raw[17], raw[18], raw[19]})
	return h, raw[:20], nil
}

func (h Header) Print() {
	fmt.Printf("Version: %d\n", h.Version)
	fmt.Printf("IHL: %d\n", h.IHL)
	fmt.Printf("TypeOfService: %d\n", h.TypeOfService)
	fmt.Printf("TotalLength: %d\n", h.TotalLength)
	fmt.Printf("Identification: 0x%04x\n", h.Identification)
	fmt.Printf("Flags: 0x%x\n", h.Flags)
	fmt.Printf("FragOffset: %d\n", h.FragOffset)
	fmt.Printf("TTL: %d\n", h.TTL)
	fmt.Printf("Protocol: %d\n", h.Protocol)
	fmt.Printf("Checksum: 0x%04x\n", h.Checksum)
	fmt.Printf("SourceAddr: %s\n", h.SourceAddr)
	fmt.Printf("DestAddr: %s\n", h.DestAddr)
	fmt.Printf("Options: % x\n", h.Options)
	fmt.Printf("Padding: % x\n", h.Padding)
}
