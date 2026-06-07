package ipv4

import (
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path"
	"strings"
	"testing"
)

func TestRoundTrip(t *testing.T) {
	raw := []byte{
		0x45,       // Version=4, IHL=5
		0x00,       // ToS
		0x00, 0x14, // Total Length = 20
		0x1c, 0x46, // Identification
		0x40, 0x00, // Flags=DF, Frag offset=0
		0x40,       // TTL = 64
		0x06,       // Protocol = 6 (TCP)
		0x9c, 0x85, // Header checksum
		0xc0, 0xa8, 0x00, 0x01, // Source = 192.168.0.1
		0xc0, 0xa8, 0x00, 0xc7, // Dest   = 192.168.0.199
	}
	h, _, err := Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]byte, 20)
	_, err = h.Marshal(out)
	if err != nil {
		t.Fatal(err)
	}
	var errs []error
	for i := range raw {
		if raw[i] != out[i] {
			errs = append(errs, fmt.Errorf("%x does not match %x: index=%d\n", out[i], raw[i], i))
		}
	}
	if len(errs) > 0 {
		t.Fatal(errors.Join(errs...))
	}
}

func TestHeaderParseBasic(t *testing.T) {
	raw, err := os.ReadFile(path.Join("..", "..", "testdata", "ipv4-basic.hex"))
	if err != nil {
		t.Fatal(err)
	}
	stripped := strings.Join(strings.Fields(string(raw)), "")
	decoded, err := hex.DecodeString(stripped)
	if err != nil {
		t.Fatal(err)
	}
	h, decoded, err := Parse(decoded)
	if err != nil {
		t.Fatal(err)
	}
	h.Print()
	p, err := h.Protocol()
	if p != "TCP" || err != nil {
		t.Fatal("Wrong protocol != TCP")
	}
	if h.ttl != 64 {
		t.Fatal("Wrong TTL != 64")
	}
}

func TestHeaderParseEcho(t *testing.T) {
	raw, err := os.ReadFile(path.Join("..", "..", "testdata", "icmp-echo.hex"))
	if err != nil {
		t.Fatal(err)
	}
	stripped := strings.Join(strings.Fields(string(raw)), "")
	decoded, err := hex.DecodeString(stripped)
	if err != nil {
		t.Fatal(err)
	}
	h, decoded, err := Parse(decoded)
	if err != nil {
		t.Fatal(err)
	}
	h.Print()
	p, err := h.Protocol()
	if p != "TCP" || err != nil {
		t.Fatal("Wrong protocol != TCP")
	}
	if h.ttl != 64 {
		t.Fatal("Wrong TTL != 64")
	}
}

func TestHeaderParseErrTooShort(t *testing.T) {
	_, _, err := Parse(nil)
	if err == nil {
		t.Fatal(err)
	}
	if !errors.Is(err, ErrTooShort) {
		t.Fatal(err)
	}
}

func TestHeaderParseErrTooShortBuffer(t *testing.T) {
	_, _, err := Parse(make([]byte, 19))
	if err == nil {
		t.Fatal(err)
	}
	if !errors.Is(err, ErrTooShort) {
		t.Fatal(err)
	}
}
