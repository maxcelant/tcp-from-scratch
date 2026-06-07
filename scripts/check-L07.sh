#!/usr/bin/env bash
# L07: passive open. A SYN to the listener produces a valid SYN/ACK.
# Oracle: the kernel (acting as nc's client) only sends the third-leg ACK if
# the SYN/ACK had a correct checksum and an acceptable ack number. So "did the
# kernel ACK?" validates the SYN/ACK end to end.
source "$(dirname "$0")/lib.sh"
need_root "$@"
cd "$REPO_ROOT"

MOD="$(module_path)"
PCAP="$(mktemp --suffix=.pcap)"
cleanup() { kill "${PROG_PID:-}" 2>/dev/null || true; stop_capture; net_down; clean_tmp; rm -f "$PCAP"; }
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
	l, err := tcp.Listen(netip.MustParseAddrPort("${STACK_ADDR}:7777"))
	if err != nil { log.Fatalf("Listen: %v", err) }
	defer l.Close()
	go func() { _, _ = l.Accept() }()
	time.Sleep(8 * time.Second)
}
EOF
gen_helper listen "$SRC" >/dev/null

info "building listener helper"
go build -o "${TMP_DIR}/listen.bin" "${TMP_DIR}/listen/main.go" || fail "helper build failed — check tcp.Listen / tcp.Listener signatures"

net_up
start_capture "$PCAP"
"${TMP_DIR}/listen.bin" >/dev/null 2>&1 &
PROG_PID=$!
sleep 0.5

info "opening a connection to ${STACK_ADDR}:7777 from the kernel (nc)"
timeout 3 nc -w 2 "$STACK_ADDR" 7777 </dev/null >/dev/null 2>&1 || true
sleep 0.5
stop_capture

if have_tshark; then
  SYNACK="$(tshark_count "$PCAP" "ip.src==${STACK_ADDR} && tcp.flags.syn==1 && tcp.flags.ack==1")"
  KACK="$(tshark_count "$PCAP" "ip.src==${HOST_ADDR} && tcp.flags.syn==0 && tcp.flags.ack==1")"
  info "SYN/ACK from stack: ${SYNACK}    third-leg ACK from kernel: ${KACK}"
  [ "${SYNACK:-0}" -ge 1 ] || fail "no SYN/ACK emitted by your stack. Check the SYN handler + sendSegment."
  [ "${KACK:-0}" -ge 1 ]   || fail "SYN/ACK emitted but the kernel never ACKed it. Almost always a bad pseudo-header checksum or wrong ack number (should be SYN.seq+1)."
else
  info "tshark not found — skipping pcap assertions (install tshark for full validation)"
fi

green "L07 OK: valid SYN/ACK accepted by the peer kernel."
