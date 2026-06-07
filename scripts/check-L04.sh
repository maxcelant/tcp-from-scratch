#!/usr/bin/env bash
# L04: icmp-echo replies to pings -> the kernel sees ICMP echo replies.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

cleanup() { kill "${PROG_PID:-}" 2>/dev/null || true; net_down; }
trap cleanup EXIT

info "building cmd/icmp-echo"
go build -o "${TMP_DIR}/icmp-echo" ./cmd/icmp-echo || fail "build failed"

net_up
"${TMP_DIR}/icmp-echo" >/dev/null 2>&1 &
PROG_PID=$!
sleep 0.5

info "pinging ${STACK_ADDR} (your stack should reply)"
PING_OUT="$(ping -c 3 -W 2 "$STACK_ADDR" 2>&1 || true)"
echo "$PING_OUT" | sed 's/^/    /'

RECV="$(echo "$PING_OUT" | grep -oE '[0-9]+ received' | grep -oE '^[0-9]+' || echo 0)"
[ "${RECV:-0}" -ge 1 ] || fail "no echo replies received. Check ICMP type=0, the recomputed ICMP + IP checksums, and that src/dst are swapped."

green "L04 OK: ${RECV}/3 echo replies. Your IPv4 marshal + checksum work end-to-end."
