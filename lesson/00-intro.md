---
id: "00"
title: Intro & Setup
requires:
  files:
    - go.mod
hints:
  - "Lesson 00 asks for `go mod init <module-path>`. Pick a path you'll keep stable across lessons — `github.com/<your-user>/tcp-from-scratch` is fine even if you never push it."
  - "If `go mod init` complains the file exists, you're done — run /review."
  - "Open a shell with `make dev`. The container has `go`, `tcpdump`, `iproute2`, and `/dev/net/tun` ready. If `make dev` fails, Docker isn't running."
  - "Run /review to see the exact missing file."
---

# Lesson 00 — Intro & Setup

Welcome. By the end of this tutorial you will have written, line by line in Go, a working TCP stack that can perform a real 3-way handshake with a Python HTTP server, send a `GET /`, receive the response, and close the connection cleanly — using your own implementation of IPv4 + TCP, not the kernel's.

This lesson is just about getting your environment ready and understanding the shape of what's coming.

## Background

### Where TCP lives in the stack

```
  ┌──────────────────────────────┐
  │  Application (your HTTP req) │
  ├──────────────────────────────┤
  │  TCP  ← you implement this   │  ← lessons 05-14
  ├──────────────────────────────┤
  │  IPv4 ← you implement this   │  ← lessons 02-04
  ├──────────────────────────────┤
  │  Ethernet (skipped)          │
  ├──────────────────────────────┤
  │  Physical                    │
  └──────────────────────────────┘
```

A real OS handles all of this in the kernel. **Userspace programs** like `curl` talk to the kernel via the **socket API** (`socket()`, `connect()`, `send()`, `recv()`). When you call `connect()`, the kernel does the SYN/SYN-ACK/ACK handshake for you, then `send()` writes bytes that the kernel chunks into TCP segments, wraps in IP packets, and hands to the NIC driver.

We're going to do all of that ourselves, in Go, in userspace.

### How do we get raw packets out of the kernel?

We use a **TUN device**. A TUN device is a virtual network interface that looks like a real NIC to the kernel, but its "wire" is actually a file descriptor in userspace.

- The kernel routes packets to the TUN device based on its routing table (just like any other interface).
- When the kernel writes a packet to it, **you read raw bytes** from `/dev/net/tun`.
- When **you write raw bytes** to `/dev/net/tun`, the kernel sees them as if a NIC delivered them.

The bytes are L3 (network layer) — meaning **IPv4 packets with no Ethernet framing**. That's why we don't need to implement Ethernet or ARP. (TAP devices are the L2 variant — we're not using those.)

```
   ┌─────────────── Your Go process ───────────────┐
   │     (your TCP stack — address 10.0.0.2)        │
   │   read(fd) ──► [raw IPv4 packet bytes] ──► you │
   │   write(fd) ◄── [raw IPv4 packet bytes] ◄── you│
   └──────────────────────┬──────────────────────────┘
                          │  (file descriptor)
                          ▼
                ┌──────────────────────────┐
                │  Linux kernel            │
                │  tun0 interface = 10.0.0.1│  ◄── shows up in `ip link`
                │  (its OWN TCP stack is    │
                │   the "peer" you talk to) │
                └──────────────────────────┘
```

### The network model (important — read this twice)

We do **not** need a network namespace, a second host, or any forwarding. The trick is how a TUN device routes:

- The kernel writes a packet to the tun fd whenever it **routes a packet out the tun0 interface**. With `ip route` sending `10.0.0.0/24` to `tun0`, any packet destined to a `10.0.0.x` address that is *not local* gets handed to your program.
- A TUN interface's **own** address (we'll use `10.0.0.1`) is *local* — packets to it are delivered to the kernel's own stack, not to the fd.

So we split the subnet:

