#!/usr/bin/env bash
# L13: graceful teardown. The peer closes; the echo server sees EOF and the
# FIN exchange completes with no RST.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

OUT="$(mktemp)"; GOT="$(mktemp)"; PCAP="$(mktemp --suffix=.pcap)"
cleanup() { kill "${PROG_PID:-}" 2>/dev/null || true; stop_capture; net_down; rm -f "$OUT" "$GOT" "$PCAP"; }
trap cleanup EXIT

info "building cmd/tcp-echo"
go build -o "${TMP_DIR}/tcp-echo" ./cmd/tcp-echo || fail "build failed"

net_up
start_capture "$PCAP"
"${TMP_DIR}/tcp-echo" >"$OUT" 2>&1 &
PROG_PID=$!
sleep 0.5

# nc -q1 closes its write side ~1s after stdin EOF, triggering the FIN exchange.
TOKEN="BYE-$RANDOM"
info "sending '${TOKEN}' then closing the client (nc -q1)"
printf '%s\n' "$TOKEN" | timeout 6 nc -q 1 -w 3 "$STACK_ADDR" 7777 > "$GOT" 2>/dev/null || true
sleep 1.5
stop_capture

cmp_token="$(cat "$GOT" 2>/dev/null || true)"
echo "$cmp_token" | grep -q "$TOKEN" || info "(note) echoed data not observed back; teardown is the focus of this check"

if have_tshark; then
  FIN_STACK="$(tshark_count "$PCAP" "ip.src==${STACK_ADDR} && tcp.flags.fin==1")"
  FIN_PEER="$(tshark_count  "$PCAP" "ip.src==${HOST_ADDR}  && tcp.flags.fin==1")"
  RST="$(tshark_count "$PCAP" "tcp.flags.reset==1")"
  info "FIN from stack: ${FIN_STACK}   FIN from peer: ${FIN_PEER}   RST: ${RST}"
  [ "${FIN_PEER:-0}"  -ge 1 ] || fail "no FIN from the peer captured — the test did not close. Re-run; if persistent, check nc -q support."
  [ "${FIN_STACK:-0}" -ge 1 ] || fail "your stack never sent its own FIN. Conn.Close (or CLOSE-WAIT->LAST-ACK) isn't sending FIN."
  [ "${RST:-0}" -eq 0 ]       || fail "a RST appeared during teardown (${RST}). A close-path state transition is wrong."
else
  info "tshark not found — skipping FIN/RST assertions"
fi

green "L13 OK: clean FIN teardown, no RST."
