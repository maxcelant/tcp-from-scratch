package checksum

import (
	"encoding/hex"
	"os"
	"path"
	"strings"
	"testing"
)

func TestEmptyBuffer(t *testing.T) {
	output := Sum(nil)
	if output != 0xFFFF {
		t.Fatalf("output sum is incorrect: %d", output)
	}
}

func TestOddLength(t *testing.T) {
	output := Sum([]byte{0xFF})
	if output != 0xFF {
		t.Fatalf("output sum is incorrect: %d", output)
	}
}

func TestCommon(t *testing.T) {
	output := Sum([]byte{0x00, 0x01, 0xF2, 0x03, 0xF4, 0xF5, 0xF6, 0xF7})
	if output != 0x220D {
		t.Fatalf("output sum is incorrect: %d", output)
	}
}

func TestVerifyIPv4Header(t *testing.T) {
	raw, err := os.ReadFile(path.Join("..", "..", "testdata", "ipv4-basic.hex"))
	if err != nil {
		t.Fatal("failed to open testdata/ipv4-basic.hex")
	}
	stripped := strings.Join(strings.Fields(string(raw)), "")
	decoded, err := hex.DecodeString(stripped)
	if err != nil {
		t.Fatal(err)
	}
	if !Verify(decoded[:20]) {
		t.Fatal("incorrect checksum returned false")
	}
	// Flipping the bit should make verify return non-zero
	decoded[0] = 0xff
	if Verify(decoded[:20]) {
		t.Fatal("checksum returned true when it must be false")
	}
}

func TestVerifyICMP(t *testing.T) {
	raw, err := os.ReadFile(path.Join("..", "..", "testdata", "icmp-echo.hex"))
	if err != nil {
		t.Fatal("failed to open testdata/icmp-echo.hex")
	}
	stripped := strings.Join(strings.Fields(string(raw)), "")
	decoded, err := hex.DecodeString(stripped)
	if err != nil {
		t.Fatal(err)
	}
	if !Verify(decoded[:20]) {
		t.Fatal("incorrect checksum returned false")
	}
	// Flipping the bit should make verify return non-zero
	decoded[0] = 0xff
	if Verify(decoded[:20]) {
		t.Fatal("checksum returned true when it must be false")
	}
}
