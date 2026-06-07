---
id: "14"
title: "Capstone: speak HTTP/1.0"
requires:
  files:
    - cmd/curl-lite/main.go
  symbols:
    - { pkg: ./internal/tcp, name: Dial }
    - { pkg: ./internal/tcp, name: Conn.Read }
    - { pkg: ./internal/tcp, name: Conn.Write }
    - { pkg: ./internal/tcp, name: Conn.Close }
  lints:
    - cmd-builds
  integration: scripts/check-L14.sh
hints:
  - "There's no new protocol here. curl-lite = Dial + Write the request + io.ReadAll the response + Close. If each of those works individually (L09–L13), the capstone is plumbing."
  - "An HTTP/1.0 request is text: `GET / HTTP/1.0\\r\\nHost: <host>\\r\\n\\r\\n`. The server replies with headers + body, then closes the connection — which is how you know the response is complete (read until io.EOF)."
  - "HTTP/1.0 (not 1.1) is the right choice: the server closes after responding, so you don't need to parse Content-Length or chunked encoding. Read until EOF and you have the whole response."
  - "Common bug: not flushing/closing your write side, or closing too early. Send the full request (with the blank line!) and then read. The blank line (\\r\\n\\r\\n) is what tells the server the request is done."
  - "If you get a connection but no response bytes, check your Conn.Read returns received data before EOF — re-run the L09/L10 integration checks."
---

# Lesson 14 — Capstone: speak HTTP/1.0

This is it. You'll write `curl-lite`: a program that uses **your** TCP stack to connect to a real HTTP server, send a `GET /` request, and print the response. Every byte — the IP header, the TCP handshake, the data segments, the ACKs, the FIN — is produced by code you wrote. The kernel just shuttles opaque bytes between your TUN device and the server.

## Background

### Why this proves everything

HTTP/1.0 over TCP exercises your entire stack end to end:

1. **`Dial`** (L12) → 3-way handshake (L07, L08) → ESTABLISHED.
2. **`Write`** (L10) the HTTP request → segmentation, checksums, the peer's ACKs advance SND.UNA.
3. **`Read`** (L09) the response → in-order delivery, your ACKs advance RCV.NXT.
4. Lost packets? **Retransmission** (L11) recovers silently.
5. Server finishes, sends **FIN** (L13) → you read `io.EOF`, you `Close()`.

If `curl-lite` prints a valid HTTP response, you have built a working TCP stack.

### Why HTTP/1.0 specifically

In HTTP/1.0, the server sends its response and then **closes the connection**. "Response complete" = "connection closed" = your `Read` returns `io.EOF`. No need to parse `Content-Length` or chunked transfer encoding — just `io.ReadAll(conn)`. (HTTP/1.1 keeps the connection alive and would require you to parse framing — out of scope.)

### The request format

```
GET / HTTP/1.0\r\n
Host: 10.0.0.1\r\n
\r\n
```

Three lines: request line, one header, blank line. The blank line (`\r\n\r\n` at the end) terminates the request. Note `\r\n`, not `\n` — HTTP uses CRLF.

### The response

```
HTTP/1.0 200 OK\r\n
Server: SimpleHTTP/0.6 Python/3.x\r\n
Date: ...\r\n
Content-type: text/html\r\n
Content-Length: ...\r\n
\r\n
<html>... body ...</html>
```

You just print all of it. Optionally split headers from body at the first `\r\n\r\n`, but printing the raw response is enough for the capstone.

## What to implement

### `cmd/curl-lite/main.go`

```
// Usage: curl-lite http://10.0.0.1:8080/
//   (or:  curl-lite 10.0.0.1:8080  — your call on URL parsing depth)
```

The flow:
1. Parse the target host:port (and path) from os.Args. A minimal `net/url` parse, or just accept `host:port` and assume path `/`.
2. `conn, err := tcp.Dial(netip.MustParseAddrPort(hostport))`.
3. Build the request string and `conn.Write([]byte(req))`.
4. `resp, err := io.ReadAll(conn)` — reads until `io.EOF` (the server's FIN).
5. Print `resp` to stdout.
6. `conn.Close()`.

Because your `Conn` implements `io.Reader`, `io.Writer`, and `io.Closer`, this is almost entirely stdlib glue. That's the reward for respecting the interfaces all along.

Keep it clean: parse args, handle errors with clear messages, don't leak the connection on error paths (`defer conn.Close()`).

## How to test it yourself

```bash
go build ./cmd/curl-lite
sudo ./scripts/net-up.sh
python3 -m http.server 8080 --bind 10.0.0.1 &

sudo ./curl-lite http://10.0.0.1:8080/
```

Expected output: an HTTP/1.0 response — status line, headers, and a directory listing HTML body. 

Run `make tcpdump` in another terminal and watch the **complete life of a TCP connection** scroll by: SYN, SYN/ACK, ACK, PSH/ACK (your GET), the server's response segments with your ACKs, then FIN/ACK both ways. That capture is the artifact of everything you built.

## Done when

- `cmd/curl-lite` builds.
- The integration check `scripts/check-L14.sh`:
  1. Brings up `tun0` and starts `python3 -m http.server` on `10.0.0.1`.
  2. Runs `curl-lite` against it with a timeout.
  3. Asserts stdout starts with `HTTP/1.0 200`.
  4. Captures a pcap and confirms the full handshake + data + FIN appear, with no RST and no retransmit storm.

When it's green, `/review` prints: **🏆 You have built TCP.**

## After this — where to go next

You have a real TCP stack. If you want to keep going:

- **Out-of-order reassembly**: buffer segments with `seq > RCV.NXT` instead of dropping them.
- **Congestion control**: add a congestion window (cwnd), slow start, and congestion avoidance (RFC 5681). This is the big one — it's what makes TCP fair on shared networks.
- **Delayed ACKs & Nagle's algorithm**: reduce tiny-packet overhead.
- **Window scaling, SACK, timestamps**: the modern TCP options (RFC 7323, RFC 2018).
- **A real `net.Listener`/`net.Conn` adapter**: make your stack a drop-in `net.Dial` replacement and run an off-the-shelf HTTP client over it.
- **IPv6**: generalize the IP layer.

But first — savour it. You sent TCP packets you built, to a real server, and got real bytes back. That's the intuition you came for.
