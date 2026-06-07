#!/usr/bin/env bash
# L14 capstone: curl-lite speaks HTTP/1.0 to a real server using your stack.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

OUT="$(mktemp)"; PCAP="$(mktemp --suffix=.pcap)"
cleanup() {
  kill "${SRV_PID:-}" 2>/dev/null || true
  stop_capture; net_down; rm -f "$OUT" "$PCAP"
}
trap cleanup EXIT

info "building cmd/curl-lite"
go build -o "${TMP_DIR}/curl-lite" ./cmd/curl-lite || fail "build failed"

net_up
info "starting real HTTP server on ${HOST_ADDR}:8080"
python3 -m http.server 8080 --bind "$HOST_ADDR" >/dev/null 2>&1 &
SRV_PID=$!
sleep 0.7

start_capture "$PCAP"
info "running: curl-lite http://${HOST_ADDR}:8080/"
timeout 15 "${TMP_DIR}/curl-lite" "http://${HOST_ADDR}:8080/" > "$OUT" 2>&1 || true
sleep 0.5
stop_capture

head -1 "$OUT" | sed 's/^/    /'
grep -q "^HTTP/1\.0 200" "$OUT" || { sed 's/^/    /' "$OUT" | head -20; fail "did not receive 'HTTP/1.0 200'. Walk back through Dial/Write/Read/Close."; }

if have_tshark; then
  SYN="$(tshark_count "$PCAP" "ip.src==${STACK_ADDR} && tcp.flags.syn==1 && tcp.flags.ack==0")"
  FIN="$(tshark_count "$PCAP" "tcp.flags.fin==1")"
  RST="$(tshark_count "$PCAP" "tcp.flags.reset==1")"
  info "SYN(out): ${SYN}   FINs: ${FIN}   RST: ${RST}"
  [ "${SYN:-0}" -ge 1 ] || fail "no outbound SYN — Dial never started."
  [ "${FIN:-0}" -ge 1 ] || fail "no FIN seen — the connection never closed cleanly."
  [ "${RST:-0}" -eq 0 ] || info "(warning) ${RST} RST(s) observed; response still parsed OK."
fi

green "==============================================="
green "  🏆  You have built TCP. Capstone is green.  "
green "==============================================="
