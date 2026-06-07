#!/usr/bin/env bash
# L01: tcpdump-lite reads raw packets off tun0 and prints them.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

OUT="$(mktemp)"
cleanup() { kill "${PROG_PID:-}" 2>/dev/null || true; net_down; rm -f "$OUT"; }
trap cleanup EXIT

info "building cmd/tcpdump-lite"
go build -o "${TMP_DIR}/tcpdump-lite" ./cmd/tcpdump-lite || fail "build failed"

net_up
"${TMP_DIR}/tcpdump-lite" "$TUN" >"$OUT" 2>/dev/null &
PROG_PID=$!
sleep 0.5

info "sending 3 ICMP echo requests to ${STACK_ADDR} (no reply expected yet)"
ping -c 3 -W 1 "$STACK_ADDR" >/dev/null 2>&1 || true
sleep 0.5

# tcpdump-lite prints one line per packet, each starting with "[<len>]".
LINES="$(grep -c '^\[[0-9]' "$OUT" || true)"
info "packet lines printed: ${LINES}"
[ "${LINES:-0}" -ge 3 ] || fail "expected >=3 packet lines, got ${LINES}. Is Read returning one packet per call and is main printing them?"

green "L01 OK: tun device opened and packets read."
