# TCP From Scratch (in Go)

Build a working userspace TCP stack in Go, one lesson at a time. By the end you'll have a binary (`curl-lite`) that opens a TUN device, hand-crafts IPv4 + TCP packets, performs a real 3-way handshake with a Python HTTP server, sends `GET /`, and prints the response — all using **your** TCP implementation, not the kernel's.

## What this is

A guided, hands-on tutorial split into **14 bite-sized lessons** under [`lesson/`](./lesson). Each lesson is a self-contained HTML page (open [`lesson/index.html`](./lesson/index.html) in a browser) that explains the background (concepts + RFC pointers with rich diagrams), tells you what to implement, shows you how to test it manually with `tcpdump`/`nc`, and lists what the `/review` skill will check before you move on.

**You write every line of Go code.** The repository scaffolds the dev environment, lesson content, test fixtures, and verification scripts — but no `internal/*.go` or `cmd/*.go` ever ships pre-written. The point is to build intuition, not copy-paste.

## What you'll build

```
                ┌──────────────────────────────────────┐
   your Go ───► │  cmd/curl-lite/main.go  (10.0.0.2)   │
                │  └──► tcp.Dial(...)                  │
                │       └──► internal/tcp (handshake,  │
                │             retransmit, FIN)         │
                │            └──► internal/ipv4        │
                │                  (+ internal/checksum)│
                │                  └──► internal/tun   │
                │                        └──► /dev/net/tun
                └──────────────────────────────────────┘
                                  │
                              (L3 packets)
                                  │
                       ┌──────────▼─────────────────────┐
                       │  Linux kernel = the peer        │
                       │  tun0 = 10.0.0.1                │
                       │  python3 -m http.server         │
                       └─────────────────────────────────┘
```

No network namespace, no second host. The TUN interface address `10.0.0.1`
is the kernel's side; your stack claims `10.0.0.2` (routed to the tun fd). The
kernel's own TCP stack is your test peer — and since it drops bad-checksum
segments, "did the kernel reply?" is a free end-to-end checksum validator.

## Prerequisites

- **Docker** (Desktop or Engine — anything with `docker compose v2`).
- Roughly 30–60 minutes per lesson; 14 lessons total.
- Basic Go familiarity (you can write a `main()`, use slices, structs, goroutines). **No prior networking knowledge required** — each lesson teaches the concepts it needs.

You do **not** need a Linux machine — the entire stack runs inside a Docker container that has `iproute2`, `tcpdump`, `tshark`, and `/dev/net/tun` available.

## Getting started

```bash
make dev           # build image, drop into a Linux shell in /workspace
```

Then open the lessons in your browser (the repo is bind-mounted, so open them from the host):

```bash
open lesson/index.html        # macOS — or just double-click it
# xdg-open lesson/index.html  # Linux
# ... read lesson 0, then implement what it says ...
```

Then from your editor/terminal (host or container — either works because the repo is bind-mounted), ask Claude Code:

- **`/review`** — runs the checks for your current lesson. On green, advances you to the next lesson automatically.
- **`/hint`** — gives you a Socratic nudge for the current lesson. Repeat for escalating hints. Never gives you the answer outright.

## How lessons are structured

Each `lesson/NN-*.html` has:

1. **Background** — what concepts you need, with RFC pointers and diagrams.
2. **What to implement** — files, types, functions (by name and signature contract, not body).
3. **How to test it yourself** — manual `tcpdump` / `nc` / `ping` commands.
4. **Done when** — what `/review` will check before letting you advance.

## Lesson map

| # | Title | You'll build |
|---|---|---|
| 00 | Intro & Setup | `go.mod`, Docker env verified |
| 01 | Opening a TUN device | `internal/tun`, `cmd/tcpdump-lite` |
| 02 | Parsing IPv4 headers | `internal/ipv4` (parse) |
| 03 | The Internet checksum (RFC 1071) | `internal/checksum` |
| 04 | Serializing IPv4 + ICMP echo | `internal/ipv4` (marshal), `cmd/icmp-echo` |
| 05 | TCP header parse/serialize | `internal/tcp/header.go` |
| 06 | TCB & state machine skeleton | `internal/tcb` (pure FSM) |
| 07 | Passive open: SYN → SYN/ACK | `internal/tcp/listener.go`, demux |
| 08 | Completing the handshake | SynRcvd → Established |
| 09 | Receiving data + ACK | `Conn.Read`, receive buffer |
| 10 | Sending data | `Conn.Write`, send buffer, segmentation |
| 11 | Retransmission (RTO) | retransmit queue, simple timer |
| 12 | Active open (client) | `tcp.Dial` |
| 13 | FIN teardown | `Conn.Close`, TimeWait |
| 14 | Capstone: `curl-lite` | end-to-end HTTP/1.0 over your stack |

## Repo layout

```
.
├── Dockerfile / docker-compose.yml   # dev environment
├── Makefile                          # convenience targets
├── lesson/                           # 14 HTML lessons + index.html (open in a browser, read in order)
│   └── assets/                        # shared stylesheet + JS for the lessons
├── testdata/                         # golden hex packet fixtures
├── scripts/                          # TUN setup + per-lesson integration checks
├── .claude/skills/                   # /review and /hint skills
├── .progress                         # tracks your current lesson
│
├── internal/    ← you create these as you progress
│   ├── tun/         (L01)
│   ├── checksum/    (L03)
│   ├── ipv4/        (L02, L04)
│   ├── tcp/         (L05, L07–L13)
│   └── tcb/         (L06, L09–L13)
└── cmd/         ← you create these too
    ├── tcpdump-lite/  (L01)
    ├── icmp-echo/     (L04)
    ├── tcp-echo/      (L09–L11)
    └── curl-lite/     (L14)
```

## What this is NOT

- **Not a production TCP stack.** No congestion control, no SACK, no window scaling, no PMTUD. You'll know enough by lesson 14 to add them if you want.
- **Not a Go tutorial.** You'll learn good Go (SOLID boundaries, `io.Reader`/`io.Writer` interfaces, table-driven tests), but the lessons assume you can read and write basic Go.
- **Not a copy-paste exercise.** If you `/hint` your way to the answer, you're cheating yourself. The capstone only feels like an accomplishment if you wrote every byte.

## When you're stuck

1. Re-read the lesson's **Background** section.
2. Run `/hint` — first hint is conceptual, later hints point at the specific RFC section, last hint points at common bugs.
3. Look at `tcpdump` output with `make tcpdump` — your stack is wrong if the bytes on the wire are wrong.
4. Last resort: read the RFC. [RFC 793](https://www.rfc-editor.org/rfc/rfc793) (TCP) and [RFC 791](https://www.rfc-editor.org/rfc/rfc791) (IPv4) are short and surprisingly readable.

Now: `make dev`, then open [`lesson/index.html`](./lesson/index.html) in your browser and start with lesson 0.
