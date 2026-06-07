package tun

import (
	"golang.org/x/sys/unix"

	"fmt"
	"os"
)

type Device struct {
	name string
	file *os.File
}

func Open(name string) (*Device, error) {
	f, err := os.OpenFile("/dev/net/tun", os.O_RDWR, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to open file: %w", err)
	}
	ifreq, err := unix.NewIfreq(name)
	if err != nil {
		return nil, fmt.Errorf("failed to create ifreq: %w", err)
	}
	// Sets tun mode and no packet info setting
	ifreq.SetUint16(unix.IFF_TUN | unix.IFF_NO_PI)
	if err := unix.IoctlIfreq(int(f.Fd()), unix.TUNSETIFF, ifreq); err != nil {
		f.Close()
		return nil, fmt.Errorf("TUNSETIFF ioctl failed: %w", err)
	}
	return &Device{name: name, file: f}, nil
}

func (d *Device) Read(p []byte) (int, error) {
	return d.file.Read(p)
}

func (d *Device) Write(p []byte) (int, error) {
	return d.file.Write(p)
}

func (d *Device) Close() error {
	return d.file.Close()
}

func (d *Device) Name() string {
	return d.name
}