| Address | Who | Role |
|---------|-----|------|
| `10.0.0.1` | the kernel (tun0's interface address) | the **peer** — runs `nc`, `ping`, `python3 -m http.server` |
| `10.0.0.2` | **your** TCP stack | the address your code claims; routed to the tun fd |

This means **the Linux kernel's own TCP stack is your test peer**, for free:

- *Server lessons* — your stack listens on `10.0.0.2:PORT`; you test with `nc 10.0.0.2 PORT` (the kernel is the client).
- *Client lessons* — the kernel runs a real server on `10.0.0.1` (e.g. `python3 -m http.server --bind 10.0.0.1`); your stack dials `10.0.0.1`.

A bonus: the kernel **silently drops TCP segments with a bad checksum**. So if the kernel ever replies to your stack, your checksums were correct — a free end-to-end validator.

The helper script `scripts/net-up.sh` sets all this up (creates a persistent `tun0`, assigns `10.0.0.1/24`, brings it up). `scripts/net-down.sh` tears it down.

### Tools you'll use a lot

- `ip link`, `ip addr`, `ip route` — Linux network configuration (instead of `ifconfig`).
- `ip tuntap` / `ip addr` / `ip route` — create and configure the TUN device.
- `tcpdump -ni tun0` — watch raw packets fly past. This is your **truth oracle**: if `tcpdump` says your packet is wrong, your packet is wrong.
- `tshark` — terminal Wireshark; useful for pcap analysis.
- `nc` (netcat) — open arbitrary TCP listeners/clients for testing.

You don't need to know these tools yet — each lesson teaches the ones it needs.

### What you'll write (the package layout)

```
internal/
  tun/        opens /dev/net/tun, reads/writes raw bytes (io.ReadWriteCloser)
  checksum/   RFC 1071 one's-complement checksum
  ipv4/       parse + marshal IPv4 headers
  tcp/        parse + marshal TCP headers + dialer/listener + demux
  tcb/        pure state: TCP FSM, sequence-number bookkeeping, buffers
cmd/
  tcpdump-lite/   prints raw packets (L01)
  icmp-echo/      replies to ping (L04)
  tcp-echo/       a TCP echo server (L09–L11)
  curl-lite/      the capstone HTTP/1.0 client (L14)
```

The boundaries matter. `tcb` will not be allowed to import `os` or `net` — it's pure state. `tun` will be the only place that touches a file descriptor. This separation is what makes the code testable.

## What to implement

This lesson has only one tangible artifact: **initialize the Go module**.

1. Drop into the dev container:
   ```bash
   make dev
   ```
2. Inside the container, at `/workspace`:
   ```bash
   go mod init github.com/<your-name>/tcp-from-scratch
   ```
   (The module path doesn't matter as long as it's consistent across lessons. Pick something and stick with it.)

3. Verify `go.mod` exists at the repo root.

That's it for code. Most of this lesson is reading.

## How to test it yourself

Inside the dev container, run a quick sanity check that the network plumbing is reachable:

```bash
ls -la /dev/net/tun        # should print a character device
ip link                    # should list lo + your container's eth0
sudo ./scripts/net-up.sh   # should create tun0 = 10.0.0.1/24
ip addr show tun0          # confirm tun0 is up with 10.0.0.1
sudo ./scripts/net-down.sh # clean up
sudo tcpdump --version     # should print a version
go version                 # should be 1.22 or newer
```

If any of those fail, fix them before moving on — you'll need all of them later.

## Done when

- `go.mod` exists at the repo root.
- `make dev` succeeds and drops you into a Linux shell with `go`, `tcpdump`, `ip`, and `python3` available.
- `sudo ./scripts/net-up.sh` brings up `tun0` with `10.0.0.1/24` (then `net-down.sh` removes it).
- You can articulate (to yourself, no test for this): what a TUN device is, what L3 means, why `10.0.0.1` is the kernel/peer and `10.0.0.2` is your stack, and where TCP sits relative to IP.

Run `/review` when you think you're done.
