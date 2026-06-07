---
id: "01"
title: Opening a TUN device
requires:
  files:
    - internal/tun/tun.go
    - cmd/tcpdump-lite/main.go
  symbols:
    - { pkg: ./internal/tun, name: Device }
    - { pkg: ./internal/tun, name: Open }
  lints:
    - cmd-builds
  integration: scripts/check-L01.sh
hints:
  - "A TUN device is opened by `open(\"/dev/net/tun\", O_RDWR)` and then configured with an `ioctl(TUNSETIFF, ...)`. Both are stdlib calls in Go via the `syscall` or `golang.org/x/sys/unix` package."
  - "The ioctl request value is `TUNSETIFF` (0x400454ca). The struct you pass is `ifreq` — only the first 16 bytes (interface name) and the flags field matter for us. Flags should be `IFF_TUN | IFF_NO_PI` — IFF_TUN means L3, IFF_NO_PI means skip the 4-byte packet info prefix."
  - "RFC-free pointer here — read `Documentation/networking/tuntap.txt` in the kernel tree (or just the man page `tun(4)`). The C example there is 30 lines and shows the exact ioctl shape."
  - "Common bug: returning the file descriptor from Open without keeping `*os.File` around. Once `os.File` goes out of scope and gets GC'd, the FD is closed. Store the *os.File on your Device struct."
  - "Common bug: the interface name field is 16 bytes, null-terminated. If you copy a Go string `\"tun0\"` straight into bytes you forget the null — that's usually fine because the buffer is zeroed, but make sure your buffer is exactly 16 bytes, not the length of the name."
---

# Lesson 01 — Opening a TUN device

You'll write the lowest layer of the stack: a Go package that opens a TUN device and lets the rest of your code read/write raw L3 packets through it. Then you'll write a tiny binary that uses it to print every incoming packet as hex.

This is the **only** package that talks to the OS device. Everything else in the project will operate on byte slices.

## Background

### What `/dev/net/tun` actually is

