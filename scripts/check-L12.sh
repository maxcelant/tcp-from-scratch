#!/usr/bin/env bash
# L12: active open. Your stack dials a REAL server (kernel http.server) and
# reaches ESTABLISHED.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

MOD="$(module_path)"
OUT="$(mktemp)"; PCAP="$(mktemp --suffix=.pcap)"
cleanup() {
  kill "${PROG_PID:-}" 2>/dev/null || true
  kill "${SRV_PID:-}" 2>/dev/null || true
  stop_capture; net_down; clean_tmp; rm -f "$OUT" "$PCAP"
}
trap cleanup EXIT

read -r -d '' SRC <<EOF || true
package main
import (
	"log"
	"net/netip"
	"time"
	tcp "${MOD}/internal/tcp"
)
func main() {
	c, err := tcp.Dial(netip.MustParseAddrPort("${HOST_ADDR}:8080"))
	if err != nil { log.Fatalf("Dial: %v", err) }
	log.Printf("STATE=%s", c.State())
	time.Sleep(2 * time.Second)
	_ = c.Close()
}
EOF
gen_helper dial "$SRC" >/dev/null

info "building dial helper"
go build -o "${TMP_DIR}/dial.bin" "${TMP_DIR}/dial/main.go" || fail "helper build failed — check tcp.Dial signature"

net_up
info "starting real HTTP server on ${HOST_ADDR}:8080 (the kernel is the peer)"
python3 -m http.server 8080 --bind "$HOST_ADDR" >/dev/null 2>&1 &
SRV_PID=$!
sleep 0.7

start_capture "$PCAP"
"${TMP_DIR}/dial.bin" >"$OUT" 2>&1 &
PROG_PID=$!
sleep 3
stop_capture

grep -q "STATE=ESTABLISHED" "$OUT" || { sed 's/^/    /' "$OUT"; fail "Dial did not reach ESTABLISHED. Check the SYN-SENT handler: validate SYN/ACK, set IRS/RCV.NXT, send the ACK."; }

if have_tshark; then
  RST="$(tshark_count "$PCAP" "tcp.flags.reset==1")"
  [ "${RST:-0}" -eq 0 ] || fail "a RST appeared (${RST}). Likely a bad checksum on your SYN, or the kernel rejecting your source address."
fi

green "L12 OK: active open to a real server succeeded."