`/dev/net/tun` is a special character device. Opening it gives you a file descriptor that is **not yet attached** to any interface. To attach it to a specific interface (and create that interface if it doesn't exist), you call `ioctl(fd, TUNSETIFF, &ifr)` where `ifr` is a `struct ifreq` populated with:

- `ifr_name` — the interface name you want, e.g. `"tun0"`. Up to 15 chars + null.
- `ifr_flags` — `IFF_TUN | IFF_NO_PI`.

`IFF_TUN` selects TUN mode (L3 packets, no Ethernet header). `IFF_NO_PI` says "don't prepend the 4-byte 'packet info' header that the kernel would otherwise add" — we don't want it; it's a vestige.

After the ioctl succeeds, the interface `tun0` exists in `ip link`, and read/write on the fd transfers raw L3 packet bytes.

### The `ifreq` struct in Go

In C, `struct ifreq` is a tagged union about 40 bytes long. We only care about two fields:

```
offset 0  : char ifr_name[16];        // interface name, null-padded
offset 16 : short ifr_flags;          // flags (for our ioctl)
... rest unused for us ...
```

In Go, the cleanest approach is `golang.org/x/sys/unix`. It exposes `Ifreq` types, `IoctlSetInt`, and constants like `unix.IFF_TUN`, `unix.IFF_NO_PI`, `unix.TUNSETIFF`. You can also do it with raw `syscall.Syscall(SYS_IOCTL, ...)` and a `[]byte` buffer — but the `unix` package is idiomatic.

### Reading and writing packets

Once attached, the file descriptor behaves like a pipe:

- `Read(buf)` — blocks until a packet is available; copies one packet's bytes into `buf`. Returns the packet length. A typical buffer size is the MTU (1500 by default).
- `Write(buf)` — sends one packet. The bytes must form a valid L3 packet (starting with the IPv4 version nibble).

One read = one full packet. You don't have to deal with TCP-style "stream chunks at this layer" — that's our job to add on top.

### Bringing the interface up

A TUN device needs an address and to be `UP` before the kernel will route packets to it. The helper `scripts/net-up.sh` creates a **persistent** `tun0`, assigns `10.0.0.1/24` (the kernel/peer side), and brings it up:

```bash
sudo ip tuntap add dev tun0 mode tun   # persistent device (survives without the fd)
sudo ip addr add 10.0.0.1/24 dev tun0
sudo ip link set tun0 up
```

Because `net-up.sh` pre-creates `tun0`, your `Open("tun0")` **attaches to the existing device** rather than creating a fresh one. The integration check runs `net-up.sh` for you.

## What to implement

### `internal/tun/tun.go`

A `Device` type that wraps an attached TUN file descriptor and satisfies `io.ReadWriteCloser`. Specifically:

- `type Device struct { ... }` — fields are yours to design (you'll need at least the `*os.File`).
- `func Open(name string) (*Device, error)` — opens `/dev/net/tun`, does the `TUNSETIFF` ioctl with the given name (e.g. `"tun0"`), returns the device. Errors should wrap the underlying syscall error with `fmt.Errorf("...: %w", err)`.
- `func (d *Device) Read(p []byte) (int, error)` — standard `io.Reader` semantics. One call returns one packet.
- `func (d *Device) Write(p []byte) (int, error)` — standard `io.Writer` semantics. One call sends one packet.
- `func (d *Device) Close() error` — closes the fd.
- `func (d *Device) Name() string` — returns the interface name you attached to (useful for logging).

**Constraint:** `Device` must satisfy `io.ReadWriteCloser`. A trivial way to enforce this is a compile-time assertion: `var _ io.ReadWriteCloser = (*Device)(nil)` at the top of the file. Do this. It's a one-liner that prevents a class of bugs.

### `cmd/tcpdump-lite/main.go`

A `main()` that:

1. Takes an interface name from os.Args (default `"tun0"`).
2. Calls `tun.Open(name)`.
3. In a loop, reads one packet at a time into a 1500-byte buffer and prints a single line per packet:
   ```
   [42] 4500 0054 a3b1 4000 4001 7f23 0a00 0001 0a00 0002 0800 ...
   ```
   The leading `[N]` is the byte length. Hex bytes follow, space-separated in groups of 2 bytes (4 hex chars).
4. Handles SIGINT by closing the device and exiting cleanly.

This binary is the userspace equivalent of `tcpdump -ni tun0 -x`. It's how you'll sanity-check that your device works in subsequent lessons.

### A note on idiomatic Go

- The TUN package is the only place that imports `os`, `syscall`, or `golang.org/x/sys/unix`. Keep it that way.
- Don't take logger or context as constructor arguments. `Open` returns a Device — that's it.
- Don't add a `Run()` method or wrap the read loop inside the package. The package is plumbing; the binary is the user.

## How to test it yourself

After you've implemented both files, from inside the dev container:

```bash
go build ./cmd/tcpdump-lite
sudo ./scripts/net-up.sh             # creates tun0 = 10.0.0.1/24
sudo ./tcpdump-lite tun0 &           # start your tool in background
ping -c 3 -W 1 10.0.0.2              # 10.0.0.2 routes to tun0 -> your program reads it
```

You should see 3 packets print as hex on stdout (the ICMP echo requests the kernel sent toward `10.0.0.2`). They'll be ignored by your binary (you're not replying yet — that's L04), so `ping` reports 100% loss. That's expected.

Stop with Ctrl-C, then:

```bash
sudo ./scripts/net-down.sh
```

In a separate terminal you can also run `sudo tcpdump -ni tun0 -x` and compare the bytes to your tool's output — they should match.

## Done when

- `internal/tun/tun.go` compiles.
- `tun.Device` satisfies `io.ReadWriteCloser` (compile-time check passes).
- `cmd/tcpdump-lite` builds and runs.
- The integration check `scripts/check-L01.sh` passes: it brings up `tun0`, runs your binary in the background, pings `10.0.0.2` 3 times, and confirms at least 3 packet-lines on stdout.

Run `/review`.
